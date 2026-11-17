#!/usr/bin/env python3
"""Child-side client for the sanctioned tasks verb round-trip.

Runs inside the bwrap namespace, where the live .tasks tree is masked;
sends one argv request to the parent-side whitelist service over the
bind-mounted AF_UNIX socket and relays the service's response (stdout,
stderr, exit status) unchanged.

Usage:
    uds-client.py <socket-path> tasks show <taskfile> --json
"""

import json
import socket
import sys

READ_CHUNK = 65536


def main() -> int:
    socket_path, argv = sys.argv[1], sys.argv[2:]
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(socket_path)
    client.sendall(json.dumps({"argv": argv}).encode())
    client.shutdown(socket.SHUT_WR)
    chunks = []
    while True:
        chunk = client.recv(READ_CHUNK)
        if not chunk:
            break
        chunks.append(chunk)
    response = json.loads(b"".join(chunks).decode())
    sys.stdout.write(response["stdout"])
    sys.stderr.write(response["stderr"])
    return int(response["exit"])


if __name__ == "__main__":
    sys.exit(main())
