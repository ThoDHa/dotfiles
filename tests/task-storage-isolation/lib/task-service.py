#!/usr/bin/env python3
"""Parent-side whitelist service for the task-storage walking skeleton.

Runs on the host, outside the bwrap namespace, and listens on an
AF_UNIX socket that the masked child reaches through a bind-mounted
socket file. Executes exactly one sanctioned `tasks` verb shape
against the fixture board; every other request is refused with a
non-zero exit and logged. This is the G3-approved escape shape in its
skeleton form: board access flows only through whitelisted verbs, so
the mask on .tasks stays intact while sanctioned operations pass.

Usage:
    task-service.py <socket-path> <fixture-repo> <taskfile-basename> <log-path>

The service handles connections sequentially and exits when its
socket file is removed.
"""

import json
import os
import socket
import subprocess
import sys

READ_CHUNK = 65536


def log(path: str, line: str) -> None:
    with open(path, "a") as handle:
        handle.write(line + "\n")


def handle(path: str, fixture: str, taskfile: str, log_path: str,
           conn: socket.socket) -> None:
    try:
        chunks = []
        while True:
            chunk = conn.recv(READ_CHUNK)
            if not chunk:
                break
            chunks.append(chunk)
        request = json.loads(b"".join(chunks).decode())
        argv = request.get("argv")
        sanctioned = argv == ["tasks", "show", taskfile, "--json"]
        log(log_path, f"request argv={argv} sanctioned={sanctioned}")
        if not sanctioned:
            response = {"exit": 126, "stdout": "",
                        "stderr": "refused: only the sanctioned verb shape is served"}
        else:
            completed = subprocess.run(
                argv, cwd=fixture, capture_output=True, text=True, timeout=30,
                env={"PATH": os.environ["PATH"], "HOME": os.environ["HOME"],
                     "TASKS_SESSION": "skeleton-child",
                     "TASKS_DIR": os.path.join(fixture, ".tasks")})
            response = {"exit": completed.returncode, "stdout": completed.stdout,
                        "stderr": completed.stderr}
        log(log_path, f"response exit={response['exit']} stdout_bytes={len(response['stdout'])}")
        conn.sendall(json.dumps(response).encode())
    except Exception as error:  # noqa: BLE001 - single-request boundary; report and keep serving
        log(log_path, f"error {error!r}")
    finally:
        conn.close()


def main() -> int:
    socket_path, fixture, taskfile, log_path = sys.argv[1:5]
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(socket_path)
    server.listen(4)
    log(log_path, f"listening socket={socket_path} fixture={fixture} taskfile={taskfile}")
    while os.path.exists(socket_path):
        try:
            server.settimeout(1.0)
            conn, _ = server.accept()
            conn.settimeout(30)
        except socket.timeout:
            continue
        handle(socket_path, fixture, taskfile, log_path, conn)
    log(log_path, "socket removed; exiting")
    return 0


if __name__ == "__main__":
    sys.exit(main())
