#!/usr/bin/env python3
"""Child-side client for the sanctioned tasks verb escape channel.

Runs inside the bwrap namespace, where the live .tasks tree is masked,
and relays one tasks verb to the parent-side service over the
bind-mounted socket. The socket path, the session attribution token,
and the session identity come from the child environment:

    PI_TASK_STORAGE_SOCKET   bind-mounted escape-channel socket file
    PI_TASK_STORAGE_TOKEN    session attribution token (service refuses without it)
    TASKS_SESSION            session id the board write attributes to

A missing variable is a hard error (exit 2), never a fallback to direct
board access: the child has no unmasked route anyway, and the request
would be refused at the service. Piped stdin rides the request as the
payload body: the write verbs' role-contract shapes (a report body on
stdin) work exactly as they do against the tasks CLI, while body-file
positional shapes are refused by the service. The service response
(stdout, stderr, exit status) is relayed unchanged.

Body bytes are decoded as UTF-8 (invalid bytes become U+FFFD): bodies
are UTF-8 markdown prose per the role contract, so valid bodies ride
the channel byte-exactly, and raw non-UTF-8 bytes are not preserved
here where the unmasked CLI path would carry them unchanged.

Usage:
    task-storage-isolation-client.py tasks <verb> [args...]

Examples (inside a masked child):
    task-storage-isolation-client.py tasks show ORCH-4-10-2-*.md --project
    printf 'report body\n' | task-storage-isolation-client.py tasks report \
        ORCH-4-10-2-*.md --slug fix --from worker --digest "one line"
"""

import json
import os
import socket
import sys

READ_CHUNK = 65536
REQUEST_MAX_BYTES = 1024 * 1024
RESPONSE_RELAY_CAP_BYTES = REQUEST_MAX_BYTES * 16


def main() -> int:
	socket_path = os.environ.get("PI_TASK_STORAGE_SOCKET")
	token = os.environ.get("PI_TASK_STORAGE_TOKEN")
	session = os.environ.get("TASKS_SESSION")
	if not socket_path or not token:
		print(
			"task-storage-isolation-client: PI_TASK_STORAGE_SOCKET and "
			"PI_TASK_STORAGE_TOKEN must be set in the child environment",
			file=sys.stderr,
		)
		return 2
	if not session:
		print(
			"task-storage-isolation-client: TASKS_SESSION must be set so "
			"board writes attribute to a session",
			file=sys.stderr,
		)
		return 2
	argv = sys.argv[1:]
	if not argv or argv[0] != "tasks":
		print("usage: task-storage-isolation-client.py tasks <verb> [args...]", file=sys.stderr)
		return 2
	stdin_body = ""
	if not sys.stdin.isatty():
		try:
			stdin_body = sys.stdin.buffer.read().decode(errors="replace")
		except OSError as error:
			print(
				f"task-storage-isolation-client: cannot read stdin: {error}",
				file=sys.stderr,
			)
			return 2
	payload = json.dumps({"argv": argv, "session": session, "token": token, "stdin": stdin_body})
	if len(payload) > REQUEST_MAX_BYTES:
		print(
			f"task-storage-isolation-client: request exceeds the {REQUEST_MAX_BYTES}-byte cap",
			file=sys.stderr,
		)
		return 2
	client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	try:
		client.connect(socket_path)
		client.sendall(payload.encode())
		client.shutdown(socket.SHUT_WR)
		chunks = []
		total = 0
		while True:
			chunk = client.recv(READ_CHUNK)
			if not chunk:
				break
			total += len(chunk)
			if total > RESPONSE_RELAY_CAP_BYTES:
				print("task-storage-isolation-client: response exceeded the relay cap", file=sys.stderr)
				return 2
			chunks.append(chunk)
	except OSError as error:
		print(f"task-storage-isolation-client: escape channel unreachable: {error}", file=sys.stderr)
		return 2
	finally:
		client.close()
	try:
		response = json.loads(b"".join(chunks).decode())
	except (json.JSONDecodeError, UnicodeDecodeError):
		print("task-storage-isolation-client: escape channel returned a malformed response", file=sys.stderr)
		return 2
	if not isinstance(response, dict) or not {"exit", "stdout", "stderr"} <= response.keys() \
			or not isinstance(response["exit"], int):
		print("task-storage-isolation-client: escape channel returned a malformed response", file=sys.stderr)
		return 2
	sys.stdout.write(response["stdout"])
	sys.stderr.write(response["stderr"])
	return response["exit"]


if __name__ == "__main__":
	sys.exit(main())
