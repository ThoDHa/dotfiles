#!/usr/bin/env bash
#
# Sync and pin check for the deployed pi extensions: the deployed copies
# under ~/.pi/agent/extensions must be byte-identical to the repo source
# (pi/extensions), and the vendored manager body must match the fleet
# manager body pin (tests/pi-agents/manager-body.sha256), the same pin
# the fleet-side suite (tests/pi-agents/test-sync.sh) enforces on
# opencode/.config/opencode/agents/manager.md. The host compare and the
# comparator self-test skip when the extensions dir is absent (CI and
# the verify container have no pi); the pin section runs everywhere.
# Host state is never written. A stale deployment fails with the sync
# remediation, and the comparator is self-tested against a doctored
# scratch copy so a comparator that can no longer detect drift fails
# loudly instead of passing vacuously. The self-test covers the
# comparator functions only, not the host-comparison wiring branch,
# which needs the extensions dir present.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$REPO_ROOT/pi/extensions"
EXTENSION="$SRC_DIR/manager-mode.ts"
BODY="$SRC_DIR/manager-body.md"
FLEET_MANAGER_MD="$REPO_ROOT/opencode/.config/opencode/agents/manager.md"
PIN_FILE="$REPO_ROOT/tests/pi-agents/manager-body.sha256"
HOST_DIR="$HOME/.pi/agent/extensions"
REMEDIATION="run make sync-pi-extensions"

source "$REPO_ROOT/tests/lib/harness.sh"

# fleet_body_digest FILE; sha256 of the manager body: everything below
# the frontmatter closing --- line. Keep the awk program identical to
# make pin-manager-body and tests/pi-agents/test-sync.sh, which share it.
fleet_body_digest() {
	awk '/^---$/{c++; if (c == 2) { in_body = 1; next } } in_body { print }' "$1" \
		| sha256sum | cut -d' ' -f1
}

pinned_digest="$(awk '!/^#/ && NF { print $1; exit }' "$PIN_FILE")"

echo "== source: repo-side files =="
for f in "$EXTENSION" "$BODY"; do
	[[ -f "$f" ]] && ok "source present: ${f#"$REPO_ROOT"/}" \
		|| bad "source present: ${f#"$REPO_ROOT"/} (missing)"
done

echo "== pin: vendored manager body matches the fleet pin =="
body_digest="$(sha256sum "$BODY" | cut -d' ' -f1)"
assert_eq "vendored manager-body.md digest matches the pin" "$pinned_digest" "$body_digest"
fleet_digest="$(fleet_body_digest "$FLEET_MANAGER_MD")"
assert_eq "vendored manager-body.md matches a fresh extraction of the fleet body" "$fleet_digest" "$body_digest"
grep -qF "$pinned_digest" "$EXTENSION" \
	&& ok "manager-mode.ts carries the pinned digest for its activation-time check" \
	|| bad "manager-mode.ts carries the pinned digest for its activation-time check"

# Pre-host snapshot for the host-untouched assertion; unset on hosts
# without the directory, which skip the host section that uses it.
if [[ -d "$HOST_DIR" ]]; then
	host_snapshot="$(mktemp -d)"
	cp "$HOST_DIR"/manager-mode.ts "$HOST_DIR"/manager-body.md "$host_snapshot/" 2>/dev/null || true
fi

if [[ ! -d "$HOST_DIR" ]]; then
	skip_test "no ~/.pi/agent/extensions on this host; host sync check skipped"
else
	echo "== sync: deployed copies match the repo source =="
	for name in manager-mode.ts manager-body.md; do
		[[ -f "$HOST_DIR/$name" ]] || { bad "deployed $name present under ~/.pi/agent/extensions"; continue; }
		if cmp -s "$SRC_DIR/$name" "$HOST_DIR/$name"; then
			ok "deployed $name is byte-identical to the repo source"
		else
			bad "deployed $name is byte-identical to the repo source"
			echo "  Stale deployment; diff summary (source vs deployed):"
			diff -u "$SRC_DIR/$name" "$HOST_DIR/$name" | sed -n '1,12p' | sed 's/^/    /' || true
			echo "  Remediation: $REMEDIATION"
		fi
	done

	echo "== host untouched: the suite writes nothing =="
	host_untouched=true
	for name in manager-mode.ts manager-body.md; do
		if [[ -f "$host_snapshot/$name" ]] && ! cmp -s "$host_snapshot/$name" "$HOST_DIR/$name"; then
			host_untouched=false
		fi
	done
	[[ "$host_untouched" == true ]] && ok "host extensions untouched by the suite" \
		|| bad "host extensions untouched by the suite"
	rm -rf "$host_snapshot"

	echo "== comparator self-test (doctored scratch copy, host untouched) =="
	doctored="$(mktemp -d)"
	sed 's/^You are a manager\./You are NOT a manager./' "$BODY" >"$doctored/manager-body.md"
	doctored_digest="$(sha256sum "$doctored/manager-body.md" | cut -d' ' -f1)"
	[[ "$doctored_digest" != "$body_digest" ]] \
		&& ok "comparator detects a doctored body line as drift" \
		|| bad "comparator detects a doctored body line as drift"
	if cmp -s "$BODY" "$doctored/manager-body.md"; then
		bad "comparator probe reports the doctored copy as drifted"
	else
		ok "comparator probe reports the doctored copy as drifted"
	fi
	rm -rf "$doctored"
fi

print_result
((fail == 0)) || exit 1
