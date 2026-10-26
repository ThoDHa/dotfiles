# Single home of the fleet manager body digest: sha256 of everything
# below the frontmatter closing --- line of the fleet manager source
# (opencode/.config/opencode/agents/manager.md). Consumed three ways:
# tests/pi-agents/test-sync.sh and tests/pi-extensions/test-sync.sh
# source the manager_body_digest function for their pin checks
# (tests/pi-agents/test-sync.sh also applies it to the host charter
# manager.md for its notice-only divergence check), and
# make pin-manager-body consumes the CLI form (bash
# tests/lib/body-digest.sh <file> prints the digest), so a program
# change can no longer land in one copy only. The pipeline is
# deliberately bare: an unclosed frontmatter extracts nothing and
# hashes to the well-known empty digest, so callers that must reject
# a vacuous result (the pin recipe) compare against the empty-input
# digest themselves.

manager_body_digest() { # FILE; sha256 of everything below the frontmatter closing --- line
	awk '/^---$/{c++; if (c == 2) { in_body = 1; next } } in_body { print }' "$1" \
		| sha256sum | cut -d' ' -f1
}

# CLI entry: executed directly, digest the file argument; sourced, done.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	if [[ $# -ne 1 || -z "$1" ]]; then
		echo "usage: bash tests/lib/body-digest.sh <file>" >&2
		exit 1
	fi
	if [[ ! -f "$1" ]]; then
		echo "body-digest: no such file: $1" >&2
		exit 1
	fi
	manager_body_digest "$1"
fi
