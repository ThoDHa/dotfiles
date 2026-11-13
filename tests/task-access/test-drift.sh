#!/usr/bin/env bash
#
# Task-access drift-check suite (ORCH-4-9-1, Tier A). Proves the drift check
# green on the unmigrated corpus (the migrated-surfaces list ships empty) and
# red on every planted failure fixture: one fixture per pattern class under
# tests/fixtures/task-access/failures/, planted into a temp root and scanned
# through --list/--root overrides, so the suite never touches the real list.
# Also pins the allowance semantics (fences, the task-access-sanctioned
# marker), the list-format rules (comments, blank lines), and the error
# contracts (missing list, missing listed file, usage error).
#
# Fixture boundary: this suite proves the check's red capability over listed
# text surfaces; it is documentation drift detection, not enforcement.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRIFT="$REPO_ROOT/tests/task-access/drift-check.sh"
FAILURES="$REPO_ROOT/tests/fixtures/task-access/failures"

source "$REPO_ROOT/tests/lib/harness.sh"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# run_drift LABEL -- <args...>: captures rc, stdout, stderr in one call so
# assertions read the exit contract and the findings text together.
rc=0; out=""; err=""
run_drift() {
	local label="$1"; shift
	out="$(bash "$DRIFT" "$@" 2>"$ROOT/stderr")"
	rc=$?
	err="$(cat "$ROOT/stderr")"
	if ((rc == 0)); then ok "$label"; else bad "$label (exit $rc)"; fi
}

echo "== default run: green on the empty migrated-surfaces list =="
run_drift "default run exits 0 on the real (empty) list"
assert_contains "default run reports the empty-list contract" "$out" "empty"
assert_eq "default run writes nothing to stderr" "" "$err"

echo "== list validation =="
out="$(bash "$DRIFT" --list "$ROOT/no-such-list.txt" 2>&1)"; rc=$?
if ((rc == 1)); then ok "missing list file exits 1"; else bad "missing list file exits 1 (exit $rc)"; fi
assert_contains "missing list file names the path" "$out" "not found"
out="$(bash "$DRIFT" --bogus 2>&1)"; rc=$?
if ((rc == 2)); then ok "unknown flag exits 2"; else bad "unknown flag exits 2 (exit $rc)"; fi

echo "== per-class red capability: every planted fixture goes red =="
# planted CLASS FILE EXPECTED_PATTERN_ID
plant() {
	local class="$1" fixture="$2" expect="$3"
	local root="$ROOT/plant-$class"
	mkdir -p "$root"
	cp "$FAILURES/$fixture" "$root/planted.md"
	printf '%s\n' "planted.md" > "$root/list.txt"
	local o e r
	o="$(bash "$DRIFT" --list "$root/list.txt" --root "$root" 2>"$root/stderr")"
	r=$?
	e="$(cat "$root/stderr")"
	if ((r == 1)); then ok "$class fixture ($fixture) goes red"; else bad "$class fixture ($fixture) goes red (exit $r)"; fi
	assert_contains "$class fixture reports the $expect pattern" "$o$e" "$expect"
	assert_contains "$class fixture names the planted file and line" "$o$e" "planted.md:"
}
plant tool-path shell-read.md "P2"
plant map-allow edit-allow.md "P1"
plant uncited-mention write-framing.md "P4"
plant uncited-mention read-framing.md "P4"
plant uncited-mention mention-noun.md "P4"
plant uncited-mention mention-deposit.md "P4"
plant tool-dirarg tool-dirarg.md "P3"

echo "== exact finding count on a single-pattern file =="
printf '%s\n' 'cat .tasks/current/x.md' > "$ROOT/one.md"
printf '%s\n' "one.md" > "$ROOT/one-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/one-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "single-violation file exits 1"; else bad "single-violation file exits 1 (exit $rc)"; fi
assert_contains "exactly one finding counted" "$out" "1 finding(s)"

echo "== allowance: the task-access-sanctioned marker =="
printf '%s\n' 'Planner deposits stay direct: write the report at .tasks/reports/research/ <!-- task-access-sanctioned -->' > "$ROOT/marked.md"
printf '%s\n' "marked.md" > "$ROOT/marked-list.txt"
run_drift "marker line is tolerated" --list "$ROOT/marked-list.txt" --root "$ROOT"
assert_contains "marker run is green" "$out" "clean"

echo "== allowance: fenced regions are skipped =="
{
	printf 'Before the fence.\n'
	printf '```text\n'
	printf 'removed map line: { action: edit, resource: ".tasks/**", effect: allow }\n'
	printf '```\n'
	printf 'After the fence, clean prose only.\n'
} > "$ROOT/fenced.md"
printf '%s\n' "fenced.md" > "$ROOT/fenced-list.txt"
run_drift "violation inside a fence is skipped" --list "$ROOT/fenced-list.txt" --root "$ROOT"
assert_contains "fenced run is green" "$out" "clean"
{
	printf '```text\n'
	printf 'fence open\n'
	printf '```\n'
	printf 'cat .tasks/current/leak.md after the fence closes\n'
} > "$ROOT/fence-leak.md"
printf '%s\n' "fence-leak.md" > "$ROOT/fence-leak-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/fence-leak-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "violation after the fence closes is caught"; else bad "violation after the fence closes is caught (exit $rc)"; fi

echo "== P4 precision: a same-line tasks citation satisfies the mention rule =="
printf '%s\n' 'Task files live under .tasks/current/; read them with tasks show, never directly.' > "$ROOT/cited.md"
printf '%s\n' "cited.md" > "$ROOT/cited-list.txt"
run_drift "a cited .tasks mention is not a finding" --list "$ROOT/cited-list.txt" --root "$ROOT"
assert_contains "cited-mention run is green" "$out" "clean"

echo "== P5 fence parity: an odd fence count is a finding =="
{
	printf 'Clean prose before the stray fence.\n'
	printf '```text\n'
	printf 'a fence that never closes silences the rest of the file\n'
} > "$ROOT/odd-fence.md"
printf '%s\n' "odd-fence.md" > "$ROOT/odd-fence-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/odd-fence-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "an odd fence count at EOF exits 1"; else bad "an odd fence count at EOF exits 1 (exit $rc)"; fi
assert_contains "the odd fence reports as fence-parity" "$out" "P5"
violation_lines="$(grep -c '^FAIL:' <<<"$out")"
assert_eq "fence parity alone yields exactly one finding" "1" "$violation_lines"
{
	printf '```text\n'
	printf 'opened and closed\n'
	printf '```\n'
	printf 'Clean prose after a balanced pair.\n'
} > "$ROOT/even-fence.md"
printf '%s\n' "even-fence.md" > "$ROOT/even-fence-list.txt"
run_drift "a balanced fence count stays green" --list "$ROOT/even-fence-list.txt" --root "$ROOT"
assert_contains "even-fence run is green" "$out" "clean"

echo "== map-diff: @role entries diff their frontmatter against the tier-b target =="
fm_planner() { # extra-body-line... -> fixture with the planner target stanza on stdout
	{
		printf -- '---\n'
		printf 'description: "Fixture planner map"\n'
		printf 'mode: subagent\n'
		printf 'permissions:\n'
		printf '  - { action: shell, resource: "*", effect: deny }\n'
		printf '  - { action: edit, resource: "*", effect: deny }\n'
		printf '  - { action: edit, resource: ".tasks/**", effect: deny }\n'
		printf '  - { action: edit, resource: ".tasks/reports/research/**", effect: allow }\n'
		printf -- '---\n'
		printf '# Fixture body\n\n'
		for line in "$@"; do printf '%s\n' "$line"; done
	}
}
fm_planner "Clean prose only; nothing direct here." > "$ROOT/md-planner.md"
printf '%s\n' "md-planner.md @planner" > "$ROOT/md-planner-list.txt"
run_drift "a frontmatter matching the tier-b target is green (sanctioned allow inside it does not fire P1)" --list "$ROOT/md-planner-list.txt" --root "$ROOT"
assert_contains "map-diff green run reports clean" "$out" "clean"
fm_planner "cat .tasks/current/leak.md from the body" > "$ROOT/md-body.md"
printf '%s\n' "md-body.md @planner" > "$ROOT/md-body-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/md-body-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "body prose of an @role entry is still scanned"; else bad "body prose of an @role entry is still scanned (exit $rc)"; fi
assert_contains "the body violation reports under its text class" "$out" "P2"
fm_planner "removed allow: { action: edit, resource: \".tasks/**\", effect: allow }" > "$ROOT/md-p1body.md"
printf '%s\n' "md-p1body.md @planner" > "$ROOT/md-p1body-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/md-p1body-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "an edit-allow in body prose still fires P1"; else bad "an edit-allow in body prose still fires P1 (exit $rc)"; fi
assert_contains "the body allow reports as map-allow" "$out" "map-allow"
{
	printf -- '---\n'
	printf 'permissions:\n'
	printf '  - { action: edit, resource: ".tasks/**", effect: allow }\n'
	printf -- '---\n'
	printf '# Body\n'
} > "$ROOT/md-diverge.md"
printf '%s\n' "md-diverge.md @planner" > "$ROOT/md-diverge-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/md-diverge-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "a live rule the target does not carry is a map-diff finding"; else bad "a live rule the target does not carry is a map-diff finding (exit $rc)"; fi
assert_contains "the divergence reports as MD" "$out" "MD"
{
	printf -- '---\n'
	printf 'permissions:\n'
	printf '  - { action: edit, resource: ".tasks/**", effect: deny }\n'
	printf -- '---\n'
	printf '# Body\n'
} > "$ROOT/md-missing.md"
printf '%s\n' "md-missing.md @planner" > "$ROOT/md-missing-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/md-missing-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "a target rule missing from live is a map-diff finding"; else bad "a target rule missing from live is a map-diff finding (exit $rc)"; fi
assert_contains "the missing rule reports as MD" "$out" "MD"
{
	printf -- '---\n'
	printf 'permissions:\n'
	printf '  - { action: edit, resource: ".tasks/reports/research/**", effect: allow }\n'
	printf '  - { action: edit, resource: ".tasks/**", effect: deny }\n'
	printf -- '---\n'
	printf '# Body\n'
} > "$ROOT/md-reorder.md"
printf '%s\n' "md-reorder.md @planner" > "$ROOT/md-reorder-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/md-reorder-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "rule order is map-diff significant (last-match-wins)"; else bad "rule order is map-diff significant (exit $rc)"; fi
assert_contains "the reorder reports as MD" "$out" "MD"
{
	printf -- '---\n'
	printf 'permissions:\n'
	printf '  - { action: edit, resource: ".tasks/**", effect: allow }\n'
	printf -- '---\n'
	printf '# Body\n'
} > "$ROOT/md-manager.md"
printf '%s\n' "md-manager.md @manager" > "$ROOT/md-manager-list.txt"
run_drift "the manager's retained interim allow is map-diff-legible" --list "$ROOT/md-manager-list.txt" --root "$ROOT"
assert_contains "manager retain run is green" "$out" "clean"
printf '%s\n' '# no frontmatter here' > "$ROOT/md-nofm.md"
printf '%s\n' "md-nofm.md @planner" > "$ROOT/md-nofm-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/md-nofm-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "an @role entry without frontmatter is a finding"; else bad "an @role entry without frontmatter is a finding (exit $rc)"; fi
assert_contains "the missing stanza reports as MD" "$out" "MD"
printf '%s\n' 'clean prose' > "$ROOT/md-unknown.md"
printf '%s\n' "md-unknown.md @nosuchrole" > "$ROOT/md-unknown-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/md-unknown-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "an @role with no tier-b config is a finding"; else bad "an @role with no tier-b config is a finding (exit $rc)"; fi
assert_contains "the unknown role reports as MD" "$out" "MD"

echo "== list format: comments, blank lines, missing listed files =="
{
	printf '# header comment\n'
	printf '\n'
	printf 'clean.md\n'
	printf '# trailing comment\n'
} > "$ROOT/fmt-list.txt"
printf '%s\n' 'Reads go through tasks show; nothing direct here.' > "$ROOT/clean.md"
run_drift "comments and blank lines carry no surface" --list "$ROOT/fmt-list.txt" --root "$ROOT"
assert_contains "one effective surface scanned" "$out" "1 migrated surface"
printf '%s\n' "ghost.md" > "$ROOT/ghost-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/ghost-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "missing listed file exits 1"; else bad "missing listed file exits 1 (exit $rc)"; fi
assert_contains "missing listed file is a P0 finding" "$out" "listed-file-missing"

echo "== last line without a trailing newline is still scanned =="
printf 'clean prose first\ncat .tasks/current/leak.md' > "$ROOT/nonl.md"
printf '%s\n' "nonl.md" > "$ROOT/nonl-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/nonl-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "violation on an unterminated final line is caught"; else bad "violation on an unterminated final line is caught (exit $rc)"; fi

echo "== precision: a .tasks edit deny rule is not a map-allow finding =="
printf '%s\n' '  - { action: edit, resource: ".tasks/**", effect: deny }' > "$ROOT/deny-rule.md"
printf '%s\n' "deny-rule.md" > "$ROOT/deny-list.txt"
out="$(bash "$DRIFT" --list "$ROOT/deny-list.txt" --root "$ROOT" 2>&1)"; rc=$?
if ((rc == 1)); then ok "an explicit .tasks edit deny rule still names no CLI route (exit 1)"; else bad "an explicit .tasks edit deny rule still names no CLI route (exit $rc)"; fi
assert_contains "the deny rule fires as an uncited mention" "$out" "P4"
assert_not_contains "the deny rule does not fire the map-allow class" "$out" "map-allow"

print_result
((fail == 0)) || exit 1
exit 0
