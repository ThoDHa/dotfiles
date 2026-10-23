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
# suite red. The four subagent fleet bodies' dual-harness notes must
# still carry the same shared truthful clause, pinned under the same
# run-everywhere contract, and the advisor and reviewer notes must also
# carry their phrase-level deposit clauses (the tasks report channel
# under .tasks/reports/; the named path under /tmp/llm/reports/) so a
# rewrite that drops either deposit destination turns the suite red.
# The host compare and the comparator self-tests skip when the
# extensions dir is absent (CI and the verify container have no pi); the
# pin, note, and deploy-canary sections run everywhere. Host state is
# never written. A stale, partial, or lingering deployment fails with
# the sync remediation; an untracked repo-side source path instead
# fails with a distinct diagnostic telling the operator to git add or
# remove it, since a deploy copies only tracked paths and rerunning it
# can never clear that mismatch. The comparator is self-tested against
# doctored scratch copies so a comparator that can no longer detect
# drift fails loudly instead of passing vacuously; the self-test covers
# the comparator functions only, not the host-comparison wiring branch,
# which needs the extensions dir present. The deploy target itself is
# canaried everywhere against a hermetic fixture repo and host dir: a
# drifted tracked path is pruned, a foreign untracked host file
# survives, and the deployed bytes end up matching the repo-tracked set
# exactly.

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
# identical content, 1 otherwise. A mismatching source path that git
# does not track is its own failure class: the deploy copies only the
# tracked set, so rerunning it can never clear the mismatch, and the
# entry gets a distinct diagnostic with a git-add-or-remove remediation
# instead. Sets forward_drift_tracked to 1 when at least one tracked
# path mismatched (or the source dir is missing), 0 otherwise, so the
# caller can scope the sync remediation to drift a deploy run fixes.
# When SRC sits outside a git work tree (the comparator self-tests run
# it on scratch copies) every path counts as tracked. Prints one
# diagnostic block per drifted entry, indented two spaces. Reads only;
# writes nothing.
sync_forward_drift() {
	local src="$1" host="$2" rel rc=0 in_repo=0 tracked_set=""
	forward_drift_tracked=0
	[[ -d "$src" ]] || { echo "  repo source dir missing: $src"; forward_drift_tracked=1; return 1; }
	if tracked_set="$(git -C "$src" ls-files 2>/dev/null)"; then
		in_repo=1
	fi
	while IFS= read -r -d '' rel; do
		[[ -f "$host/$rel" ]] && cmp -s "$src/$rel" "$host/$rel" && continue
		if (( in_repo )) && ! grep -qx -F -- "$rel" <<<"$tracked_set"; then
			echo "  untracked repo source path (a deploy copies only tracked paths): $rel"
			echo "    Remediation: git add or remove it"
			rc=1
			continue
		fi
		forward_drift_tracked=1
		if [[ ! -f "$host/$rel" ]]; then
			echo "  missing from the deployed set: $rel"
		else
			echo "  content drift (source vs deployed): $rel"
			diff -u "$src/$rel" "$host/$rel" 2>/dev/null | sed -n '1,12p' | sed 's/^/    /' || true
		fi
		rc=1
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

# The subagent notes share the manager note's truthful clause minus its
# "so their conditional clauses apply as written" tail; pin it verbatim
# in all four so a reverted or divergent clause turns the suite red on
# every host, including those without ~/.pi.
subagent_tasks_clause='The tasks CLI is present in both harnesses (on pi stowed to ~/.local/bin/tasks) and the task-files protocol is usable on pi with durable .tasks records'
for agent in worker advisor planner reviewer; do
	agent_note="$(grep -m1 '^Dual-harness note:' "$REPO_ROOT/opencode/.config/opencode/agents/$agent.md")"
	assert_contains "$agent dual-harness note pins the shared pi tasks-CLI truthfulness clause" "$agent_note" "$subagent_tasks_clause"
done

# The advisor and reviewer notes must name both deposit destinations at
# phrase level (the tasks report channel and the named fallback path),
# so dropping or rewording either one turns the suite red where the
# deposit misattribution class occurred.
for agent in advisor reviewer; do
	agent_note="$(grep -m1 '^Dual-harness note:' "$REPO_ROOT/opencode/.config/opencode/agents/$agent.md")"
	assert_contains "$agent dual-harness note pins the tasks report channel deposit clause" "$agent_note" 'the tasks report channel under .tasks/reports/'
	assert_contains "$agent dual-harness note pins the named-path deposit clause" "$agent_note" 'at the named path under /tmp/llm/reports/'
done

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
	if ((forward_rc == 0)); then
		ok "every repo-side extension file is deployed byte-identical"
	else
		bad "every repo-side extension file is deployed byte-identical"
		((forward_drift_tracked != 0)) && echo "  Remediation: $REMEDIATION"
	fi
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

	rm -rf "$scratch_deployed" "$subdir_src" "$subdir_deployed" "$ghost_repo" "$ghost_deployed"
fi

# Deploy canary: run make sync-pi-extensions against a hermetic fixture
# (fixture repo plus temp host dir) instead of the live tree, so the
# deploy contract is exercised everywhere, including hosts without
# ~/.pi. The fixture's tracked set carries a top-level and a nested
# file; its history also carries two since-deleted tracked paths. The
# fixture host starts with byte drift at both tracked paths, the two
# drifted tracked paths themselves, and a never-tracked foreign file.
# After the deploy the tracked paths match the fixture bytes exactly,
# the drifted tracked paths are pruned, and the foreign file survives.
echo "== deploy canary: tracked-prune against a hermetic fixture =="
canary_repo="$(mktemp -d)"
canary_host="$(mktemp -d)"
mkdir -p "$canary_repo/pi/extensions/nested"
printf 'tracked alpha\n' > "$canary_repo/pi/extensions/alpha.ts"
printf 'tracked beta\n' > "$canary_repo/pi/extensions/nested/beta.md"
printf 'ghost top\n' > "$canary_repo/pi/extensions/ghost-top.ts"
printf 'ghost nested\n' > "$canary_repo/pi/extensions/nested/ghost-deleted.md"
# The fixture is built with a null global and system git config so a
# user's global gitignore cannot silently shrink the tracked set the
# canary asserts against.
canary_git_env=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null)
"${canary_git_env[@]}" git -C "$canary_repo" init -q
"${canary_git_env[@]}" git -C "$canary_repo" add -A
"${canary_git_env[@]}" git -C "$canary_repo" -c user.name=selftest -c user.email=selftest@example.com commit -qm seed
rm "$canary_repo/pi/extensions/ghost-top.ts" "$canary_repo/pi/extensions/nested/ghost-deleted.md"
"${canary_git_env[@]}" git -C "$canary_repo" add -A
"${canary_git_env[@]}" git -C "$canary_repo" -c user.name=selftest -c user.email=selftest@example.com commit -qm "delete ghosts"
mkdir -p "$canary_host/nested"
printf 'stale bytes\n' > "$canary_host/alpha.ts"
printf 'stale bytes\n' > "$canary_host/nested/beta.md"
printf 'ghost top\n' > "$canary_host/ghost-top.ts"
printf 'ghost nested\n' > "$canary_host/nested/ghost-deleted.md"
printf 'foreign\n' > "$canary_repo/foreign-seed.txt"
cp "$canary_repo/foreign-seed.txt" "$canary_host/host-local-extension.ts"

canary_log="$canary_repo/deploy.log"
if make -s -C "$REPO_ROOT" sync-pi-extensions \
	PI_EXTENSIONS_SRC="$canary_repo/pi/extensions" \
	PI_EXTENSIONS_DIR="$canary_host" >"$canary_log" 2>&1; then
	ok "deploy target succeeds against the hermetic fixture"
else
	bad "deploy target succeeds against the hermetic fixture"
	sed 's/^/    /' "$canary_log"
fi

[[ ! -e "$canary_host/ghost-top.ts" && ! -e "$canary_host/nested/ghost-deleted.md" ]] \
	&& ok "canary: drifted tracked paths (top-level and nested) are pruned" \
	|| bad "canary: drifted tracked paths (top-level and nested) are pruned"

if [[ -f "$canary_host/host-local-extension.ts" ]] \
	&& cmp -s "$canary_host/host-local-extension.ts" "$canary_repo/foreign-seed.txt"; then
	ok "canary: the foreign untracked host file survives the deploy"
else
	bad "canary: the foreign untracked host file survives the deploy"
fi

byte_rc=0
while IFS= read -r -d '' tracked_rel; do
	host_rel="${tracked_rel#pi/extensions/}"
	if ! cmp -s "$canary_repo/$tracked_rel" "$canary_host/$host_rel"; then
		byte_rc=1
	fi
done < <(git -C "$canary_repo" ls-files -z -- pi/extensions)
((byte_rc == 0)) \
	&& ok "canary: deployed bytes match the fixture tracked set exactly" \
	|| bad "canary: deployed bytes match the fixture tracked set exactly"

expected_files="$( { git -C "$canary_repo" ls-files -- pi/extensions | sed 's|^pi/extensions/||'; printf '%s\n' 'host-local-extension.ts'; } | sort)"
actual_files="$(cd "$canary_host" && find . -type f -printf '%P\n' | sort)"
assert_eq "canary: deployed file set is exactly the tracked set plus the foreign file" "$expected_files" "$actual_files"

sync_forward_drift "$canary_repo/pi/extensions" "$canary_host"
canary_forward_rc=$?
sync_reverse_drift "$canary_repo/pi/extensions" "$canary_host" "$canary_repo"
canary_reverse_rc=$?
((canary_forward_rc == 0 && canary_reverse_rc == 0)) \
	&& ok "canary: both comparators pass the freshly deployed fixture host" \
	|| bad "canary: both comparators pass the freshly deployed fixture host"

rm -rf "$canary_repo" "$canary_host"

print_result
((fail == 0)) || exit 1
