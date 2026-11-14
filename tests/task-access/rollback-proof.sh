#!/usr/bin/env bash
#
# Rollback proof for the ORCH-4-9 task-access migration (ORCH-4-9-4):
# reverts the three migration commits on a scratch checkout under /tmp
# (never the main tree) and proves the rolled-back state is fully green
# with zero task-data loss while the live board stays untouched.
#
# Procedure:
#   1. Pre-flight: resolve the main tree and live board, verify the base
#      commit is the dispatch base and an ancestor of HEAD, and pin the
#      escape-hatch fallback wording in the landed contract (parent
#      acceptance criterion: the rollback's operating fallback is written
#      into the migrated contract).
#   2. Snapshot the live board (per-file digest set) and the main tree's
#      git status, both compared unchanged after the procedure.
#   3. git clone --no-hardlinks the repo into a /tmp scratch dir and
#      check out the base commit; the clone reads the source store only.
#   4. Revert the migration commits newest-first (one revert commit each,
#      no rebase, no amend anywhere) and prove the reverted tree equals
#      the pre-migration tree byte-for-byte.
#   5. Deploy the reverted tree's generated artifacts into a scratch HOME
#      (the live deployment reflects the migrated tree and is never
#      touched), then run the reverted Makefile's full suite list with
#      per-suite exit gating; every suite must be green.
#   6. Zero-task-data-loss proof: the reverted tree tracks no .tasks
#      content; the rolled-back CLI exports the live-board copy (exit 0
#      over the full record set; lint excluded: its commit-reachability
#      check inspects the copy's git context, which the scratch clone
#      bounds to main's refs); the live board digest set and the main
#      tree's git status are identical to the pre-procedure snapshots.
#
# Host-only (needs git, make, rsync, and the host toolchain); it is not
# part of verify-inner. The scratch checkout stays in place after the run
# (scratch waiver) for inspection; its path is printed in the results.
# The script writes nothing outside the scratch dir and nothing to the
# live board: every live-board access here is a read.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE_COMMIT="8897f2d"
# Newest-first revert order: the stage-3 charters commit, then stage-2
# skill homes, then stage-1 harness, so each revert sees its parent's
# state and no conflict can arise between sequential stages.
MIGRATION_COMMITS=(
	8897f2d  # feat: migrate the seven fleet charters to CLI-only task access
	ac56b7a  # feat: migrate the authoritative skill homes to CLI-only access
	4d52cd9  # feat: add the task-access verb map and migration harness
)
# The reverted Makefile's suite list, cross-checked against the scratch
# tree's own `test:` recipe below before any suite runs.
EXPECTED_SUITES=(lint-corpus test-smoke test-links test-rules test-tasks test-tasks-hazard test-task-metrics test-pi-extractor test-oc-continue test-pi-continue test-agents-md test-pi-agents test-pi-extensions test-pi)
# Host-deployment suites (the verify-inner comment reserves them to the
# host): they check the host's stow deployment structure, a property of
# the host that the migration commits never touch, so they run against
# the real HOME while every content-comparing suite runs against the
# scratch HOME deployed from the reverted tree.
REAL_HOME_SUITES=(test-links test-rules)
ESCAPE_HATCH_DOC="$REPO_ROOT/agents/.agents/skills/task-files/SKILL.md"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/orch4-9-4-rollback.XXXXXX")"
RESULTS_FILE="$SCRATCH/rollback-proof-results.txt"
{
	printf '# ORCH-4-9-4 rollback proof results\n'
	printf '# base commit: %s\n' "$BASE_COMMIT"
	printf '# scratch: %s\n' "$SCRATCH"
	printf '# started: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$RESULTS_FILE"

pass=0
fail=0
ok() { printf '  PASS %s\n' "$1" | tee -a "$RESULTS_FILE"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1" | tee -a "$RESULTS_FILE"; fail=$((fail + 1)); }
die() { printf 'rollback-proof: %s\n' "$1" | tee -a "$RESULTS_FILE" >&2; exit 1; }

MAIN_TREE="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
MAIN_TREE="${MAIN_TREE%/.git}"
[[ -d "$MAIN_TREE" ]] || die "cannot resolve the main tree from $REPO_ROOT"
LIVE_BOARD="$MAIN_TREE/.tasks"
[[ -d "$LIVE_BOARD" ]] || die "live board not found at $LIVE_BOARD"

echo "== rollback proof (scratch: $SCRATCH) =="

echo "== pre-flight =="
git -C "$REPO_ROOT" merge-base --is-ancestor "$BASE_COMMIT" HEAD ||
	die "base commit $BASE_COMMIT is not an ancestor of HEAD"
base_subject="$(git -C "$REPO_ROOT" log -1 --format=%s "$BASE_COMMIT")"
[[ "$base_subject" == "feat: migrate the seven fleet charters to CLI-only task access" ]] ||
	die "base commit subject drifted: $base_subject"
ok "base commit is the dispatch base ($BASE_COMMIT, charters stage)"
for commit in "${MIGRATION_COMMITS[@]}"; do
	git -C "$REPO_ROOT" cat-file -e "$commit^{commit}" || die "migration commit missing: $commit"
done
ok "all three migration commits resolve ($(printf '%s ' "${MIGRATION_COMMITS[@]}"))"
if grep -q 'prints the whole task file byte-exact when no projection fits' "$ESCAPE_HATCH_DOC" &&
	grep -q 'MUST NOT fall back to writing `.tasks/` files by hand' "$ESCAPE_HATCH_DOC"; then
	ok "escape-hatch fallback wording present in the landed contract (task-files skill)"
else
	bad "escape-hatch fallback wording present in the landed contract (task-files skill)"
fi

board_digest() { # -> "<file count> <digest>" for the live board's files
	local count digest
	count="$(find "$LIVE_BOARD" -type f | wc -l)"
	digest="$( (cd "$LIVE_BOARD" && find . -type f -print0 | sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1)"
	printf '%s %s' "$count" "$digest"
}
main_tree_status_digest() { # -> digest of the main tree's porcelain status
	git -C "$MAIN_TREE" status --porcelain | sort | sha256sum | cut -d' ' -f1
}
BEFORE_BOARD="$(board_digest)"
BEFORE_STATUS="$(main_tree_status_digest)"
ok "live board snapshotted ($(printf '%s' "$BEFORE_BOARD" | cut -d' ' -f1) files)"

echo "== scratch checkout at the base commit =="
git clone --quiet --no-hardlinks "$MAIN_TREE" "$SCRATCH/repo" || die "clone failed"
head_hash="$(git -C "$SCRATCH/repo" rev-parse --short=7 HEAD)"
[[ "$head_hash" == "$BASE_COMMIT" ]] || die "scratch HEAD is $head_hash, not $BASE_COMMIT"
git -C "$SCRATCH/repo" config user.name "orch4-9-4 rollback proof"
git -C "$SCRATCH/repo" config user.email "orch4-9-4@rollback.invalid"
ok "scratch checkout at $BASE_COMMIT"

echo "== revert the migration commits (newest first) =="
# The pre-migration reference is the harness commit's parent: linear
# history puts the three migration commits directly on top of it, so the
# full revert must restore this tree byte-for-byte (8897f2d^ is only one
# step back, the skill-homes stage).
PRE_MIGRATION_REF="4d52cd9^"
for commit in "${MIGRATION_COMMITS[@]}"; do
	if ! git -C "$SCRATCH/repo" revert --no-edit "$commit" >> "$SCRATCH/revert.log" 2>&1; then
		bad "revert of $commit failed (see $SCRATCH/revert.log)"
		git -C "$SCRATCH/repo" status --porcelain | head -5 >> "$RESULTS_FILE" || true
		die "revert failed; investigated, not waived"
	fi
done
ok "three revert commits landed cleanly"
if [[ -z "$(git -C "$SCRATCH/repo" status --porcelain)" ]] &&
	[[ ! -d "$SCRATCH/repo/tests/fixtures/task-access" ]] &&
	[[ -z "$(git -C "$SCRATCH/repo" diff --stat "$PRE_MIGRATION_REF" HEAD 2>/dev/null)" ]]; then
	ok "reverted tree equals the pre-migration tree byte-for-byte ($PRE_MIGRATION_REF; harness removed)"
else
	bad "reverted tree equals the pre-migration tree byte-for-byte ($PRE_MIGRATION_REF)"
	git -C "$SCRATCH/repo" diff --stat "$PRE_MIGRATION_REF" HEAD | head -10 >> "$RESULTS_FILE" || true
fi

echo "== scratch-HOME deployment of the reverted tree =="
REAL_HOME="$HOME"
export HOME="$SCRATCH/home"
mkdir -p "$HOME"
for target in sync-agents-md sync-pi-agents sync-pi-extensions; do
	if make -C "$SCRATCH/repo" -s "$target" >> "$SCRATCH/deploy.log" 2>&1; then
		ok "make $target (into the scratch HOME)"
	else
		bad "make $target (into the scratch HOME)"
		tail -5 "$SCRATCH/deploy.log" >> "$RESULTS_FILE" || true
		die "deployment failed; investigated, not waived"
	fi
done

echo "== $(( ${#EXPECTED_SUITES[@]} - ${#REAL_HOME_SUITES[@]} )) content suites on the reverted state plus ${#REAL_HOME_SUITES[@]} host-deployment checks =="
# Cross-check the reverted Makefile's own `test:` recipe against the
# expected list, then run each suite as its own gated invocation.
targets_line="$(awk '/^test:/{print; exit}' "$SCRATCH/repo/Makefile" | sed 's/^test:[ \t]*//')"
suites_expected="${EXPECTED_SUITES[0]} ${EXPECTED_SUITES[*]:1}"
if [[ "$targets_line" == "$suites_expected" ]]; then
	ok "reverted Makefile's test list matches the expected suite set"
else
	bad "reverted Makefile's test list matches the expected suite set (got [$targets_line])"
fi
for suite in "${EXPECTED_SUITES[@]}"; do
	suite_home="$HOME"
	label="make $suite green on the reverted state"
	for host_suite in "${REAL_HOME_SUITES[@]}"; do
		if [[ "$suite" == "$host_suite" ]]; then
			suite_home="$REAL_HOME"
			label="make $suite green (host-deployment check, real HOME)"
		fi
	done
	if HOME="$suite_home" make -C "$SCRATCH/repo" -s "$suite" >> "$SCRATCH/suites-$suite.log" 2>&1; then
		ok "$label"
	else
		bad "$label"
		tail -8 "$SCRATCH/suites-$suite.log" >> "$RESULTS_FILE" || true
		die "$label failed; investigated, not waived"
	fi
done

echo "== zero task-data loss =="
tracked_tasks="$(git -C "$SCRATCH/repo" ls-files | grep -c '^\.tasks/' || true)"
if [[ "${tracked_tasks:-0}" == "0" ]]; then
	ok "reverted tree tracks zero .tasks content (board data is untracked, untouched)"
else
	bad "reverted tree tracks zero .tasks content (found $tracked_tasks tracked paths)"
fi
cp -R "$SCRATCH/repo" "$SCRATCH/board-repo"
cp -R "$LIVE_BOARD" "$SCRATCH/board-repo/.tasks"
rollback_tasks="$SCRATCH/board-repo/opencode/.local/bin/tasks"
export_records="$SCRATCH/rollback-export.jsonl"
# lint is deliberately excluded here: its commit-reachability check
# inspects the git context around the board copy, and the scratch clone
# intentionally bounds refs to main, so branch-recorded commits the live
# board cites are unreachable there regardless of data integrity. The
# export check is a full-board readability proof: exit 0 with a non-empty
# record set shows the rolled-back CLI reads every task file and report
# without error; byte-exact reconstruction stays test-tasks.sh's coverage.
if TASKS_DIR="$SCRATCH/board-repo/.tasks" "$rollback_tasks" export --format jsonl --include-reports > "$export_records" 2> "$SCRATCH/export.err" && [[ -s "$export_records" ]]; then
	ok "rolled-back CLI export completes over the full board ($(wc -l < "$export_records") records, exit 0)"
else
	bad "rolled-back CLI export completes over the full board"
	tail -5 "$SCRATCH/export.err" >> "$RESULTS_FILE" || true
fi
AFTER_BOARD="$(board_digest)"
AFTER_STATUS="$(main_tree_status_digest)"
if [[ "$BEFORE_BOARD" == "$AFTER_BOARD" ]]; then
	ok "live board untouched: $(printf '%s' "$AFTER_BOARD" | cut -d' ' -f1) files, digest identical before/after"
else
	bad "live board untouched (digest changed: $BEFORE_BOARD -> $AFTER_BOARD)"
fi
if [[ "$BEFORE_STATUS" == "$AFTER_STATUS" ]]; then
	ok "main tree git status unchanged by the procedure"
else
	bad "main tree git status unchanged by the procedure"
fi

printf '\nResult: %d passed, %d failed\n' "$pass" "$fail" | tee -a "$RESULTS_FILE"
printf 'finished: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RESULTS_FILE"
if ((fail > 0)); then
	exit 1
fi
echo "rollback proof green; results: $RESULTS_FILE"
exit 0
