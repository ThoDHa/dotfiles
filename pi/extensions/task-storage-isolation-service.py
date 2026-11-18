#!/usr/bin/env python3
"""Parent-side escape-channel service for sanctioned tasks verbs.

The production form of the ORCH-4-10-1 skeleton whitelist service,
hosted by the task-storage-isolation extension for the lifetime of one
parent session. Masked children reach it through a bind-mounted socket
FILE and may run exactly the sanctioned verb shapes against the parent
session's board: reads (show, list, reports) and the two protocol write
channels (log, report). Everything else is refused with a logged
non-zero response, so the .tasks mask stays intact while sanctioned
operations pass.

Access control, per the ORCH-4-10 decision log amendments:

- Socket-path visibility: the service refuses to start unless the
  socket's parent directory exists, is owned by the invoking user, and
  has mode 0700, so only processes of the same user that the directory
  owner admits can even resolve the socket path.
- Session attribution token: every request must carry the token the
  parent extension generated for its session; it is compared in
  constant time and logged only as a salted hash prefix. SO_PEERCRED is
  deliberately not used: bwrap's default user mapping keeps the child's
  uid equal to the invoking uid, so peer credentials cannot discriminate
  a sanctioned child from any same-uid process on this single-user
  machine.
- Write attribution binds to the service's session registry, which
  contains exactly one provisioned identity: the channel label derived
  from the session attribution token. Log and report requests are
  rewritten server-side (a claimed --from is dropped, the label is
  injected) and run with TASKS_SESSION set to the label, so no child
  can deposit as another agent or as the Manager default. The claimed
  session is kept in the service log for audit but never applied.
- Request cap: a request may not exceed REQUEST_MAX_BYTES and the
  connection is dropped on overflow; the skeleton's unbounded recv loop
  is gone.
- Read window: a request must arrive within REQUEST_RECV_WINDOW_SECONDS
  wall clock; a hostile slow sender is refused instead of holding the
  sequential service past the window.
- --dir is refused anywhere in the argv: the service cwd is the board;
  board redirection is never a sanctioned shape.
- Path policy on every argv element (positionals and flag-attached
  values alike): each element is normalized with the same candidates
  the guard enforces (lexical, kernel-style walk, realpath, ancestor)
  and every candidate must land inside the board repo, the service's
  one sanctioned surface. The service never opens a child-named path
  outside it.
- Report bodies ride the request stdin only: the body-file positional
  shape is refused (a child-named file would be read with the
  service's unmasked view, an arbitrary-file-read lane), and bodies
  are bounded by the request cap, closing the board-flooding variant.

Usage:
    task-storage-isolation-service.py <socket-path> <repo-cwd> <log-path>

The token comes from the PI_TASK_STORAGE_TOKEN environment variable.
The service handles connections sequentially, exits when its socket
file is removed, and exits when its parent process dies (per-session
lifetime; no daemon surface).
"""

import hashlib
import hmac
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time

READ_CHUNK = 65536
REQUEST_MAX_BYTES = 1024 * 1024
# A request over the acceptance cap is never executed, but the read
# side still drains (up to this hard bound) so the refusing response
# reaches the client before the connection closes; draining past this
# bound is a hostile stream and the connection is simply dropped.
REQUEST_DRAIN_MAX_BYTES = 16 * 1024 * 1024
OUTPUT_CAP_BYTES = 16 * 1024 * 1024
REQUEST_TIMEOUT_SECONDS = 30
# Wall-clock bound on one connection's request read: a hostile sender
# trickling bytes under the per-recv timeout must not hold the
# sequential service past this window.
REQUEST_RECV_WINDOW_SECONDS = 30
IDLE_POLL_SECONDS = 1.0

SANCTIONED_VERBS = ("show", "list", "reports", "log", "report")
SANCTIONED_FLAGS = {
	"show": ("--json", "--raw", "--section", "--tail", "--project",
	         "--entries", "--bytes", "--role"),
	"list": ("--json", "--lane", "--limit", "--offset"),
	"reports": ("--json", "--include-body", "--limit", "--offset"),
	"log": ("--from",),
	"report": ("--slug", "--from", "--digest"),
}
# The service cwd is the board; --dir redirection is never sanctioned.
DENIED_FLAGS = ("--dir",)
SESSION_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
# The flags that consume the following argv element; every other
# non-flag element is a positional. Mirrors the tasks CLI parsers.
VALUE_FLAGS = {
	"show": ("--section", "--tail", "--entries", "--bytes", "--role"),
	"list": ("--lane", "--limit", "--offset"),
	"reports": ("--limit", "--offset"),
	"log": ("--from",),
	"report": ("--slug", "--from", "--digest"),
}
# Task files are board entries the CLI resolves by name; a taskfile
# positional carrying a slash would ride the CLI's file-path resolution
# instead, so channel taskfiles are bare names only.
BOARD_ENTRY_PATTERN = re.compile(r"^[^/\0]+$")
STDIN_MARKER = "-"
WRITE_VERBS = ("log", "report")


def channel_label(token):
	"""The service's provisioned write-attribution identity.

	Derived from the session attribution token, so it is stable per
	session, unique across sessions, and not choosable by a child: the
	session registry this service vouches for contains exactly this
	label, and every channel write attributes to it regardless of what
	the request claims.
	"""
	return "iso-channel-" + hashlib.sha256(token.encode()).hexdigest()[:16]


def bind_write_attribution(argv, attribution):
	"""Rewrite a write argv so its attribution is service-bound.

	Drops any claimed --from (and its value) and appends the provisioned
	channel label; read verbs pass through untouched.
	"""
	if argv[1] not in WRITE_VERBS:
		return argv
	rebuilt = [argv[0], argv[1]]
	index = 2
	while index < len(argv):
		if argv[index] == "--from":
			index += 2
			continue
		rebuilt.append(argv[index])
		index += 1
	return rebuilt + ["--from", attribution]


def log(path, line):
	with open(path, "a") as handle:
		handle.write(line + "\n")


def kernel_walk(base, element):
	"""Resolve element the way the kernel resolves it at open time.

	Component by component: symlinks are resolved the moment they are
	crossed and dot-dot segments apply to the RESOLVED target, not to
	the raw name. This is the resolution lexical normalization cannot
	see: raw "ln/../secret" with ln -> .tasks/x opens .tasks/secret in
	the kernel while lexically landing outside. Non-existing tails
	continue lexically from the deepest resolved prefix, which is where
	such an open would fail or create.
	"""
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


def path_candidates(repo_cwd, element):
	"""Every absolute path the element could resolve to under open().

	Returns the lexical candidate, the kernel-style walk, and the
	ancestor-realpath fallback for write-ahead targets: the same
	candidate set the guard enforces, mirrored so the service and the
	guard cannot disagree about a path.
	"""
	lexical = os.path.normpath(
		element if element.startswith("/") else os.path.join(repo_cwd, element)
	)
	candidates = [lexical, kernel_walk(repo_cwd, element)]
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


def element_is_inside(repo_real, element):
	"""True when EVERY candidate resolution lands inside the board repo."""
	for candidate in path_candidates(repo_real, element):
		resolved = os.path.realpath(candidate)
		if resolved != repo_real and not resolved.startswith(repo_real + os.sep):
			return False
	return True


def verify_socket_visibility(socket_path):
	"""Refuse to start unless the socket dir is a 0700 dir owned by us."""
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
			f"socket dir mode is {oct(stat.st_mode & 0o777)}, refusing to bind outside 0700 visibility: {parent}"
		)


def validate_request(request, repo_cwd):
	"""Return (argv, session, stdin) or raise ValueError with a reason."""
	if not isinstance(request, dict):
		raise ValueError("request must be a JSON object")
	argv = request.get("argv")
	session = request.get("session")
	stdin = request.get("stdin", "")
	token = request.get("token")
	if not isinstance(argv, list) or not argv or not all(
		isinstance(element, str) for element in argv
	):
		raise ValueError("argv must be a non-empty list of strings")
	if len(argv) > 64:
		raise ValueError("argv has too many elements")
	if any(len(element) > 4096 for element in argv):
		raise ValueError("argv element exceeds the 4096-byte cap")
	if not isinstance(session, str) or not SESSION_PATTERN.match(session):
		raise ValueError(
			"session must match [A-Za-z0-9._-]{1,64} so board writes attribute to a session"
		)
	if not isinstance(stdin, str):
		raise ValueError("stdin must be a string when present")
	if not isinstance(token, str):
		raise ValueError("token missing; the escape channel requires the session attribution token")
	for element in argv:
		if element in DENIED_FLAGS or element.startswith("--dir="):
			raise ValueError("--dir board redirection is not a sanctioned shape")
	if argv[0] != "tasks":
		raise ValueError("only the tasks CLI is served")
	if len(argv) < 2 or argv[1] not in SANCTIONED_VERBS:
		raise ValueError(f"verb must be one of {', '.join(SANCTIONED_VERBS)}")
	verb = argv[1]
	allowed = SANCTIONED_FLAGS[verb]
	values = VALUE_FLAGS[verb]
	positionals = []
	expect_value = False
	for element in argv[2:]:
		if expect_value:
			if element.startswith("--"):
				raise ValueError(
					f"{verb}: flag value must not look like a flag: {element}"
				)
			expect_value = False
			continue
		if element.startswith("--"):
			if element not in allowed:
				raise ValueError(f"flag {element} is not sanctioned for verb {verb}")
			if element in values:
				expect_value = True
			continue
		positionals.append(element)
	repo_real = os.path.realpath(repo_cwd)
	for element in argv[2:]:
		if not element_is_inside(repo_real, element):
			raise ValueError(
				"argument resolves outside the board repo; the service never "
				f"opens child-named paths outside it: {element!r}"
			)
	if verb in ("show", "reports"):
		if len(positionals) != 1 or not BOARD_ENTRY_PATTERN.match(positionals[0]):
			raise ValueError(f"{verb} takes exactly one bare taskfile positional")
	elif verb == "log":
		if len(positionals) < 2 or not BOARD_ENTRY_PATTERN.match(positionals[0]):
			raise ValueError("log takes a bare taskfile positional and a message")
	elif verb == "list":
		if positionals:
			raise ValueError("list takes no positional arguments")
	else:  # report
		if len(positionals) < 1 or not BOARD_ENTRY_PATTERN.match(positionals[0]):
			raise ValueError("report takes a bare taskfile positional")
		if len(positionals) > 2 or (len(positionals) == 2 and positionals[1] != STDIN_MARKER):
			raise ValueError(
				"report bodies ride the request stdin only (taskfile [-]); "
				"child-named body files are refused"
			)
	if expect_value:
		raise ValueError(f"{verb}: flag {argv[-1]} requires a value")
	return argv, session, stdin, token


def run_verb(argv, repo_cwd, attribution, stdin):
	"""Run one sanctioned verb with capped, sanitized subprocess I/O.

	Both output pipes are pumped concurrently and hard-capped so a
	verb cannot buffer unbounded output in the service; overflow kills
	the verb and returns the 125 refusal. The request body is forwarded
	to the verb's stdin for the report verb (its role-contract shape
	reads stdin without the explicit marker) and whenever the argv
	carries the '-' marker. Board writes run with TASKS_SESSION set to
	the service-provisioned attribution, never to a child-claimed value.
	"""
	env = {
		"PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
		"HOME": os.environ.get("HOME", ""),
		"TASKS_SESSION": attribution,
	}
	proc = subprocess.Popen(
		argv, cwd=repo_cwd, env=env, stdin=subprocess.PIPE,
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
			if STDIN_MARKER in argv or argv[1] == "report":
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
	deadline = time.monotonic() + REQUEST_TIMEOUT_SECONDS
	for thread in threads:
		thread.join(max(0.0, deadline - time.monotonic()))
	if any(thread.is_alive() for thread in threads):
		proc.kill()
		proc.wait()
		return 124, "", "refused: verb exceeded the request timeout"
	writer.join(5)
	return_code = proc.wait()
	stdout, stderr = results.get("stdout"), results.get("stderr")
	if stdout is None or stderr is None:
		return 125, "", "refused: verb output exceeded the response cap"
	return return_code, stdout.decode(errors="replace"), stderr.decode(errors="replace")


def handle(conn, repo_cwd, expected_token, log_path):
	"""Serve one connection: read, validate, authorize, execute, respond.

	Every refusal and every served request is logged with the token-hash
	prefix for attribution; the connection is always closed.
	"""
	try:
		chunks = []
		total = 0
		oversize = False
		deadline = time.monotonic() + REQUEST_RECV_WINDOW_SECONDS

		def refuse_slow_sender():
			log(log_path, f"refused slow sender past the {REQUEST_RECV_WINDOW_SECONDS}s read window bytes={total}")
			try:
				conn.sendall(json.dumps({
					"exit": 126, "stdout": "",
					"stderr": f"refused: request read window of {REQUEST_RECV_WINDOW_SECONDS}s exceeded",
				}).encode())
			except OSError:
				pass

		while True:
			remaining = deadline - time.monotonic()
			if remaining <= 0:
				refuse_slow_sender()
				return
			conn.settimeout(remaining)
			try:
				chunk = conn.recv(READ_CHUNK)
			except socket.timeout:
				refuse_slow_sender()
				return
			if not chunk:
				break
			total += len(chunk)
			if total > REQUEST_MAX_BYTES:
				oversize = True
				if total > REQUEST_DRAIN_MAX_BYTES:
					log(log_path, f"dropped hostile stream bytes={total} cap={REQUEST_MAX_BYTES}")
					return
			chunks.append(chunk)
		# The read window leaves the timeout at its last shrinking residue;
		# restore the full send timeout so no post-loop response sendall
		# inherits a near-zero deadline.
		conn.settimeout(REQUEST_TIMEOUT_SECONDS)
		token_prefix = hashlib.sha256(expected_token.encode()).hexdigest()[:12]
		if oversize:
			log(log_path, f"refused oversize request bytes={total} cap={REQUEST_MAX_BYTES}")
			conn.sendall(json.dumps({
				"exit": 126, "stdout": "",
				"stderr": f"refused: request exceeds the {REQUEST_MAX_BYTES}-byte cap",
			}).encode())
			return
		try:
			request = json.loads(b"".join(chunks).decode())
			argv, session, stdin, token = validate_request(request, repo_cwd)
		except (ValueError, json.JSONDecodeError) as error:
			log(log_path, f"token={token_prefix} refused {error}")
			conn.sendall(json.dumps({
				"exit": 126, "stdout": "", "stderr": f"refused: {error}",
			}).encode())
			return
		if not hmac.compare_digest(token, expected_token):
			log(log_path, f"token={token_prefix} refused attribution token mismatch session={session} argv={argv}")
			conn.sendall(json.dumps({
				"exit": 126, "stdout": "",
				"stderr": "refused: attribution token mismatch",
			}).encode())
			return
		attribution = channel_label(expected_token)
		log(log_path, f"token={token_prefix} request session=claimed:{session} attr={attribution} argv={argv} sanctioned=True")
		exit_code, stdout, stderr = run_verb(bind_write_attribution(argv, attribution), repo_cwd, attribution, stdin)
		log(log_path, f"token={token_prefix} response exit={exit_code} stdout_bytes={len(stdout)} session=claimed:{session} attr={attribution}")
		conn.sendall(json.dumps({
			"exit": exit_code, "stdout": stdout, "stderr": stderr,
		}).encode())
	except Exception as error:  # noqa: BLE001 - per-connection boundary; log and keep serving
		log(log_path, f"error {error!r}")
	finally:
		conn.close()


def main() -> int:
	if len(sys.argv) != 4:
		print(__doc__)
		return 2
	socket_path, repo_cwd, log_path = sys.argv[1:4]
	token = os.environ.get("PI_TASK_STORAGE_TOKEN")
	if not token:
		print("PI_TASK_STORAGE_TOKEN must be set for the service to start")
		return 1
	verify_socket_visibility(socket_path)
	if not os.path.isdir(repo_cwd):
		print(f"repo cwd is not a directory: {repo_cwd}")
		return 1
	original_parent = os.getppid()
	try:
		os.unlink(socket_path)
	except FileNotFoundError:
		pass
	server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	server.bind(socket_path)
	server.listen(4)
	log(log_path, f"listening socket={socket_path} repo={repo_cwd} verbs={','.join(SANCTIONED_VERBS)}")
	try:
		while os.path.exists(socket_path):
			if os.getppid() != original_parent:
				log(log_path, "parent session gone; exiting")
				break
			try:
				server.settimeout(IDLE_POLL_SECONDS)
				conn, _ = server.accept()
				conn.settimeout(REQUEST_TIMEOUT_SECONDS)
			except socket.timeout:
				continue
			handle(conn, repo_cwd, token, log_path)
	finally:
		server.close()
		try:
			os.unlink(socket_path)
		except FileNotFoundError:
			pass
		log(log_path, "service stopped")
	return 0


if __name__ == "__main__":
	sys.exit(main())
