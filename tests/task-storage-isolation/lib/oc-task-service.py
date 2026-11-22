#!/usr/bin/env python3
"""Parent-side broker service for opencode task-storage isolation (ORCH-4-10-3).

Runs on the host next to the opencode server process and listens on an
AF_UNIX socket inside a 0700 runtime directory. The opencode task-storage
guard plugin rewrites every shell tool call from a normal-role session
into a bridge-client invocation; the client submits the original command
as a single JSON string element, so no shell reconstruction ever happens
on the transport. The service gates each request on:

- a session attribution token (0600 file beside the socket), NOT
  SO_PEERCRED's uid (same-uid children make it a no-op; the pid field
  IS used, to keep the control channel opencode-only),
- a session registry entry (session, agent) pair registered by the
  guard plugin over the control channel before it rewrites a call, so
  a model forging direct client invocations is refused,
- a request size cap and an argv width cap (the walking skeleton's
  unbounded recv loop, closed) and a wall-clock read window so a slow
  trickle sender cannot hold a connection past the window no matter how
  its chunks arrive, mirroring the landed ORCH-4-10-2 service gate,
- a per-role tasks-verb whitelist byte-aligned with the landed
  ORCH-4-9 verb contracts (tests/fixtures/task-access/role-verbs.sh),
- a shell-syntax screen: the sanctioned class is reached only when the
  shlex tokenization carries no live shell syntax (operators, pipes,
  redirects, substitutions, tilde/glob/brace expansion, comments,
  command-splitting newlines), so compound commands fall to the masked
  class instead of executing their tails unmasked,
- a per-verb argv policy on the parsed tokens: flag whitelists, the
  path policy on EVERY element (lexical, kernel-walk, and ancestor
  candidates must land inside the board repo), bare board-entry
  taskfile positionals, and bodies on the request stdin only
  (child-named body files are refused), mirroring the landed ORCH-4-10-2
  service gates,
- service-bound write attribution: --from is rewritten server-side to
  a token-derived channel label and TASKS_SESSION is pinned to it;
  claimed identities survive only in the audit log.

Sanctioned verbs execute the PARSED tokens unmasked on the host (never
the original bash -c string); every other command executes under
bubblewrap with the repository's live .tasks trees masked (main
checkout, every git worktree, and the request cwd), while the cwd,
/tmp, and the main .git directory stay writable so ordinary worker
flows (build, test, commit) keep working. Every request and its
outcome land in a JSONL audit log; refused requests never execute.

Usage:
    oc-task-service.py --socket PATH --repo MAIN_ROOT --audit-log PATH
                      [--token-file PATH]

The service runs until its socket file is removed or the process is
signalled; concurrent connections are served on threads.
"""

import argparse
import hashlib
import json
import os
import pathlib
import re
import shlex
import shutil
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time

READ_CHUNK = 65536
MAX_REQUEST_BYTES = 1024 * 1024
REQUEST_RECV_WINDOW_SECONDS = 30
MAX_ARGV = 64
MAX_ARGV_ELEMENT_BYTES = 4096
DEFAULT_TIMEOUT_SECONDS = 3600
MAX_RESPONSE_BYTES = 8 * 1024 * 1024
# Hard cap on the child output the service buffers; overflow kills the
# child. Mirrors the pi escape channel's OUTPUT_CAP_BYTES so neither
# broker's memory grows with child output.
OUTPUT_CAP_BYTES = 16 * 1024 * 1024

# Per-role sanctioned verb sets, byte-aligned with the landed verb
# contracts (tests/fixtures/task-access/role-verbs.sh; verb-map.md is
# the prose form). The manager never brokers (the guard plugin exempts
# it), so no manager row exists here.
ROLE_VERBS = {
    "worker": {"show", "log", "report"},
    "planner": {"list", "show", "reports", "edit", "log", "report"},
    "reviewer": {"show", "reports", "list", "report"},
    "advisor": {"show", "reports", "list", "log", "report"},
    "scout": set(),
    "verifier": {"render"},
}

MASK_ENV_KEYS = ("PATH", "HOME", "TERM", "LANG", "LC_ALL", "TMPDIR",
                 "TASKS_SESSION", "XDG_STATE_HOME")

# Per-verb flag policy mirroring the tasks CLI parsers: SANCTIONED_FLAGS
# lists the flags each verb admits, VALUE_FLAGS the ones consuming the
# following element; every other non-flag element is a positional.
SANCTIONED_FLAGS = {
    "show": ("--json", "--raw", "--section", "--tail", "--project",
             "--entries", "--bytes", "--role"),
    "list": ("--json", "--lane", "--limit", "--offset"),
    "reports": ("--json", "--include-body", "--limit", "--offset"),
    "log": ("--from",),
    "report": ("--slug", "--from", "--digest"),
    "edit": ("--section", "--append"),
    "render": (),
}
VALUE_FLAGS = {
    "show": ("--section", "--tail", "--entries", "--bytes", "--role"),
    "list": ("--lane", "--limit", "--offset"),
    "reports": ("--limit", "--offset"),
    "log": ("--from",),
    "report": ("--slug", "--from", "--digest"),
    "edit": ("--section",),
    "render": (),
}
# The service cwd is the board; --dir redirection is never sanctioned.
DENIED_FLAGS = ("--dir",)
# Task files are bare board-entry names on the channel: a positional
# carrying a slash would ride the CLI's file-path resolution instead.
BOARD_ENTRY_PATTERN = re.compile(r"^[^/\0]+$")
STDIN_MARKER = "-"
# Verbs whose section/report bodies ride the request stdin; child-named
# body files are refused outright (the pi channel's closed read lane).
STDIN_BODY_VERBS = ("report", "edit")
# Write verbs whose --from attribution is rewritten server-side; edit
# attributes through the pinned TASKS_SESSION instead (no --from flag).
WRITE_FROM_VERBS = ("log", "report")

# Characters carrying shell meaning when UNQUOTED (operators, pipes,
# redirects, separators, substitutions, brace/glob expansion) plus
# command-splitting newlines; inside double quotes only substitution
# stays live. Tilde and comment leaders are live at word start only,
# matching where bash and shlex both act on them.
LIVE_UNQUOTED = set(";&|<>(){}$`*?[\n\r")
LIVE_IN_DOUBLE = set("$`")
WORD_START_LIVE = ("~", "#")


def audit(log_path: str, record: dict) -> None:
    record["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())
    with open(log_path, "a") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


# Session attribution registry: held in memory, never on disk (the
# BrokerService instance owns it as state["registry"]). The guard plugin
# (running inside the opencode server process) registers each (session,
# agent) pair over the control channel before it rewrites a call; exec
# requests must carry a registered pair. A sandboxed client can steal the
# token file (same uid), but it cannot mint pairs: control requests are
# accepted only from a peer whose /proc/<pid>/exe is the opencode binary
# itself, so model-forged registrations are refused and cross-session
# impersonation has no readable source.

def verify_runtime_dir(socket_path: str) -> None:
	"""Refuse to bind unless the socket dir is a 0700 dir owned by us.

	The pi service's socket-visibility gate, mirrored so neither broker
	binds outside 0700 visibility regardless of which entry point
	started it (main, or direct class construction).
	"""
	parent = os.path.dirname(os.path.abspath(socket_path)) or "/"
	try:
		stat = os.stat(parent)
	except OSError as error:
		raise SystemExit(f"socket dir unusable: {parent}: {error}")
	if not os.path.isdir(parent):
		raise SystemExit(f"socket path parent is not a directory: {parent}")
	if stat.st_uid != os.getuid():
		raise SystemExit(f"socket dir not owned by the invoking user: {parent}")
	if stat.st_mode & 0o777 != 0o700:
		raise SystemExit(
			f"socket dir mode is {oct(stat.st_mode & 0o777)}, "
			f"refusing to bind outside 0700 visibility: {parent}")


def peer_pid(conn: socket.socket) -> int:
    try:
        creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED,
                                struct.calcsize("3I"))
        return struct.unpack("3I", creds)[0]
    except OSError:
        return 0


def peer_exe(conn: socket.socket) -> str:
    pid = peer_pid(conn)
    if not pid:
        return ""
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


ANCESTRY_WALK_DEPTH = 64


def peer_chain(pid: int) -> list:
    """The connecting peer's (pid, exe) ancestry chain, nearest first and
    capped at ANCESTRY_WALK_DEPTH hops. The walk stops early when /proc
    stops resolving (vanished process, namespace edge); the gate reads
    an unresolvable chain as refusal, never as acceptance."""
    chain = []
    current = pid
    for _ in range(ANCESTRY_WALK_DEPTH):
        if current <= 1:
            break
        try:
            exe = os.path.realpath(f"/proc/{current}/exe")
        except OSError:
            exe = ""
        chain.append((current, exe))
        try:
            with open(f"/proc/{current}/stat", "rb") as stat_handle:
                stat = stat_handle.read().decode(errors="replace")
            current = int(stat.rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return chain


def spawner_pin() -> str:
    """The exe of the process that launched this service: in production
    the guard plugin's host (the opencode server binary), in a suite the
    driver process. Every accepted exec peer must reach this exe through
    its ancestry without passing through the service process."""
    try:
        return os.path.realpath(f"/proc/{os.getppid()}/exe")
    except OSError:
        return ""


def exec_peer_allowed(gate: dict, peer_pid_value: int,
                      claimed_ancestor) -> tuple:
    """Decide an exec request's peer ancestry (the registered-pair
    replay gate). A peer descending from the broker service process is
    refused outright: masked children and brokered runs are exactly that,
    and replaying a stolen registered pair must not promote them. Any
    other peer is accepted only when its chain reaches the pinned
    spawner exe; a claimed --peer-ancestor ties that acceptance to the
    exact spawner pid the guard passes."""
    if gate is None:
        return True, ""
    chain = peer_chain(peer_pid_value)
    if any(pid == gate["service_pid"] for pid, _ in chain):
        return False, "exec peer descends from the broker service process"
    if claimed_ancestor is not None:
        for pid, exe in chain:
            if pid == claimed_ancestor:
                if exe == gate["pin"]:
                    return True, ""
                return False, "peer-ancestor pid does not carry the pinned executor"
        return False, "peer-ancestor pid is not in the peer's ancestry"
    if any(exe == gate["pin"] for _, exe in chain):
        return True, ""
    return False, "peer chain does not reach the pinned executor"


def is_opencode_peer(conn: socket.socket) -> bool:
    exe = peer_exe(conn)
    return exe.endswith("/opencode")


def worktree_roots(repo: str) -> list:
    try:
        out = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            cwd=repo, capture_output=True, text=True, timeout=30,
        )
        roots = []
        for line in out.stdout.splitlines():
            if line.startswith("worktree "):
                roots.append(line[len("worktree "):].strip())
        if repo not in roots:
            roots.append(repo)
        return roots
    except Exception:  # noqa: BLE001 - mask enumeration must not kill the service
        return [repo]


def mask_paths(repo: str, cwd: str) -> list:
    paths = []
    for root in worktree_roots(repo):
        candidate = os.path.join(root, ".tasks")
        if candidate not in paths:
            paths.append(candidate)
    if cwd:
        resolved = os.path.realpath(cwd)
        # The request cwd may sit at any depth inside a standalone board
        # tree, so every ancestor of the resolved cwd up to the filesystem
        # root contributes its candidate; a fixed-depth candidate pair
        # always leaves some depth's board readable through the bwrap
        # mask. The membership check dedupes against the worktree
        # candidates above.
        current = resolved
        while True:
            candidate = os.path.join(current, ".tasks")
            if os.path.isdir(candidate) and candidate not in paths:
                paths.append(candidate)
            parent = os.path.dirname(current)
            if parent == current:
                break
            current = parent
    return paths


def bash_command(argv: list):
    """Return the raw command string when the transport is a shell call
    (["/bin/bash", "-c", command]), else None. Plain-list transports
    never pass through a shell, so the syntax screen does not apply to
    them and the token list is executed as received."""
    if len(argv) == 3 and os.path.basename(argv[0]) in ("bash", "sh") \
            and argv[1] == "-c" and isinstance(argv[2], str):
        return argv[2]
    return None


def command_tokens(argv: list) -> list:
    # The broker transport carries the original command as ONE argv element
    # (["/bin/bash", "-c", command]), so the whitelist matches the tokens
    # recovered from that string, not the transport argv itself. Tokenization
    # failure (unbalanced quotes) lands in the masked class, where bwrap
    # executes it safely.
    command = bash_command(argv)
    if command is None:
        return argv
    try:
        return shlex.split(command)
    except ValueError:
        return []


def carries_live_shell_syntax(command: str) -> bool:
    """True when the shell transport string still carries shell meaning
    after tokenization: any hit routes the command to the masked class,
    where bash's own parse executes inside the namespace with the board
    masked. Quote-aware by design: metacharacters inside single quotes
    are literal data both parsers agree on, while unquoted operators,
    substitutions, and expansion characters (and dollar/backtick inside
    double quotes) diverge the token list from what bash would run."""
    quote = None
    word_start = True
    index = 0
    length = len(command)
    while index < length:
        char = command[index]
        if quote == "'":
            if char == "'":
                quote = None
            index += 1
            continue
        if quote == '"':
            if char == '"':
                quote = None
            elif char == "\\":
                index += 1
            elif char in LIVE_IN_DOUBLE:
                return True
            index += 1
            continue
        if char == "\\":
            index += 2
            word_start = False
            continue
        if char == "'" or char == '"':
            quote = char
            word_start = False
            index += 1
            continue
        if char in WORD_START_LIVE and word_start:
            return True
        if char in LIVE_UNQUOTED:
            return True
        word_start = char in " \t"
        index += 1
    return False


def classify(agent: str, argv: list) -> str:
    verbs = ROLE_VERBS.get(agent)
    if verbs is None:
        return "unknown-role"
    tokens = command_tokens(argv)
    if len(tokens) < 2 or tokens[0] != "tasks" or tokens[1] not in verbs \
            or len(tokens) > MAX_ARGV:
        return "masked"
    command = bash_command(argv)
    if command is not None and carries_live_shell_syntax(command):
        return "masked"
    return "sanctioned"


def channel_label(token: str) -> str:
    """The service's provisioned write-attribution identity, derived
    from the session attribution token: stable per session, unique
    across sessions, and not choosable by a child. Every sanctioned
    board write attributes to this label regardless of what the request
    claims; claimed identities survive only in the audit log."""
    return "oc-channel-" + hashlib.sha256(token.encode()).hexdigest()[:16]


def bind_write_attribution(tokens: list, label: str) -> list:
    """Rewrite a write invocation so its attribution is service-bound:
    the claimed --from (and its value) is dropped and the channel label
    appended; read verbs pass through untouched."""
    if tokens[1] not in WRITE_FROM_VERBS:
        return tokens
    rebuilt = [tokens[0], tokens[1]]
    index = 2
    while index < len(tokens):
        if tokens[index] == "--from":
            index += 2
            continue
        rebuilt.append(tokens[index])
        index += 1
    return rebuilt + ["--from", label]


def kernel_walk(base: str, element: str) -> str:
    """Resolve element the way the kernel resolves it at open time:
    symlinks resolve the moment they are crossed and dot-dot applies to
    the RESOLVED target, so a path that lexically lands outside the
    board while opening inside it is still seen. Non-existing tails
    continue lexically from the deepest resolved prefix."""
    current = os.sep if element.startswith("/") else base
    for segment in element.split(os.sep):
        if segment in ("", "."):
            continue
        if segment == "..":
            current = os.path.dirname(current) or os.sep
            continue
        candidate = os.path.join(current, segment)
        try:
            current = os.path.realpath(candidate)
        except OSError:
            current = candidate
    return current


def path_candidates(repo_real: str, element: str) -> list:
    """Every absolute path the element could resolve to under open():
    the lexical candidate, the kernel-style walk, and the deepest
    existing ancestor's realpath. The same candidate set the guard
    plugin enforces, mirrored so the service cannot disagree with it."""
    lexical = os.path.normpath(
        element if element.startswith("/") else os.path.join(repo_real, element)
    )
    candidates = [lexical, kernel_walk(repo_real, element)]
    parts = lexical.split(os.sep)
    for cut in range(len(parts) - 1, 1, -1):
        head = os.sep.join(parts[:cut])
        tail = os.sep.join(parts[cut:])
        try:
            candidates.append(os.path.join(os.path.realpath(head or os.sep), tail))
            break
        except OSError:
            continue
    return candidates


def element_is_inside(repo_real: str, element: str) -> bool:
    """True when EVERY candidate resolution lands inside the board repo."""
    for candidate in path_candidates(repo_real, element):
        resolved = os.path.realpath(candidate)
        if resolved != repo_real and not resolved.startswith(repo_real + os.sep):
            return False
    return True


def validate_sanctioned(tokens: list, repo_real: str) -> list:
    """Per-verb argv policy over the parsed tokens; returns the exec
    argv and raises ValueError with a model-facing reason otherwise.
    Mirrors the landed pi service: flag whitelists per verb, the path
    policy on EVERY element (positionals and flag-attached values
    alike), bare board-entry taskfiles, and bodies on the request stdin
    only (child-named body files are refused)."""
    verb = tokens[1]
    allowed = SANCTIONED_FLAGS[verb]
    values = VALUE_FLAGS[verb]
    positionals = []
    expect_value = False
    for element in tokens[2:]:
        if expect_value:
            if element.startswith("--"):
                raise ValueError(
                    f"{verb}: flag value must not look like a flag: {element}")
            expect_value = False
            continue
        if element.startswith("--"):
            if element in DENIED_FLAGS or element.startswith("--dir="):
                raise ValueError("--dir board redirection is not a sanctioned shape")
            if element not in allowed:
                raise ValueError(f"flag {element} is not sanctioned for verb {verb}")
            if element in values:
                expect_value = True
            continue
        positionals.append(element)
    if expect_value:
        raise ValueError(f"{verb}: flag {tokens[-1]} requires a value")
    for element in tokens[2:]:
        if not element_is_inside(repo_real, element):
            raise ValueError(
                "argument resolves outside the board repo; the service never "
                f"opens child-named paths outside it: {element!r}")
    if verb in ("show", "reports"):
        if len(positionals) != 1 or not BOARD_ENTRY_PATTERN.match(positionals[0]):
            raise ValueError(f"{verb} takes exactly one bare taskfile positional")
    elif verb in ("list", "render"):
        if positionals:
            raise ValueError(f"{verb} takes no positional arguments")
    elif verb == "log":
        if len(positionals) < 2 or not BOARD_ENTRY_PATTERN.match(positionals[0]):
            raise ValueError("log takes a bare taskfile positional and a message")
    else:  # the stdin-body verbs
        if verb not in STDIN_BODY_VERBS:
            raise ValueError(f"verb {verb} has no positional policy")
        if len(positionals) < 1 or not BOARD_ENTRY_PATTERN.match(positionals[0]):
            raise ValueError(f"{verb} takes a bare taskfile positional")
        if len(positionals) > 2 or (len(positionals) == 2
                                    and positionals[1] != STDIN_MARKER):
            raise ValueError(
                f"{verb} bodies ride the request stdin only (taskfile [-]); "
                "child-named body files are refused")
    return [tokens[0], *tokens[1:]]


def sanitized_env(attribution: str = "") -> dict:
    """The sanitized execution env both paths share: only MASK_ENV_KEYS
    survives from the service environment, with TASKS_SESSION pinned to
    the service-bound attribution label when one is given."""
    env = {key: os.environ[key] for key in MASK_ENV_KEYS if key in os.environ}
    if attribution:
        env["TASKS_SESSION"] = attribution
    return env


def run_capped(argv: list, cwd: str, env: dict, timeout: int,
               stdin: str = "") -> dict:
    """Run argv with both output pipes pumped concurrently and
    hard-capped: overflow kills the child and returns the 125 refusal
    instead of buffering unbounded output in the service, and a child
    holding both pipes past the deadline is killed with the 124 timeout
    refusal. stdin, when given, rides the child's stdin and is bounded
    by the request cap that delivered it."""
    proc = subprocess.Popen(
        argv, cwd=cwd, env=env, stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    results = {}

    def pump(stream, key):
        chunks = []
        total = 0
        while True:
            chunk = stream.read(READ_CHUNK)
            if not chunk:
                break
            total += len(chunk)
            if total > OUTPUT_CAP_BYTES:
                proc.kill()
                results[key] = None
                return
            chunks.append(chunk)
        results[key] = b"".join(chunks)

    def feed():
        try:
            if stdin:
                proc.stdin.write(stdin.encode())
            proc.stdin.close()
        except (BrokenPipeError, OSError):
            pass

    threads = [
        threading.Thread(target=pump, args=(proc.stdout, "stdout")),
        threading.Thread(target=pump, args=(proc.stderr, "stderr")),
    ]
    writer = threading.Thread(target=feed)
    writer.start()
    for thread in threads:
        thread.start()
    deadline = time.monotonic() + timeout
    for thread in threads:
        thread.join(max(0.0, deadline - time.monotonic()))
    if any(thread.is_alive() for thread in threads):
        proc.kill()
        proc.wait()
        return finish(124, "", "refused: verb exceeded the execution timeout")
    writer.join(5)
    return_code = proc.wait()
    stdout, stderr = results.get("stdout"), results.get("stderr")
    if stdout is None or stderr is None:
        return finish(125, "", "refused: verb output exceeded the response cap")
    return finish(return_code, stdout.decode(errors="replace"), stderr.decode(errors="replace"))


def execute_sanctioned(exec_argv: list, cwd: str, timeout: int, stdin: str = "",
                       attribution: str = "", ground_root: str = "") -> dict:
    """Run the parsed tasks invocation only, never the original shell
    string, with a sanitized env whose TASKS_SESSION is pinned to the
    service-bound attribution label and whose TASKS_DIR is pinned to the
    validated cwd's repo/worktree root's .tasks tree (a scratch board
    resolves only through the explicit pin; the request cwd is already
    contained to those roots). Non-empty stdin (report/edit
    bodies) rides the subprocess stdin, bounded by the request cap that
    delivered it; output is pumped under the hard cap."""
    env = sanitized_env(attribution)
    if ground_root:
        env["TASKS_DIR"] = os.path.join(ground_root, ".tasks")
    resolved = shutil.which(exec_argv[0], path=env.get("PATH", ""))
    if resolved is None:
        return finish(126, "", f"{exec_argv[0]} not found in the broker PATH; "
                      "sanctioned execution refused")
    return run_capped([resolved, *exec_argv[1:]], cwd, env, timeout, stdin)


def transcript_store_paths() -> list:
    """Board content copied into the other harness's session store (the
    DC2 lane): the opencode storage dir and the pi agent sessions dir,
    resolved from the service's own environment like the child-facing
    bwrap argv builder does."""
    data_home = os.environ.get("XDG_DATA_HOME") or (
        os.environ.get("HOME", "") + "/.local/share")
    stores = [os.path.join(data_home, "opencode")]
    home = os.environ.get("HOME", "")
    if home:
        stores.append(os.path.join(home, ".pi", "agent", "sessions"))
    return stores


def execute_masked(argv: list, cwd: str, repo: str, timeout: int) -> dict:
    bwrap = ["bwrap"]
    for flag in ("--unshare-user", "--unshare-ipc", "--unshare-pid",
                 "--die-with-parent"):
        bwrap.append(flag)
    bwrap += ["--ro-bind", "/", "/"]
    bwrap += ["--dev", "/dev", "--proc", "/proc"]
    bwrap += ["--bind", "/tmp", "/tmp"]
    if cwd and os.path.isdir(cwd):
        bwrap += ["--bind", cwd, cwd]
    git_dir = os.path.join(repo, ".git")
    if os.path.exists(git_dir):
        bwrap += ["--bind", git_dir, git_dir]
    for mask in mask_paths(repo, cwd):
        if os.path.isdir(mask):
            bwrap += ["--tmpfs", mask]
    for store in transcript_store_paths():
        if os.path.isdir(store):
            bwrap += ["--tmpfs", store]
    bwrap += [argv[0], *argv[1:]]
    env = sanitized_env()
    try:
        return run_capped(bwrap, cwd or repo, env, timeout)
    except FileNotFoundError:
        return finish(126, "", "bwrap unavailable; masked execution refused")


def finish(exit_code: int, stdout: str, stderr: str) -> dict:
    def cap(text: str) -> str:
        data = text.encode()
        if len(data) <= MAX_RESPONSE_BYTES:
            return text
        return data[:MAX_RESPONSE_BYTES].decode(errors="replace") \
            + "\n[truncated by oc-task-service]"

    return {"exit": exit_code, "stdout": cap(stdout), "stderr": cap(stderr)}


def refused(reason: str) -> dict:
    return {"exit": 126, "stdout": "", "stderr": f"refused: {reason}"}


def refuse_slow_sender(conn: socket.socket, log_path: str, total: int) -> None:
    """Audit and answer a connection that outlived the read window."""
    audit(log_path, {"class": "refused",
                     "reason": "slow sender past the read window",
                     "bytes": total})
    try:
        conn.sendall(json.dumps(refused(
            f"request read window of {REQUEST_RECV_WINDOW_SECONDS}s exceeded"
        )).encode())
    except OSError:
        pass


def handle(repo: str, token: str, log_path: str, state: dict,
           conn: socket.socket, gate: dict = None) -> None:
    chunks = []
    total = 0
    deadline = time.monotonic() + REQUEST_RECV_WINDOW_SECONDS
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                refuse_slow_sender(conn, log_path, total)
                return
            conn.settimeout(remaining)
            try:
                chunk = conn.recv(READ_CHUNK)
            except socket.timeout:
                refuse_slow_sender(conn, log_path, total)
                return
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_REQUEST_BYTES:
                # the oversize refusal rides the restored full timeout: at
                # this point the socket timeout is the read window's last
                # shrinking residue, and a refusal dropped by it would
                # surface as a raw service error instead of the cap reason
                conn.settimeout(DEFAULT_TIMEOUT_SECONDS)
                audit(log_path, {"class": "refused", "reason": "request over size cap",
                                 "bytes": total})
                conn.sendall(json.dumps(refused("request over size cap")).encode())
                return
            chunks.append(chunk)
        # the read window leaves the timeout at its last shrinking residue;
        # restore the full timeout so no post-loop response sendall
        # inherits a near-zero deadline
        conn.settimeout(DEFAULT_TIMEOUT_SECONDS)
        raw = b"".join(chunks).decode()
        if not raw.strip():
            # a connect-and-close liveness ping (the guard plugin probes the
            # socket before spawning a service); not a request, nothing to
            # answer
            audit(log_path, {"class": "probe"})
            return
        request = json.loads(raw)
        if request.get("control") == "register":
            session = str(request.get("session", ""))
            agent = str(request.get("agent", ""))
            if not is_opencode_peer(conn):
                audit(log_path, {"class": "refused", "reason": "control from non-opencode peer",
                                 "session": session, "agent": agent})
                conn.sendall(json.dumps(refused("control channel is opencode-only")).encode())
                return
            if session and agent:
                state["registry"].add((session, agent))
                audit(log_path, {"class": "register", "session": session, "agent": agent})
                conn.sendall(json.dumps({"exit": 0, "stdout": "", "stderr": ""}).encode())
            else:
                audit(log_path, {"class": "refused", "reason": "malformed control request"})
                conn.sendall(json.dumps(refused("malformed control request")).encode())
            return
        claimed_token = request.get("token")
        session = str(request.get("session", ""))
        agent = str(request.get("agent", ""))
        cwd = str(request.get("cwd", ""))
        argv = request.get("argv")
        if claimed_token != token:
            audit(log_path, {"class": "refused", "reason": "token mismatch",
                             "session": session, "agent": agent})
            conn.sendall(json.dumps(refused("attribution token mismatch")).encode())
            return
        if (session, agent) not in state["registry"]:
            audit(log_path, {"class": "refused", "reason": "attribution not registered",
                             "session": session, "agent": agent})
            conn.sendall(json.dumps(refused("session attribution not registered")).encode())
            return
        claimed_ancestor = request.get("peer_ancestor")
        if claimed_ancestor is not None and not isinstance(claimed_ancestor, int):
            audit(log_path, {"class": "refused", "reason": "peer_ancestor must be an integer pid",
                             "session": session, "agent": agent})
            conn.sendall(json.dumps(refused("peer_ancestor must be an integer pid")).encode())
            return
        allowed, gate_reason = exec_peer_allowed(gate, peer_pid(conn),
                                                 claimed_ancestor)
        if not allowed:
            audit(log_path, {"class": "refused", "reason": gate_reason,
                             "session": session, "agent": agent})
            conn.sendall(json.dumps(refused(gate_reason)).encode())
            return
        if not isinstance(argv, list) or not argv or len(argv) > MAX_ARGV \
                or not all(isinstance(item, str) for item in argv):
            audit(log_path, {"class": "refused", "reason": "malformed argv",
                             "session": session, "agent": agent})
            conn.sendall(json.dumps(refused("malformed argv")).encode())
            return
        if any(len(item) > MAX_ARGV_ELEMENT_BYTES for item in argv):
            audit(log_path, {"class": "refused",
                             "reason": f"argv element exceeds the {MAX_ARGV_ELEMENT_BYTES}-byte cap",
                             "session": session, "agent": agent})
            conn.sendall(json.dumps(refused(
                f"argv element exceeds the {MAX_ARGV_ELEMENT_BYTES}-byte cap")).encode())
            return
        timeout = request.get("timeout", DEFAULT_TIMEOUT_SECONDS)
        if not isinstance(timeout, int) or timeout <= 0 \
                or timeout > DEFAULT_TIMEOUT_SECONDS:
            timeout = DEFAULT_TIMEOUT_SECONDS
        digest = hashlib.sha256(json.dumps(argv).encode()).hexdigest()[:16]
        kind = classify(agent, argv)
        exec_argv = None
        if kind == "sanctioned":
            resolved = os.path.realpath(cwd) if cwd else ""
            # Longest-containing root wins: worktree list order puts the
            # main repo first, and the board ground must follow the cwd's
            # nearest project root, not an ancestor repo.
            ground_root = next((r for r in sorted(
                                    [os.path.realpath(rr) for rr in worktree_roots(repo)],
                                    key=len, reverse=True)
                                if resolved == r or resolved.startswith(r + os.sep)), "")
            if not ground_root:
                audit(log_path, {"class": "refused", "reason": "cwd outside repository",
                                 "session": session, "agent": agent, "argv": argv})
                conn.sendall(json.dumps(refused("cwd outside the repository")).encode())
                return
            stdin_body = request.get("stdin", "")
            if not isinstance(stdin_body, str):
                audit(log_path, {"class": "refused", "reason": "stdin must be a string",
                                 "session": session, "agent": agent, "argv": argv})
                conn.sendall(json.dumps(refused("stdin body must be a string")).encode())
                return
            try:
                exec_argv = validate_sanctioned(command_tokens(argv),
                                                os.path.realpath(repo))
            except ValueError as error:
                audit(log_path, {"class": "refused", "reason": str(error),
                                 "session": session, "agent": agent, "argv": argv})
                conn.sendall(json.dumps(refused(str(error))).encode())
                return
            exec_argv = bind_write_attribution(exec_argv, state["attribution"])
            response = execute_sanctioned(exec_argv, cwd, timeout, stdin_body,
                                          state["attribution"], ground_root)
        elif kind == "masked":
            response = execute_masked(argv, cwd, repo, timeout)
        else:
            audit(log_path, {"class": "refused", "reason": f"role not served: {agent}",
                             "session": session, "agent": agent})
            conn.sendall(json.dumps(refused(f"role not served: {agent}")).encode())
            return
        record = {"class": kind, "session": session, "agent": agent,
                  "cwd": cwd, "argv": argv, "argv_sha": digest,
                  "tokens": command_tokens(argv),
                  "exit": response["exit"]}
        if exec_argv is not None:
            record["exec_argv"] = exec_argv
            record["attribution"] = state["attribution"]
        audit(log_path, record)
        conn.sendall(json.dumps(response).encode())
    except subprocess.TimeoutExpired:
        audit(log_path, {"class": "timeout"})
        try:
            conn.sendall(json.dumps(refused("execution timeout")).encode())
        except OSError:
            pass
    except Exception as error:  # noqa: BLE001 - per-request boundary; report and keep serving
        audit(log_path, {"class": "error", "reason": repr(error)})
        try:
            conn.sendall(json.dumps(refused(f"service error: {error}")).encode())
        except OSError:
            pass
    finally:
        conn.close()


class BrokerHandler(socketserver.StreamRequestHandler):
    def setup(self) -> None:
        super().setup()
        self.request.settimeout(DEFAULT_TIMEOUT_SECONDS)

    def handle(self) -> None:  # noqa: D102 - socketserver contract
        self.server.handle_connection(self.request)


class BrokerService(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: str, repo: str, token: str,
                 log_path: str, exec_peer_gate: bool = False) -> None:
        verify_runtime_dir(address)
        self.repo = repo
        self.token = token
        self.log_path = log_path
        self.state = {"registry": set(), "attribution": channel_label(token)}
        if exec_peer_gate:
            pin = spawner_pin()
            if not pin or not os.path.exists(pin):
                raise SystemExit("exec-peer gate armed but the spawner exe "
                                 "is unreadable; refusing to serve unpinned")
            self.peer_gate = {"service_pid": os.getpid(), "pin": pin}
        else:
            self.peer_gate = None
        super().__init__(address, BrokerHandler)

    def handle_connection(self, conn: socket.socket) -> None:
        handle(self.repo, self.token, self.log_path, self.state, conn,
               gate=self.peer_gate)

    def handle_error(self, request, client_address) -> None:
        audit(self.log_path, {"class": "handler-error"})


def watch_socket(service_obj: BrokerService, socket_path: str,
                 stop: threading.Event) -> None:
    while not stop.wait(1.0):
        if not os.path.exists(socket_path):
            stop.set()
            threading.Thread(target=service_obj.shutdown, daemon=True).start()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--audit-log", required=True)
    parser.add_argument("--token-file")
    args = parser.parse_args()

    socket_path = os.path.abspath(args.socket)
    runtime_dir = os.path.dirname(socket_path)
    os.makedirs(runtime_dir, mode=0o700, exist_ok=True)
    verify_runtime_dir(socket_path)

    token_file = args.token_file or os.path.join(runtime_dir, "token")
    if os.path.exists(token_file):
        token = pathlib.Path(token_file).read_text().strip()
    else:
        import secrets
        token = secrets.token_hex(32)
        descriptor = os.open(token_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle_file:
            handle_file.write(token)

    if os.path.exists(socket_path):
        os.unlink(socket_path)
    service_obj = BrokerService(socket_path, os.path.abspath(args.repo),
                                token, os.path.abspath(args.audit_log),
                                exec_peer_gate=True)
    os.chmod(socket_path, 0o600)
    audit(os.path.abspath(args.audit_log),
          {"class": "service-start", "socket": socket_path,
           "repo": os.path.abspath(args.repo)})

    stop = threading.Event()
    watcher = threading.Thread(target=watch_socket,
                               args=(service_obj, socket_path, stop),
                               daemon=True)
    watcher.start()
    try:
        service_obj.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        service_obj.server_close()
        if os.path.exists(socket_path):
            os.unlink(socket_path)
        audit(os.path.abspath(args.audit_log), {"class": "service-stop"})
    return 0


if __name__ == "__main__":
    sys.exit(main())
