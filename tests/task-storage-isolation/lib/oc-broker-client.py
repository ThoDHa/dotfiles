#!/usr/bin/env python3
"""Bridge client for the opencode task-storage broker (ORCH-4-10-3).

The guard plugin rewrites each shell tool call into one invocation of
this script; the original command arrives as a single argv element and
travels to the parent-side service as one JSON string, so no shell
reconstruction happens at any layer. The client reads the socket path
and attribution token from the runtime directory (0700 dir, 0600
token file), sends the plugin-supplied session attribution with the
command, and relays the service's response (stdout, stderr, exit)
unchanged.

Report and edit bodies ride the request: when the command tokenizes to
a tasks write-verb invocation, the client captures its own stdin and
carries it as the request's stdin field, bounded by the request cap.
The service refuses child-named body files, so stdin is the only body
channel; a body fed through shell redirection inside the command
string travels as shell syntax and lands in the masked class.

Usage:
    oc-broker-client.py --registry DIR --session ID --agent NAME exec COMMAND
"""

import argparse
import json
import os
import select
import shlex
import socket
import sys

READ_CHUNK = 65536
SEND_LIMIT = 1024 * 1024
STDIN_PRIME_SECONDS = 1.0
STDIN_VERBS = ("report", "edit")


def wants_stdin(command: str) -> bool:
    """True when the command tokenizes to a tasks write-verb invocation
    whose body rides stdin. Tokenization failure (unbalanced quotes)
    captures nothing; the command lands in the masked class anyway."""
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    return len(tokens) >= 2 and tokens[0] == "tasks" and tokens[1] in STDIN_VERBS


def capture_stdin() -> str:
    """Read piped stdin as a write-verb body without ever touching a
    TTY and without hanging on a silent pipe: a pipe that delivers
    nothing within the priming window yields an empty body, and a pipe
    that delivers is drained to EOF. A read failure after data arrived
    is fatal (exit 2): a silently truncated body must never deposit."""
    try:
        if sys.stdin is None or sys.stdin.isatty():
            return ""
        descriptor = sys.stdin.fileno()
    except (OSError, ValueError):
        return ""
    try:
        ready, _, _ = select.select([descriptor], [], [], STDIN_PRIME_SECONDS)
        if not ready:
            return ""
        chunks = []
        while True:
            chunk = os.read(descriptor, READ_CHUNK)
            if not chunk:
                break
            chunks.append(chunk)
    except OSError as error:
        print(f"broker stdin capture failed ({error}); the body would be "
              "truncated, refusing to deposit", file=sys.stderr)
        raise SystemExit(2)
    return b"".join(chunks).decode(errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--peer-ancestor", type=int, default=None,
                        help="spawner pid the guard passes so the broker can "
                        "tie exec-peer acceptance to the exact host process")
    parser.add_argument("--session", required=True)
    parser.add_argument("--agent", required=True)
    parser.add_argument("verb", choices=["exec"])
    parser.add_argument("command")
    args = parser.parse_args()

    registry = os.path.abspath(args.registry)
    socket_path = os.path.join(registry, "broker.sock")
    try:
        with open(os.path.join(registry, "token")) as handle:
            token = handle.read().strip()
    except OSError as error:
        print(f"broker registry unreadable ({error}); "
              "rollback: set TASKS_BROKER_DISABLE=1 or remove the "
              "task-storage-guard plugin", file=sys.stderr)
        return 126

    body = capture_stdin() if wants_stdin(args.command) else ""
    payload = json.dumps({
        "token": token,
        "session": args.session,
        "agent": args.agent,
        "cwd": os.getcwd(),
        "argv": ["/bin/bash", "-c", args.command],
        "stdin": body,
        "peer_ancestor": args.peer_ancestor,
    }).encode()
    if len(payload) > SEND_LIMIT:
        print("refused: command exceeds the broker request cap", file=sys.stderr)
        return 126

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(socket_path)
        client.sendall(payload)
        client.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = client.recv(READ_CHUNK)
            if not chunk:
                break
            chunks.append(chunk)
        response = json.loads(b"".join(chunks).decode())
    except (OSError, ValueError, KeyError, TypeError) as error:
        # any failed or malformed broker exchange gets the same clean,
        # actionable refusal as the connect and registry failures above:
        # the model must see the rollback route, not a traceback
        print(f"broker exchange failed ({error}); "
              "rollback: set TASKS_BROKER_DISABLE=1 or remove the "
              "task-storage-guard plugin", file=sys.stderr)
        return 127
    finally:
        client.close()
    sys.stdout.write(response["stdout"])
    sys.stderr.write(response["stderr"])
    return int(response["exit"])


if __name__ == "__main__":
    sys.exit(main())
