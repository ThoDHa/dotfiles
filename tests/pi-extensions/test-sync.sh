#!/usr/bin/env bash
#
# Sync and pin check for the deployed pi extensions: the deployed set
# under ~/.pi/agent/extensions is compared against the repo source set
# (pi/extensions) in both directions: every repo-side file must exist
# deployed and byte-identical, and no file whose path git history tracks
# under pi/extensions may linger deployed after deletion from the repo.
# Host-local extensions and package symlinks were never tracked by the
# repo, so they are tolerated foreign content rather than drift. The
# vendored manager body must match the fleet manager body pin
# (tests/pi-agents/manager-body.sha256), the same pin the fleet-side
# suite (tests/pi-agents/test-sync.sh) enforces on
# opencode/.config/opencode/agents/manager.md, and the fleet body's
# dual-harness note must still carry its load-bearing pi mapping phrases
# (the pi tasks-CLI truthfulness clause and the background-to-detach
# mapping), so a pi surface change that invalidates a mapping turns the
# suite red. The host compare and the comparator self-test skip when the
# extensions dir is absent (CI and the verify container have no pi); the
# pin and note sections run everywhere. Host state is never written. A
# stale, partial, or lingering deployment fails with the sync
# remediation, and the comparator is self-tested against doctored
# scratch copies so a comparator that can no longer detect drift fails
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

# sync_forward_drift SRC HOST; return 0 when every regular file under
# SRC, relative path preserved, exists under HOST as a regular file with
# identical content, 1 otherwise. Prints one diagnostic block per
# drifted entry, indented two spaces. Reads only; writes nothing.
sync_forward_drift() {
	local src="$1" host="$2" rel rc=0
	[[ -d "$src" ]] || { echo "  repo source dir missing: $src"; return 1; }
	while IFS= read -r -d '' rel; do
		if [[ ! -f "$host/$rel" ]]; then
			echo "  missing from the deployed set: $rel"
			rc=1
			continue
		fi
		if ! cmp -s "$src/$rel" "$host/$rel"; then
			echo "  content drift (source vs deployed): $rel"
			diff -u "$src/$rel" "$host/$rel" 2>/dev/null | sed -n '1,12p' | sed 's/^/    /' || true
			rc=1
		fi
	done < <(find "$src" -type f -printf '%P\0')
	return "$rc"
}

# sync_reverse_drift SRC HOST REPO_ROOT; return 0 when no file deployed
# under HOST is a deleted repo extension, 1 otherwise. A deployed file
# is lingering drift when it is absent from SRC while git history tracks
# the same path under the repo's extension source, meaning the sync once
# deployed it; host-local extensions and package symlinks were never
# tracked and are tolerated foreign content. Prints one diagnostic per
# lingering entry, indented two spaces. Reads only; writes nothing.
sync_reverse_drift() {
	local src="$1" host="$2" repo="$3" rel tracked
	local -a lingering=()
	[[ -d "$host" ]] || return 0
	if ! tracked="$(git -C "$repo" log --format= --name-only -- pi/extensions | sed 's|^pi/extensions/||' | sort -u)"; then
		echo "  git history unavailable; cannot separate lingering repo extensions from foreign content"
		return 1
	fi
	while IFS= read -r -d '' rel; do
		[[ -f "$src/$rel" ]] && continue
		grep -qx -F -- "$rel" <<<"$tracked" || continue
		lingering+=("$rel")
	done < <(find "$host" -type f -printf '%P\0')
	(( ${#lingering[@]} == 0 )) && return 0
	printf '  lingering deleted repo extension still deployed: %s\n' "${lingering[@]}"
	return 1
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

echo "== pin: dual-harness note carries the pi mappings =="
note_line="$(grep -m1 '^Dual-harness note:' "$FLEET_MANAGER_MD")"
tasks_clause='the tasks CLI is present in both harnesses (on pi stowed to ~/.local/bin/tasks) and the task-files protocol is usable on pi with durable .tasks records, so their conditional clauses apply as written'
detach_mapping="rule 4's \`background: true\` maps to the subagent tool's \`detach\` parameter (\`detach: true\`)"
assert_contains "fleet dual-harness note pins the pi tasks-CLI truthfulness clause" "$note_line" "$tasks_clause"
assert_contains "fleet dual-harness note pins the background-to-detach mapping" "$note_line" "$detach_mapping"

# Pre-host snapshot for the host-untouched assertion; unset on hosts
# without the directory, which skip the host section that uses it.
if [[ -d "$HOST_DIR" ]]; then
	host_snapshot="$(mktemp -d)"
	cp -a "$HOST_DIR"/. "$host_snapshot/"
fi

if [[ ! -d "$HOST_DIR" ]]; then
	skip_test "no ~/.pi/agent/extensions on this host; host sync check skipped"
else
	echo "== sync: deployed set matches the repo source set =="
	sync_forward_drift "$SRC_DIR" "$HOST_DIR"
	forward_rc=$?
	sync_reverse_drift "$SRC_DIR" "$HOST_DIR" "$REPO_ROOT"
	reverse_rc=$?
	((forward_rc == 0)) \
		&& ok "every repo-side extension file is deployed byte-identical" \
		|| { bad "every repo-side extension file is deployed byte-identical"; echo "  Remediation: $REMEDIATION"; }
	((reverse_rc == 0)) \
		&& ok "no deleted repo extension lingers in the deployed set" \
		|| bad "no deleted repo extension lingers in the deployed set"

	echo "== host untouched: the suite writes nothing =="
	if diff -r --no-dereference "$host_snapshot" "$HOST_DIR" >/dev/null; then
		ok "host extensions untouched by the suite"
	else
		bad "host extensions untouched by the suite"
	fi
	rm -rf "$host_snapshot"

	echo "== comparator self-test (doctored scratch copies, host untouched) =="
	scratch_deployed="$(mktemp -d)"
	cp -a "$SRC_DIR"/. "$scratch_deployed"/
	sync_forward_drift "$SRC_DIR" "$scratch_deployed"
	control_forward_rc=$?
	sync_reverse_drift "$SRC_DIR" "$scratch_deployed" "$REPO_ROOT"
	control_reverse_rc=$?
	((control_forward_rc == 0 && control_reverse_rc == 0)) \
		&& ok "comparator passes an in-sync scratch deployment" \
		|| bad "comparator passes an in-sync scratch deployment"

	subdir_src="$(mktemp -d)"
	subdir_deployed="$(mktemp -d)"
	cp -a "$SRC_DIR"/. "$subdir_src"/
	cp -a "$SRC_DIR"/. "$subdir_deployed"/
	mkdir -p "$subdir_src/newext"
	printf 'export const placeholder = 1;\n' > "$subdir_src/newext/index.ts"
	sync_forward_drift "$subdir_src" "$subdir_deployed"
	subdir_rc=$?
	((subdir_rc != 0)) \
		&& ok "comparator detects an undeployed subdir-shaped repo extension" \
		|| bad "comparator detects an undeployed subdir-shaped repo extension"

	ghost_repo="$(mktemp -d)"
	ghost_deployed="$(mktemp -d)"
	git -C "$ghost_repo" init -q
	mkdir -p "$ghost_repo/pi/extensions"
	printf 'ghost\n' > "$ghost_repo/pi/extensions/ghost-extension.ts"
	git -C "$ghost_repo" add -A
	git -C "$ghost_repo" -c user.name=selftest -c user.email=selftest@example.com commit -qm add
	rm "$ghost_repo/pi/extensions/ghost-extension.ts"
	git -C "$ghost_repo" add -A
	git -C "$ghost_repo" -c user.name=selftest -c user.email=selftest@example.com commit -qm remove
	cp -a "$SRC_DIR"/. "$ghost_deployed"/
	printf 'ghost\n' > "$ghost_deployed/ghost-extension.ts"
	sync_reverse_drift "$SRC_DIR" "$ghost_deployed" "$ghost_repo"
	ghost_rc=$?
	((ghost_rc != 0)) \
		&& ok "comparator detects a lingering repo-deleted extension" \
		|| bad "comparator detects a lingering repo-deleted extension"

	rm "$ghost_deployed/ghost-extension.ts"
	printf 'local\n' > "$ghost_deployed/host-local-extension.ts"
	sync_reverse_drift "$SRC_DIR" "$ghost_deployed" "$ghost_repo"
	foreign_rc=$?
	((foreign_rc == 0)) \
		&& ok "comparator tolerates never-tracked host-local extensions" \
		|| bad "comparator tolerates never-tracked host-local extensions"

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

	rm -rf "$scratch_deployed" "$subdir_src" "$subdir_deployed" "$ghost_repo" "$ghost_deployed" "$doctored"
fi

print_result
((fail == 0)) || exit 1
