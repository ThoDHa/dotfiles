#!/usr/bin/env bash
#
# Characterization suite for the tasks CLI parser's heading-delimiter
# hazard (unit ORCH-4-1): pins the observed behavior of every documented
# failure mode FM-1 through FM-12 against the current implementation.
#
# Label contract:
#   "(reproduced-pin)" documents current corruption the parser-fix
#     follow-up flips; a flip treats each assertion as a Test Change
#     Intent Verification case whose intent evidence is this task's
#     findings report and its report-corrections addendum
#     (.tasks/reports/ORCH-4-1-.../NN-{execution,report-corrections}.md).
#   "(safe-pin)" asserts behavior that must stay correct through any
#     fix: the refuted hazard claim (FM-3), the one fence-aware
#     surface (FM-11), the no-fence controls that keep the fix from
#     overcorrecting, and the behavior halves that survive the fix
#     (entry-visibility guards, FM-10's intended stop-at-first-section).
#   "(setup)" asserts fixture construction only (the anti-tautology
#     premise behind a reproduced-pin); it runs no CLI surface and
#     cannot flip under a parser fix.
#
# Self-contained: scratch boards under a temp root, exported TASKS_DIR
# and TASKS_TEST_CLOCK as the only seams, public CLI surfaces plus the
# two precedented probe patterns (sourced function, stdin pipe).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASKS_BIN="$REPO_ROOT/opencode/.local/bin/tasks"

source "$REPO_ROOT/tests/lib/harness.sh"

accept() { # label; rest is the command that must succeed
	local label="$1"; shift
	if t "$@" </dev/null >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}
first_line_of() { # file fixed-string; prints the 1-based line number
	grep -nm1 -F "$2" "$1" | cut -d: -f1
}
duration_of() { # file; prints the **Duration:** header value
	grep -oP '^\*\*Duration:\*\*\s+\K.*' "$1"
}
status_of() { # file; prints the **Status:** header value
	grep -oP '^\*\*Status:\*\*\s+\K.*' "$1"
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export TASKS_DIR="$ROOT/.tasks"
# Pinned CLI clock (the sanctioned TASKS_DIR + TASKS_TEST_CLOCK seam):
# closure and stamp timestamps read deterministic values.
export TASKS_TEST_CLOCK="2026-06-15 12:00"

t() { "$TASKS_BIN" "$@"; }

t init >/dev/null

# Separate board for the lint-surface fixtures (FM-4, FM-10, FM-12): lint
# scans a whole board, so per-filename assertions need these findings
# isolated from the main board's fixtures.
LINT_BOARD="$ROOT/lintboard/.tasks"
t init --dir "$LINT_BOARD" >/dev/null

echo "== FM-1: fenced '## ' heading truncates the show tail (reproduced-pin) =="
# A ```-fenced '## ' line inside Work Log ends the section for
# work_log_tail: every later entry drops out of tasks show.
f_fm1="$TASKS_DIR/current/20260101-0900-fm1-fence-show.md"
printf '%s\n' \
	'# Task: FM1 Fence Show Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Priority:** Medium' '**Updated:** 2026-01-01 08:00' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: first entry' '' 'first body' '' \
	'```' \
	'## Fence Headed Section' \
	'```' '' \
	'### 2026-01-01 10:00: worker: second entry' '' 'second body' \
	> "$f_fm1"
fm1_show="$(t show "$f_fm1")"
assert_contains "FM-1 safe-pin: tail shows the pre-fence entry" "$fm1_show" "first entry"
assert_not_contains "FM-1 reproduced-pin: tail hides the post-fence entry" "$fm1_show" "second entry"
assert_not_contains "FM-1 reproduced-pin: tail hides the post-fence body" "$fm1_show" "second body"

echo "== FM-2: tasks log inserts above the fenced heading (reproduced-pin) =="
# append_work_log_entry flushes the new entry at the first '## ' line
# seen inside Work Log, so a fenced heading captures it; entries below
# the fence stay in the file but out of every tail.
t log "$f_fm1" --from hazard "new entry after the fence" >/dev/null
fm1_entry_line="$(first_line_of "$f_fm1" "new entry after the fence")"
fm1_fence_line="$(first_line_of "$f_fm1" "## Fence Headed Section")"
fm1_second_line="$(first_line_of "$f_fm1" "second entry")"
if (( fm1_entry_line < fm1_fence_line )); then ok "FM-2 reproduced-pin: entry inserted above the fenced heading"; else bad "FM-2 reproduced-pin: entry inserted above the fenced heading (entry $fm1_entry_line, fence $fm1_fence_line)"; fi
if (( fm1_fence_line < fm1_second_line )); then ok "FM-2 safe-pin: hand-written entry sits below the fence"; else bad "FM-2 safe-pin: hand-written entry sits below the fence"; fi
fm1_show2="$(t show "$f_fm1")"
assert_contains "FM-2 safe-pin: tail carries the inserted entry" "$fm1_show2" "new entry after the fence"
assert_not_contains "FM-2 reproduced-pin: tail still hides the hand-written entry" "$fm1_show2" "second entry"
assert_contains "FM-2 safe-pin: the hidden entry is not deleted from the file" \
	"$(cat "$f_fm1")" "second body"

echo "== FM-3: quoted '## '/'### ' lines are inert (safe-pin; hazard claim refuted) =="
# The hazard paragraph's quoted-block half: a '>' prefix blocks the
# ^## / ^### match in the tail, the span anchors, and the append path.
f_fm3="$TASKS_DIR/current/20260101-0905-fm3-quoted.md"
printf '%s\n' \
	'# Task: FM3 Quoted Block Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Priority:** Medium' '**Updated:** 2026-01-01 08:00' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: quoted first' '' 'first body' '' \
	'> ## Quoted Heading' '' \
	'> ### 2026-01-01 09:30: worker: quoted anchor' '' \
	'middle body' '' \
	'### 2026-01-01 10:00: worker: quoted last' '' 'last body' \
	> "$f_fm3"
fm3_show="$(t show "$f_fm3" --tail 5)"
assert_contains "FM-3 safe-pin: quoted '## ' does not truncate the tail" "$fm3_show" "quoted last"
eval "$(awk '/^work_log_span\(\)/{f=1} f{print} f&&/^\}$/{exit}' "$TASKS_BIN")"
assert_eq "FM-3 safe-pin: quoted '### ' timestamp is not a span anchor" \
	"2026-01-01 09:00"$'\t'"2026-01-01 10:00" "$(work_log_span "$f_fm3")"
t log "$f_fm3" --from hazard "entry at true end" >/dev/null
fm3_entry_line="$(first_line_of "$f_fm3" "entry at true end")"
fm3_last_line="$(first_line_of "$f_fm3" "last body")"
if (( fm3_entry_line > fm3_last_line )); then ok "FM-3 safe-pin: log appends past the quoted block at section end"; else bad "FM-3 safe-pin: log appends past the quoted block at section end (entry $fm3_entry_line, last body $fm3_last_line)"; fi

echo "== FM-4: fenced '## ' in the header region truncates the header (reproduced-pin) =="
# header_of and assemble_rows stop at the first '^## ' line: fields after
# a fenced heading fall back to defaults in the render and escape the
# lint shape checks.
f_fm4="$LINT_BOARD/current/20260101-0900-fm4-fence-header.md"
printf '%s\n' \
	'# Task: FM4 Fence Header Probe' '' \
	'**Created:** 2026-01-01 08:00' '' \
	'```' \
	'## Fence Headed Section' \
	'```' '' \
	'**Status:** Ready' '**Priority:** High' '**Updated:** hand-stamped' '' \
	'## Table of Contents' '' \
	'## Objective' '' 'body' '' \
	'## Success Criteria' '' \
	'## Work Log' '' \
	'## Execution Log' '' 'body' \
	> "$f_fm4"
t render --dir "$LINT_BOARD" >/dev/null
fm4_lane="$(awk '/^## Triage/{f=1} /^## Ready/{f=0} f' "$LINT_BOARD/dashboard.md")"
assert_contains "FM-4 reproduced-pin: truncated header lands in the Triage lane" "$fm4_lane" "FM4 Fence Header Probe"
fm4_row="$(grep -F 'FM4 Fence Header Probe' "$LINT_BOARD/dashboard.md")"
assert_contains "FM-4 reproduced-pin: hidden Priority falls back to the default" "$fm4_row" "| Medium |"
fm4_show="$(t show --dir "$LINT_BOARD" "$(basename "$f_fm4")")"
assert_not_contains "FM-4 reproduced-pin: show header region stops at the fence" "$fm4_show" "**Status:** Ready"
fm4_lint="$(t lint --dir "$LINT_BOARD" 2>&1 || true)"
assert_contains "FM-4 reproduced-pin: lint reports the Status field missing" "$fm4_lint" \
	"current/$(basename "$f_fm4"): header Status field missing"
assert_not_contains "FM-4 reproduced-pin: shape-invalid Updated escapes the lint check" "$fm4_lint" \
	"current/$(basename "$f_fm4"): header Updated not CLI-shaped"

echo "== FM-4 control: fields in header position are checked (safe-pin) =="
f_fm4c="$LINT_BOARD/current/20260101-0901-fm4c-header-control.md"
printf '%s\n' \
	'# Task: FM4C Header Control Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Ready' '**Priority:** High' '**Updated:** hand-stamped' '' \
	'## Table of Contents' '' \
	'## Objective' '' 'body' '' \
	'## Success Criteria' '' \
	'## Work Log' '' \
	'## Execution Log' '' 'body' \
	> "$f_fm4c"
t render --dir "$LINT_BOARD" >/dev/null
fm4c_lint="$(t lint --dir "$LINT_BOARD" 2>&1 || true)"
assert_contains "FM-4 safe-pin control: lint flags the same value in header position" "$fm4c_lint" \
	"current/$(basename "$f_fm4c"): header Updated not CLI-shaped"

echo "== FM-5: the criteria section tracker runs on fenced headings (reproduced-pin) =="
# track_criteria_section updates SECNAME/INSC on every level-2 heading,
# fence included: a fenced heading inside Success Criteria clears INSC,
# so real unticked boxes after it count zero in the closure gate.
f_fm5a="$TASKS_DIR/current/20260101-0910-fm5a-gate-fence.md"
printf '%s\n' \
	'# Task: FM5A Gate Fence Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Success Criteria' '' \
	'```' \
	'## Fence Headed Section' \
	'```' '' \
	'- [ ] real unticked criterion' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$f_fm5a"
accept "FM-5 reproduced-pin: close passes an unticked box hidden behind a fenced heading" \
	close "$f_fm5a"
assert_eq "FM-5 reproduced-pin: the closed file is Completed" "Completed" "$(status_of "$f_fm5a")"

echo "== FM-5 control: the same box without a fence refuses (safe-pin) =="
f_fm5x="$TASKS_DIR/current/20260101-0911-fm5x-gate-control.md"
printf '%s\n' \
	'# Task: FM5X Gate Control Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Success Criteria' '' \
	'- [ ] real unticked criterion' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$f_fm5x"
fm5x_err="$(t close "$f_fm5x" 2>&1 >/dev/null || true)"
assert_contains "FM-5 safe-pin control: an unfenced unticked box refuses closure" "$fm5x_err" \
	"unchecked Success Criteria boxes: 1"

echo "== FM-5: boxes after a fenced heading under-count (reproduced-pin) =="
f_fm5b="$TASKS_DIR/current/20260101-0912-fm5b-undercount.md"
printf '%s\n' \
	'# Task: FM5B Undercount Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Success Criteria' '' \
	'- [ ] criterion before fence' '' \
	'```' \
	'## Fence Headed Section' \
	'```' '' \
	'- [ ] criterion after fence' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$f_fm5b"
assert_eq "FM-5 setup: the file carries two unticked boxes" "2" \
	"$(grep -c '^- \[ \] ' "$f_fm5b")"
fm5b_err="$(t close "$f_fm5b" 2>&1 >/dev/null || true)"
assert_contains "FM-5 reproduced-pin: the gate counts one of the two unticked boxes" "$fm5b_err" \
	"unchecked Success Criteria boxes: 1"

echo "== FM-5: a fenced '## Dependencies' heading toggles indeps scanning (reproduced-pin) =="
# closure_gate_scan sets indeps from SECNAME on every level-2 heading
# line, fence included: a task-ID citation inside a plain code fence
# becomes a declared child once a fenced '## Dependencies' heading
# precedes it.
sibling="$TASKS_DIR/current/ORCH-4-2-20260101-0900-child.md"
printf '%s\n' \
	'# Task: Sibling Child' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Triage' '**Updated:** 2026-01-01 08:00' '' \
	'## Objective' '' 'body' '' \
	'## Success Criteria' '' '- [ ] box' '' \
	'## Work Log' '' '### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$sibling"
f_fm5c="$TASKS_DIR/current/20260101-0913-fm5c-indeps-fence.md"
printf '%s\n' \
	'# Task: FM5C Indeps Fence Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Objective' '' 'body' '' \
	'```' \
	'## Dependencies' '' \
	'citing ORCH-4-2 inside a fence' \
	'```' '' \
	'## Success Criteria' '' '- [x] done box' '' \
	'## Work Log' '' '### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$f_fm5c"
fm5c_err="$(t close "$f_fm5c" 2>&1 >/dev/null || true)"
assert_contains "FM-5 reproduced-pin: fenced citation declares an open child" "$fm5c_err" \
	"unfinished named child task(s): ORCH-4-2"

echo "== FM-5 control: the same citation without the fenced heading is inert (safe-pin) =="
f_fm5d="$TASKS_DIR/current/20260101-0914-fm5d-indeps-control.md"
printf '%s\n' \
	'# Task: FM5D Indeps Control Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Objective' '' 'body' '' \
	'```' \
	'citing ORCH-4-2 inside a fence' \
	'```' '' \
	'## Success Criteria' '' '- [x] done box' '' \
	'## Work Log' '' '### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$f_fm5d"
accept "FM-5 safe-pin control: a fenced citation without the heading never blocks closure" \
	close "$f_fm5d"
rm -f "$sibling"
t render >/dev/null

echo "== FM-6: a fenced '## ' heading ends the span scan early (reproduced-pin) =="
# work_log_span exits at the first '^## ' line inside Work Log: anchors
# after the fence miss the Duration derivation on stamp.
f_fm6a="$TASKS_DIR/current/20260101-0920-fm6a-span-fence.md"
printf '%s\n' \
	'# Task: FM6A Span Fence Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Completed' '**Updated:** 2026-01-01 08:00' \
	'**Completed:** 2026-01-02 08:00' '**Duration:** N/A' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: real start' '' 'body' '' \
	'```' \
	'## Fence Headed Section' \
	'```' '' \
	'### 2026-01-01 11:00: worker: real end after fence' '' 'body' \
	> "$f_fm6a"
t stamp "$f_fm6a" >/dev/null
assert_eq "FM-6 reproduced-pin: Duration collapses to 0m (true span 2h)" "0m" "$(duration_of "$f_fm6a")"

echo "== FM-6 control: the same anchors without a fence derive 2h (safe-pin) =="
f_fm6x="$TASKS_DIR/current/20260101-0921-fm6x-span-control.md"
printf '%s\n' \
	'# Task: FM6X Span Control Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Completed' '**Updated:** 2026-01-01 08:00' \
	'**Completed:** 2026-01-02 08:00' '**Duration:** N/A' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: real start' '' 'body' '' \
	'### 2026-01-01 11:00: worker: real end' '' 'body' \
	> "$f_fm6x"
t stamp "$f_fm6x" >/dev/null
assert_eq "FM-6 safe-pin control: unfenced anchors derive the true 2h span" "2h" "$(duration_of "$f_fm6x")"

echo "== FM-6: a fenced '### <ts>:' line counts as the last anchor (reproduced-pin) =="
# The anchor regex runs on every '### ' line inside the section, fence
# included: a fenced fake anchor last in file order inflates the span.
f_fm6b="$TASKS_DIR/current/20260101-0922-fm6b-fenced-anchor.md"
printf '%s\n' \
	'# Task: FM6B Fenced Anchor Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Completed' '**Updated:** 2026-01-01 08:00' \
	'**Completed:** 2026-01-02 08:00' '**Duration:** N/A' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: real start' '' 'body' '' \
	'### 2026-01-01 10:00: worker: real end' '' 'body' '' \
	'```' \
	'### 2026-01-01 23:00: worker: fenced fake anchor' \
	'```' \
	> "$f_fm6b"
t stamp "$f_fm6b" >/dev/null
assert_eq "FM-6 reproduced-pin: Duration inflates to 14h (true span 1h)" "14h" "$(duration_of "$f_fm6b")"

echo "== FM-6 control: the same anchors with an empty fence derive 1h (safe-pin) =="
f_fm6y="$TASKS_DIR/current/20260101-0923-fm6y-fenced-anchor-control.md"
printf '%s\n' \
	'# Task: FM6Y Fenced Anchor Control Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Completed' '**Updated:** 2026-01-01 08:00' \
	'**Completed:** 2026-01-02 08:00' '**Duration:** N/A' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: real start' '' 'body' '' \
	'### 2026-01-01 10:00: worker: real end' '' 'body' '' \
	'```' \
	'empty fenced example' \
	'```' \
	> "$f_fm6y"
t stamp "$f_fm6y" >/dev/null
assert_eq "FM-6 safe-pin control: an anchor-free fence derives the true 1h span" "1h" "$(duration_of "$f_fm6y")"

echo "== FM-7: a fenced heading satisfies --section existence (reproduced-pin) =="
# section_level/replace_section_body classify headings fence-blind:
# tasks edit targets a fenced-only heading and its replacement span
# swallows everything after the fenced line.
f_fm7a="$TASKS_DIR/current/20260101-0930-fm7a-edit-fence.md"
printf '%s\n' \
	'# Task: FM7A Edit Fence Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Objective' '' 'objective body' '' \
	'## Real Section' '' 'real body' '' \
	'```' \
	'## Fence Headed Section' \
	'```' '' \
	'post-fence body' \
	> "$f_fm7a"
printf 'replaced body\n' | t edit "$f_fm7a" --section "Fence Headed Section" >/dev/null \
	&& ok "FM-7 reproduced-pin: edit targets a heading that exists only inside a fence" \
	|| bad "FM-7 reproduced-pin: edit targets a heading that exists only inside a fence"
fm7a_body="$(cat "$f_fm7a")"
assert_contains "FM-7 reproduced-pin: the replacement lands at the fenced heading" "$fm7a_body" "replaced body"
assert_not_contains "FM-7 reproduced-pin: the span swallows the post-fence body" "$fm7a_body" "post-fence body"
assert_eq "FM-7 reproduced-pin: the replacement swallows the closing fence line" "1" \
	"$(grep -c '^```$' "$f_fm7a")"

echo "== FM-7: append lands before a fenced heading inside the section (reproduced-pin) =="
f_fm7b="$TASKS_DIR/current/20260101-0931-fm7b-append-fence.md"
printf '%s\n' \
	'# Task: FM7B Append Fence Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Real Section' '' 'pre-fence body' '' \
	'```' \
	'## Fence Headed Section' \
	'```' '' \
	'post-fence body' \
	> "$f_fm7b"
printf 'appended body\n' | t edit "$f_fm7b" --section "Real Section" --append >/dev/null
fm7b_append_line="$(first_line_of "$f_fm7b" "appended body")"
fm7b_fence_line="$(first_line_of "$f_fm7b" "## Fence Headed Section")"
fm7b_post_line="$(first_line_of "$f_fm7b" "post-fence body")"
if (( fm7b_append_line < fm7b_fence_line )); then ok "FM-7 reproduced-pin: append ends at the fenced heading"; else bad "FM-7 reproduced-pin: append ends at the fenced heading (append $fm7b_append_line, fence $fm7b_fence_line)"; fi
if (( fm7b_fence_line < fm7b_post_line )); then ok "FM-7 safe-pin: post-fence content survives the append"; else bad "FM-7 safe-pin: post-fence content survives the append"; fi

echo "== FM-7: section creation inserts above a fenced anchor heading (reproduced-pin) =="
# insert_section_body scans for its anchor with the same fence-blind
# classifier: creating a missing template section whose canonical anchor
# exists only inside a fence lands the new heading inside the fence
# region, above the fenced line.
f_fm7c="$TASKS_DIR/current/20260101-0932-fm7c-insert-fence.md"
printf '%s\n' \
	'# Task: FM7C Insert Fence Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Objective' '' 'objective body' '' \
	'```' \
	'## Execution Log' \
	'```' \
	> "$f_fm7c"
printf 'created section body\n' | t edit "$f_fm7c" --section "Dependencies" >/dev/null \
	&& ok "FM-7 reproduced-pin: creation resolves its anchor to a fenced heading" \
	|| bad "FM-7 reproduced-pin: creation resolves its anchor to a fenced heading"
fm7c_created_line="$(first_line_of "$f_fm7c" "## Dependencies")"
fm7c_fence_line="$(first_line_of "$f_fm7c" '## Execution Log')"
if (( fm7c_created_line < fm7c_fence_line )); then ok "FM-7 reproduced-pin: the new section is inserted above the fenced anchor"; else bad "FM-7 reproduced-pin: the new section is inserted above the fenced anchor (created $fm7c_created_line, fence $fm7c_fence_line)"; fi

echo "== FM-8: duplicate '## Work Log' headings split the append paths (reproduced-pin drift) =="
# The literal matchers special-case '## Work Log' before the generic
# '^## ' boundary, so a duplicate heading re-opens the section for the
# tail, the span, and tasks log; the heading-level-aware edit path ends
# the first section at the duplicate. Two append paths disagree.
f_fm8="$TASKS_DIR/current/20260101-0940-fm8-duplicate-worklog.md"
printf '%s\n' \
	'# Task: FM8 Duplicate Work Log Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Priority:** Medium' '**Updated:** 2026-01-01 08:00' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: first-section entry' '' 'first body' '' \
	'## Work Log' '' \
	'### 2026-01-01 10:00: worker: second-section entry' '' 'second body' \
	> "$f_fm8"
fm8_show="$(t show "$f_fm8" --tail 5)"
assert_contains "FM-8 reproduced-pin: tail spans both duplicate sections" "$fm8_show" "second-section entry"
t log "$f_fm8" --from hazard "log-appended body" >/dev/null
fm8_log_line="$(first_line_of "$f_fm8" "log-appended body")"
fm8_second_line="$(first_line_of "$f_fm8" "second-section entry")"
if (( fm8_log_line > fm8_second_line )); then ok "FM-8 reproduced-pin: tasks log appends past the duplicate at file end"; else bad "FM-8 reproduced-pin: tasks log appends past the duplicate at file end (log $fm8_log_line, second section $fm8_second_line)"; fi

echo "== FM-8: edit --append ends at the duplicate heading (reproduced-pin drift) =="
f_fm8c="$TASKS_DIR/current/20260101-0941-fm8c-edit-duplicate.md"
printf '%s\n' \
	'# Task: FM8C Edit Duplicate Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: first-section entry' '' 'first body' '' \
	'## Work Log' '' \
	'### 2026-01-01 10:00: worker: second-section entry' '' 'second body' \
	> "$f_fm8c"
printf 'edit-appended body\n' | t edit "$f_fm8c" --section "Work Log" --append >/dev/null
fm8c_edit_line="$(first_line_of "$f_fm8c" "edit-appended body")"
# The duplicate heading is the second '## Work Log' line in the file.
fm8c_dup_line="$(grep -n '^## Work Log$' "$f_fm8c" | sed -n '2p' | cut -d: -f1)"
if (( fm8c_edit_line < fm8c_dup_line )); then ok "FM-8 reproduced-pin: edit --append lands above the duplicate heading"; else bad "FM-8 reproduced-pin: edit --append lands above the duplicate heading (edit $fm8c_edit_line, duplicate $fm8c_dup_line)"; fi

echo "== FM-8: the span derivation reads both duplicate sections (reproduced-pin) =="
f_fm8b="$TASKS_DIR/current/20260101-0942-fm8b-duplicate-span.md"
printf '%s\n' \
	'# Task: FM8B Duplicate Span Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Completed' '**Updated:** 2026-01-01 08:00' \
	'**Completed:** 2026-01-02 08:00' '**Duration:** N/A' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: first-section anchor' '' 'body' '' \
	'## Work Log' '' \
	'### 2026-01-01 11:00: worker: second-section anchor' '' 'body' \
	> "$f_fm8b"
t stamp "$f_fm8b" >/dev/null
assert_eq "FM-8 reproduced-pin: Duration spans anchors across the duplicate (2h)" "2h" "$(duration_of "$f_fm8b")"

echo "== FM-9: a level-3 '### Work Log' section is invisible (reproduced-pin) =="
# '/^## Work Log/' never matches a level-3 heading: the tail prints no
# entries, the span derives no anchors, and tasks log appends at EOF.
f_fm9="$TASKS_DIR/current/20260101-0950-fm9-level3.md"
printf '%s\n' \
	'# Task: FM9 Level3 Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Priority:** Medium' '**Updated:** 2026-01-01 08:00' '' \
	'## Objective' '' 'objective body' '' \
	'### Work Log' '' \
	'### 2026-01-01 09:00: worker: entry under level-3 heading' '' 'level-3 body' \
	> "$f_fm9"
fm9_show="$(t show "$f_fm9")"
assert_not_contains "FM-9 reproduced-pin: tail prints no entries under the level-3 heading" "$fm9_show" \
	"entry under level-3 heading"
t log "$f_fm9" --from hazard "entry at end of file" >/dev/null
fm9_entry_line="$(first_line_of "$f_fm9" "entry at end of file")"
fm9_last_body_line="$(first_line_of "$f_fm9" "level-3 body")"
if (( fm9_entry_line > fm9_last_body_line )); then ok "FM-9 reproduced-pin: log appends at end of file"; else bad "FM-9 reproduced-pin: log appends at end of file (entry $fm9_entry_line, last body $fm9_last_body_line)"; fi
f_fm9b="$TASKS_DIR/current/20260101-0951-fm9b-level3-span.md"
printf '%s\n' \
	'# Task: FM9B Level3 Span Probe' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** Completed' '**Updated:** 2026-01-01 08:00' \
	'**Completed:** 2026-01-02 08:00' '**Duration:** N/A' '' \
	'### Work Log' '' \
	'### 2026-01-01 09:00: worker: anchor under level-3 heading' '' 'body' '' \
	'### 2026-01-01 11:00: worker: second anchor under level-3 heading' '' 'body' \
	> "$f_fm9b"
t stamp "$f_fm9b" >/dev/null
assert_eq "FM-9 reproduced-pin: Duration derives N/A from an unread section" "N/A" "$(duration_of "$f_fm9b")"

echo "== FM-10: header fields after the first real '## ' heading are invisible (safe-pin) =="
# Decision (report-corrections addendum): stop-at-first-section is the
# intended header contract; a field placed after a real heading is a
# malformed file whose sanctioned signal is lint's missing-field
# finding, so these pins must stay green through any parser fix.
f_fm10="$LINT_BOARD/current/20260101-0960-fm10-field-order.md"
printf '%s\n' \
	'# Task: FM10 Field Order Probe' '' \
	'**Created:** 2026-01-01 08:00' '' \
	'## Objective' '' \
	'**Status:** Ready' '**Priority:** High' '**Updated:** hand-stamped' '' \
	'## Table of Contents' '' \
	'## Success Criteria' '' \
	'## Work Log' '' \
	'## Execution Log' '' 'body' \
	> "$f_fm10"
t render --dir "$LINT_BOARD" >/dev/null
fm10_lane="$(awk '/^## Triage/{f=1} /^## Ready/{f=0} f' "$LINT_BOARD/dashboard.md")"
assert_contains "FM-10 safe-pin: fields after the first heading land in the Triage lane" "$fm10_lane" "FM10 Field Order Probe"
fm10_row="$(grep -F 'FM10 Field Order Probe' "$LINT_BOARD/dashboard.md")"
assert_contains "FM-10 safe-pin: misplaced Priority falls back to the default" "$fm10_row" "| Medium |"
fm10_lint="$(t lint --dir "$LINT_BOARD" 2>&1 || true)"
assert_contains "FM-10 safe-pin: lint reports the Status field missing" "$fm10_lint" \
	"current/$(basename "$f_fm10"): header Status field missing"
assert_not_contains "FM-10 safe-pin: shape-invalid Updated outside the header region escapes the shape check" "$fm10_lint" \
	"current/$(basename "$f_fm10"): header Updated not CLI-shaped"

echo "== FM-11: criteria_box is fence-aware (safe-pin control) =="
# The one fence-aware surface: fenced checkbox and ~ marker lines count
# zero in the closure gate and the lint. This pin guards the control so
# the parser fix cannot regress fence-awareness here. The lint count is
# observable only on a terminal file (the unchecked advisory fires on
# Completed status), so the count pin closes with --force and asserts
# the advisory reports the real box alone (a broken fence toggle would
# report 2).
f_fm11="$TASKS_DIR/current/20260101-0970-fm11-fence-awareness.md"
printf '%s\n' \
	'# Task: FM11 Fence Awareness Control' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Success Criteria' '' \
	'- [ ] real unticked criterion' '' \
	'```' \
	'- [ ] fenced example box' \
	'```' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$f_fm11"
fm11_err="$(t close "$f_fm11" 2>&1 >/dev/null || true)"
assert_contains "FM-11 safe-pin: the gate counts the real box, not the fenced one" "$fm11_err" \
	"unchecked Success Criteria boxes: 1"
t close --force "$f_fm11" >/dev/null
fm11_lint="$(t lint --verbose 2>&1 || true)"
assert_contains "FM-11 safe-pin: lint counts the real box alone on the closed file" "$fm11_lint" \
	"$(basename "$f_fm11"): Status Completed with 1 unchecked Success Criteria boxes"

f_fm11b="$TASKS_DIR/current/20260101-0971-fm11b-fenced-marker.md"
printf '%s\n' \
	'# Task: FM11B Fenced Marker Control' '' \
	'**Created:** 2026-01-01 08:00' '**Status:** In Progress' '**Updated:** 2026-01-01 08:00' '' \
	'## Success Criteria' '' \
	'- ~ [ ] real superseded criterion' '' \
	'```' \
	'- ~ [ ] fenced superseded example' \
	'```' '' \
	'## Work Log' '' \
	'### 2026-01-01 09:00: worker: anchor' '' 'body' \
	> "$f_fm11b"
accept "FM-11 safe-pin: the real ~ marker alone resolves closure" close "$f_fm11b"
fm11_log="$(awk '/^## Work Log/{f=1} f' "$f_fm11b")"
assert_contains "FM-11 safe-pin: the close note lists the real superseded criterion" "$fm11_log" \
	"1 superseded Success Criteria: real superseded criterion"
assert_not_contains "FM-11 safe-pin: the fenced ~ marker stays out of the close note" "$fm11_log" \
	"fenced superseded example"

echo "== FM-12: header extraction agreement matrix (safe-pin controls, two agreement pins, one drift finding) =="
# The three header extractions over the shared fixture set: header_of
# (tasks show), assemble_rows (the render), lint_scan_files (the lint).
# Control: all three agree. FM-4/FM-10: all three agree the fields are
# absent. Drift finding: the bare '## ' heading stops header_of and
# assemble_rows but leaves lint_scan_files reading the header, because
# heading_level returns 2 with empty HTEXT and track_criteria_section
# keeps inhdr set when SECNAME is empty. The FM-4 agreement pin flips
# with the FM-4 fix; the FM-10 agreement pin holds per the
# report-corrections addendum's stop-at-first-section decision.
fm4c_row="$(grep -F 'FM4C Header Control Probe' "$LINT_BOARD/dashboard.md")"
fm4c_lint="$(t lint --dir "$LINT_BOARD" 2>&1 || true)"
fm4c_show="$(t show --dir "$LINT_BOARD" "$(basename "$f_fm4c")")"
assert_contains "FM-12 safe-pin control: render reads the real Priority" "$fm4c_row" "| High |"
assert_contains "FM-12 safe-pin control: lint reads the same fields" "$fm4c_lint" \
	"current/$(basename "$f_fm4c"): header Updated not CLI-shaped"
assert_contains "FM-12 safe-pin control: show reads the same fields" "$fm4c_show" "**Status:** Ready"
assert_not_contains "FM-12 safe-pin control: lint finds no missing Status on the control" "$fm4c_lint" \
	"current/$(basename "$f_fm4c"): header Status field missing"
fm12_fm4_row="$(grep -F 'FM4 Fence Header Probe' "$LINT_BOARD/dashboard.md")"
assert_contains "FM-12 reproduced-pin agreement: render shows the default fallback row for the FM-4 fixture" "$fm12_fm4_row" "| Medium |"
fm12_fm10_row="$(grep -F 'FM10 Field Order Probe' "$LINT_BOARD/dashboard.md")"
assert_contains "FM-12 safe-pin agreement: render shows the default fallback row for the FM-10 fixture" "$fm12_fm10_row" "| Medium |"

echo "== FM-12 drift: a bare '## ' heading splits lint from render and show (reproduced-pin) =="
# heading_level('## ') is 2 with empty HTEXT, so track_criteria_section
# sets SECNAME to empty and lint_scan_files keeps scanning the header,
# while header_of and assemble_rows stop at the '^## ' line.
f_fm12="$LINT_BOARD/current/20260101-0980-fm12-bare-heading-drift.md"
printf '%s\n' \
	'# Task: FM12 Bare Heading Drift Probe' '' \
	'**Created:** 2026-01-01 08:00' '' \
	'## ' '' \
	'**Status:** Ready' '**Priority:** High' '**Updated:** 2026-01-01 08:00' '' \
	'## Table of Contents' '' \
	'## Objective' '' 'body' '' \
	'## Success Criteria' '' \
	'## Work Log' '' \
	'## Execution Log' '' 'body' \
	> "$f_fm12"
t render --dir "$LINT_BOARD" >/dev/null
fm12_lane="$(awk '/^## Triage/{f=1} /^## Ready/{f=0} f' "$LINT_BOARD/dashboard.md")"
assert_contains "FM-12 reproduced-pin: render stops at the bare heading (Triage lane)" "$fm12_lane" \
	"FM12 Bare Heading Drift Probe"
fm12_show="$(t show --dir "$LINT_BOARD" "$(basename "$f_fm12")")"
assert_not_contains "FM-12 reproduced-pin: show header region stops at the bare heading" "$fm12_show" \
	"**Status:** Ready"
fm12_lint="$(t lint --dir "$LINT_BOARD" 2>&1 || true)"
assert_not_contains "FM-12 reproduced-pin: lint keeps reading fields past the bare heading" "$fm12_lint" \
	"current/$(basename "$f_fm12"): header Status field missing"

print_result
((fail == 0)) || exit 1
