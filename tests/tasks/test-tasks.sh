#!/usr/bin/env bash
#
# Tests for the `tasks` board tool. Self-contained: builds a scratch .tasks/
# dir under a temp root, exercises each command, and asserts the derived
# dashboard, idempotency, atomic claiming, lane placement, and the
# canonical-root resolution guard.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASKS_BIN="$REPO_ROOT/opencode/.local/bin/tasks"

source "$REPO_ROOT/tests/lib/harness.sh"

refuse() { # label; rest is the command to attempt
	local label="$1"; shift
	if t "$@" </dev/null >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export TASKS_DIR="$ROOT/.tasks"
# Pin the CLI clock: backdating fixtures and stamp/close assertions read
# deterministic timestamps, and the set guard admits CLI-owned header
# fields only under this sanctioned test seam. TASKS_DIR above and the
# clock must stay exported together; the CLI's co-gate refuses a clock
# without an explicit TASKS_DIR.
export TASKS_TEST_CLOCK="2026-06-15 12:00"
DASH="$TASKS_DIR/dashboard.md"

t() { "$TASKS_BIN" "$@"; }

edit_stderr_of() { # rest is the edit invocation; echoes its stderr
	# edit consumes stdin even when refusing, so detach it
	t edit "$@" </dev/null 2>&1 >/dev/null || true
}

# The battery pins the CLI clock through TASKS_TEST_CLOCK (the sanctioned
# seam the set-guard section exercises), so assertions on CLI-refreshed
# timestamps compare against the pinned clock's date. The fallback keeps
# the same assertion meaningful when the battery runs unpinned.
clock_today() { printf '%s\n' "${TASKS_TEST_CLOCK%% *}"; }

echo "== init =="
t init >/dev/null
[[ -d "$TASKS_DIR/current" && -d "$TASKS_DIR/archive" && -f "$DASH" ]] \
	&& ok "init scaffolds dirs and dashboard" || bad "init scaffolds dirs and dashboard"
board="$(cat "$DASH")"
for lane in "## Triage" "## Ready" "## In Progress" "## Blocked/Cancelled" "## Completed" "## Archive"; do
	assert_contains "board has lane $lane" "$board" "$lane"
done

echo "== init: idempotent on an existing board (G14 pin) =="
# Running init on a live board must scaffold nothing away and rewrite
# nothing: both subdirs still exist, existing task files survive, and the
# derived dashboard comes back byte-identical (init only ever renders,
# and render is a pure function of the task files).
f_idem="$(t new --id IDM-1 --name "Idempotent Init Target")"
idem_board="$(cat "$DASH")"
idem_out="$(t init)"
assert_eq "init on an existing board reports the same directory" "$TASKS_DIR" "$idem_out"
[[ -d "$TASKS_DIR/current" && -d "$TASKS_DIR/archive" ]] && ok "init keeps both subdirs" || bad "init keeps both subdirs"
[[ -f "$f_idem" ]] && ok "init leaves existing task files in place" || bad "init leaves existing task files in place"
assert_eq "init on an existing board leaves the dashboard byte-identical" "$idem_board" "$(cat "$DASH")"
rm -f "$f_idem"
t render >/dev/null

echo "== new =="
f_ip="$(t new --id API-1 --name "Refactor the Auth Flow" --status "In Progress" --priority High)"
f_tr="$(t new --id API-2 --name "Add Rate Limiting" --priority Low)"
f_rd="$(t new --id API-3 --name "Document Endpoints" --status Ready --priority Medium)"
[[ -f "$f_ip" && -f "$f_tr" && -f "$f_rd" ]] && ok "new creates task files" || bad "new creates task files"
assert_contains "new writes canonical header" "$(cat "$f_ip")" "**Owner:**"
assert_contains "new sets Priority" "$(cat "$f_ip")" "**Priority:** High"

echo "== set (progress + updated) =="
t set "$f_ip" Progress=45% >/dev/null
assert_contains "set writes Progress" "$(header=$(awk '/^## /{exit}{print}' "$f_ip"); echo "$header")" "**Progress:** 45%"
# Updated auto-refreshes and no duplicate Owner line appears
owner_lines="$(grep -c '^\*\*Owner:\*\*' "$f_ip")"
assert_eq "no duplicate Owner line after set" "1" "$owner_lines"

echo "== lane placement =="
board="$(cat "$DASH")"
# In Progress row carries the percentage and priority
ip_row="$(grep -F 'Refactor the Auth Flow' <<<"$board")"
assert_contains "In Progress row shows 45%" "$ip_row" "45%"
assert_contains "In Progress row links into current/" "$ip_row" "(./current/"
# Triage and Ready placement
assert_contains "Triage lane lists API-2 task" "$(awk '/^## Triage/{f=1} /^## Ready/{f=0} f' <<<"$board")" "Add Rate Limiting"
assert_contains "Ready lane lists API-3 task" "$(awk '/^## Ready/{f=1} /^## In Progress/{f=0} f' <<<"$board")" "Document Endpoints"

echo "== created column =="
assert_contains "new writes a canonical Created field" "$(cat "$f_tr")" "**Created:**"
assert_contains "Triage header carries a Created column" "$board" "| Task | Priority | Created | Updated |"
assert_contains "Ready header carries a Created column" "$board" "| Task | Priority | Created | Updated |"
assert_contains "Blocked/Cancelled header carries a Created column" "$board" "| Task | Status | Created | Updated |"
tr_created="$(grep -oP '^\*\*Created:\*\*\s+\K.*' "$f_tr")"
assert_contains "Triage row shows the task's Created timestamp" "$(grep -F 'Add Rate Limiting' <<<"$board")" "$tr_created"
# A task file predating the canonical field still renders its real creation date
legacy="$TASKS_DIR/current/20240101-0900-legacy-created-line.md"
cat >"$legacy" <<'EOF'
# Task: Legacy Created Line

*Created: 2024-01-01 09:00*
**Status:** Triage
**Priority:** Low
**Updated:** 2024-01-01 09:30

## Objective
EOF
t render >/dev/null
assert_contains "legacy *Created:* line still yields a date" "$(grep -F 'Legacy Created Line' "$DASH")" "2024-01-01 09:00"
# A task file with no creation timestamp at all falls back to N/A
undated="$TASKS_DIR/current/20240101-1000-undated-task.md"
cat >"$undated" <<'EOF'
# Task: Undated Task

**Status:** Triage
**Priority:** Low
**Updated:** 2024-01-01 10:00

## Objective
EOF
t render >/dev/null
assert_contains "missing creation timestamp renders N/A" "$(grep -F 'Undated Task' "$DASH")" "| N/A |"
rm -f "$legacy" "$undated"
t render >/dev/null
board="$(cat "$DASH")"

echo "== idempotent render =="
before="$(cat "$DASH")"
t render >/dev/null
after="$(cat "$DASH")"
assert_eq "render is byte-identical on no change" "$before" "$after"

echo "== Last updated is derived (newest Updated), not wall-clock =="
newest_updated="$(grep -hoP '^\*\*Updated:\*\*\s+\K.*' "$TASKS_DIR"/current/*.md | LC_ALL=C sort | tail -1)"
last_line="$(grep -oP '^\*Last updated: \K.*(?=\*)' "$DASH")"
assert_eq "Last updated equals newest task Updated" "$newest_updated" "$last_line"

echo "== atomic claim (concurrent race, exactly one winner) =="
outdir="$(mktemp -d)"
for i in 1 2 3 4 5; do
	( t claim "$f_tr" --owner "sess-$i" >"$outdir/$i.out" 2>&1; echo $? >"$outdir/$i.code" ) &
done
wait
winners=0; losers=0
for i in 1 2 3 4 5; do
	code="$(cat "$outdir/$i.code")"
	if [[ "$code" == "0" ]]; then winners=$((winners + 1)); else losers=$((losers + 1)); fi
done
assert_eq "exactly one claimer wins" "1" "$winners"
assert_eq "the other four lose" "4" "$losers"
[[ -f "$f_tr.claim" ]] && ok "claim sidecar exists" || bad "claim sidecar exists"
claimed_owner="$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_tr")"
assert_contains "Owner field set to the winning session" "$claimed_owner" "sess-"
rm -rf "$outdir"

echo "== double claim rejected =="
refuse "second claim rejected" claim "$f_tr" --owner "intruder"

echo "== release clears claim and owner =="
t release "$f_tr" >/dev/null
[[ ! -f "$f_tr.claim" ]] && ok "sidecar removed on release" || bad "sidecar removed on release"
owner_after="$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_tr" || true)"
assert_eq "Owner cleared on release" "" "${owner_after:-}"
assert_eq "release leaves the Owner field present and empty" "1" \
	"$(grep -c '^\*\*Owner:\*\*$' "$f_tr")"

echo "== release: any session may release a foreign claim (G15 pin) =="
# Release is a cooperative unlock, not an ownership transfer: the
# stale-sidecar recovery path depends on any board-writer session being
# able to release a claim left behind by a dead session. The mismatch is
# announced, never refused: a foreign release warns with both identities
# and then succeeds, so recovery can never dead-end on a dead owner.
f_xo="$(t new --id XOWN-1 --name "Cross Owner Release Target")"
t claim "$f_xo" --owner session-alice >/dev/null
assert_contains "claim sets the owning session" "$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_xo")" "session-alice"
xo_err_file="$ROOT/xo-release-err.txt"
xo_out="$(TASKS_SESSION=session-bob t release "$f_xo" 2>"$xo_err_file")" && xo_rc=0 || xo_rc=$?
assert_eq "a foreign session's release succeeds" "0" "$xo_rc"
assert_contains "a foreign session's release reports success" "$xo_out" "released XOWN-1"
xo_err="$(cat "$xo_err_file")"
assert_contains "the foreign-release warning reads as a warning" "$xo_err" "warning:"
assert_contains "the warning names the sidecar's recorded owner" "$xo_err" "session-alice"
assert_contains "the warning names the releasing session" "$xo_err" "session-bob"
assert_contains "the warning announces the recovery unlock" "$xo_err" "recovery unlock"
[[ ! -f "$f_xo.claim" ]] && ok "a foreign session's release removes the sidecar" || bad "a foreign session's release removes the sidecar"
owner_cross="$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_xo" || true)"
assert_eq "a foreign session's release clears Owner" "" "${owner_cross:-}"
rm -f "$f_xo" "$xo_err_file"
# The matching-identity leg stays silent: the warning fires on the
# mismatch, not on release itself.
f_xo2="$(t new --id XOWN-2 --name "Same Owner Release Target")"
TASKS_SESSION=session-carol t claim "$f_xo2" >/dev/null
xo2_err="$(TASKS_SESSION=session-carol t release "$f_xo2" 2>&1 >/dev/null || true)"
assert_not_contains "a same-session release does not warn" "$xo2_err" "warning:"
rm -f "$f_xo2"
t render >/dev/null

echo "== blocked lane =="
t set "$f_tr" Status=Blocked "Status Reason=lane placement probe" >/dev/null
blocked_lane="$(awk '/^## Blocked\/Cancelled/{f=1} /^## Completed/{f=0} f' <"$DASH")"
assert_contains "blocked task appears in Blocked/Cancelled lane" "$blocked_lane" "Add Rate Limiting"
assert_contains "blocked row carries its Created timestamp" "$blocked_lane" "$tr_created"
assert_contains "blocked row states the status" "$blocked_lane" "| Blocked |"
t set "$f_tr" Status=Triage >/dev/null

echo "== completed and archive lanes =="
t set "$f_rd" Status=Completed Completed="2026-07-09 18:00" Duration="2h 15m" >/dev/null
board="$(cat "$DASH")"
comp_lane="$(awk '/^## Completed/{f=1} /^## Archive/{f=0} f' <<<"$board")"
assert_contains "completed task appears in Completed lane" "$comp_lane" "Document Endpoints"
assert_contains "Completed lane carries the duration" "$comp_lane" "2h 15m"
# Move a file to archive/ and confirm it renders in the Archive lane
mv "$f_rd" "$TASKS_DIR/archive/"
t render >/dev/null
board="$(cat "$DASH")"
arch_lane="$(awk '/^## Archive/{f=1} f' <<<"$board")"
assert_contains "archived task appears in Archive lane" "$arch_lane" "(./archive/"
comp_lane="$(awk '/^## Completed/{f=1} /^## Archive/{f=0} f' <<<"$board")"
assert_not_contains "archived task left the Completed lane" "$comp_lane" "Document Endpoints"

echo "== --dir flag on init/render/new/set =="
dirtasks="$ROOT/flagtest/.tasks"
dirout="$(t init --dir "$dirtasks")"
assert_eq "init --dir reports the requested directory" "$dirtasks" "$dirout"
[[ -d "$dirtasks/current" && -d "$dirtasks/archive" && -f "$dirtasks/dashboard.md" ]] \
	&& ok "init --dir scaffolds the requested directory" || bad "init --dir scaffolds the requested directory"
f_dir="$(t new --id DIR-1 --name "Dir Flag Task" --dir "$dirtasks")"
[[ -f "$f_dir" ]] && ok "new --dir creates the task in the requested directory" || bad "new --dir creates the task in the requested directory"
t set --dir "$dirtasks" "$(basename "$f_dir")" Status=Ready Progress=25% >/dev/null
t render --dir "$dirtasks"
flagboard="$(cat "$dirtasks/dashboard.md")"
assert_contains "render --dir rebuilds the requested board" "$flagboard" "Dir Flag Task"
assert_contains "set --dir applies to the requested board" \
	"$(awk '/^## Ready/{f=1} /^## In Progress/{f=0} f' <<<"$flagboard")" "Dir Flag Task"
assert_not_contains "main board is untouched by --dir traffic" "$(cat "$DASH")" "Dir Flag Task"

echo "== valueless option guards on pre-existing subcommands =="
# A flag at end of argv, or followed by another flag, must refuse with a
# usage error instead of aborting on an unbound variable or swallowing the
# next flag as the value.
init_guard_err="$(t init --dir --bogus 2>&1 >/dev/null || true)"
assert_contains "init refuses a valueless --dir" "$init_guard_err" "init: --dir requires a value"
render_guard_err="$(t render --dir --bogus 2>&1 >/dev/null || true)"
assert_contains "render refuses a valueless --dir" "$render_guard_err" "render: --dir requires a value"
new_guard_err="$(t new --id --API-9 2>&1 >/dev/null || true)"
assert_contains "new refuses a valueless --id" "$new_guard_err" "new: --id requires a value"
set_guard_err="$(t set --dir --bogus 2>&1 >/dev/null || true)"
assert_contains "set refuses a valueless --dir" "$set_guard_err" "set: --dir requires a value"
claim_guard_err="$(t claim "$f_tr" --owner --bogus 2>&1 >/dev/null || true)"
assert_contains "claim refuses a valueless --owner" "$claim_guard_err" "claim: --owner requires a value"
release_guard_err="$(t release --dir --bogus 2>&1 >/dev/null || true)"
assert_contains "release refuses a valueless --dir" "$release_guard_err" "release: --dir requires a value"
init_guard_err="$(t init --dir 2>&1 >/dev/null || true)"
assert_contains "init refuses a trailing --dir" "$init_guard_err" "init: --dir requires a value"
render_guard_err="$(t render --dir 2>&1 >/dev/null || true)"
assert_contains "render refuses a trailing --dir" "$render_guard_err" "render: --dir requires a value"
new_guard_err="$(t new --id 2>&1 >/dev/null || true)"
assert_contains "new refuses a trailing --id" "$new_guard_err" "new: --id requires a value"
set_guard_err="$(t set --dir 2>&1 >/dev/null || true)"
assert_contains "set refuses a trailing --dir" "$set_guard_err" "set: --dir requires a value"
claim_guard_err="$(t claim "$f_tr" --owner 2>&1 >/dev/null || true)"
assert_contains "claim refuses a trailing --owner" "$claim_guard_err" "claim: --owner requires a value"
release_guard_err="$(t release --dir 2>&1 >/dev/null || true)"
assert_contains "release refuses a trailing --dir" "$release_guard_err" "release: --dir requires a value"

echo "== --flag=VALUE long form =="
# The space-separated form refuses any value beginning with --, so such
# values are only expressible through the long form; it must round-trip
# verbatim while the space form stays exactly as it is today.
escdir="$ROOT/longform/.tasks"
t init --dir="$escdir" >/dev/null
f_esc1="$(t new --id=ESC-1 --name=--force --status=Ready --priority=High --dir="$escdir")"
[[ -f "$f_esc1" ]] && ok "new accepts long-form options" || bad "new accepts long-form options"
assert_contains "new --name=--force writes the raw name" "$(head -1 "$f_esc1")" "# Task: --force"
assert_contains "new --name=--force writes the raw objective" "$(cat "$f_esc1")" "[ESC-1] --force"
assert_contains "new --status= writes the status" "$(cat "$f_esc1")" "**Status:** Ready"
assert_contains "new --priority= writes the priority" "$(cat "$f_esc1")" "**Priority:** High"
f_esc2="$(t new --id=ESC-2 --name "Long Form Target")"
[[ -f "$f_esc2" ]] && ok "long and space forms mix in one invocation" || bad "long and space forms mix in one invocation"
t render --dir="$escdir" >/dev/null
assert_contains "render --dir= rebuilds the requested board" "$(cat "$escdir/dashboard.md")" "--force"
t set --dir="$escdir" "$(basename "$f_esc1")" Status=Blocked "Status Reason=long form probe" >/dev/null
assert_contains "set --dir= applies to the requested board" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_esc1")" "Blocked"
t claim --dir="$escdir" "$(basename "$f_esc1")" --owner=sess-longform >/dev/null
assert_contains "claim --owner= writes the owner" "$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_esc1")" "sess-longform"
t release --dir="$escdir" "$(basename "$f_esc1")" >/dev/null
assert_eq "release --dir= clears the owner" "" "$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_esc1" || true)"
show_esc="$(t show --dir="$escdir" "$(basename "$f_esc1")")"
assert_contains "show --dir= reads the requested board" "$show_esc" "# Task: --force"
t log --dir="$escdir" "$(basename "$f_esc1")" --from=Worker-LF3 "Long form dir log" >/dev/null
assert_contains "log --dir= and --from= apply together" "$(cat "$f_esc1")" "Worker-LF3: Long form dir log"
printf 'Long form dir edit body\n' | t edit --dir="$escdir" "$(basename "$f_esc1")" --section=Objective >/dev/null
assert_contains "edit --dir= and --section= apply together" "$(cat "$f_esc1")" "Long form dir edit body"
printf 'Long form dir report body\n' | t report --dir="$escdir" "$(basename "$f_esc1")" --slug=dir-lf --digest="dir long form" >/dev/null
[[ -f "$escdir/reports/$(basename "$f_esc1")/01-dir-lf.md" ]] \
	&& ok "report --dir= deposits under the requested board" || bad "report --dir= deposits under the requested board"
printf 'Long form report body\n' | t report "$f_esc2" --slug=long-form --from=Worker-LF --digest="equals = inside" >/dev/null
[[ -f "$TASKS_DIR/reports/$(basename "$f_esc2")/01-long-form.md" ]] \
	&& ok "report --slug= deposits the file" || bad "report --slug= deposits the file"
assert_contains "report --from= attributes the entry" "$(cat "$f_esc2")" "Worker-LF: Report"
assert_contains "report --digest= keeps equals signs" "$(cat "$f_esc2")" "**Digest:** equals = inside"
t log "$f_esc2" --from=Worker-LF2 "Long form log entry" >/dev/null
assert_contains "log --from= headings the worker" "$(cat "$f_esc2")" "Worker-LF2: Long form log entry"
printf 'Long form section body\n' | t edit "$f_esc2" --section=Objective >/dev/null
assert_contains "edit --section= replaces the body" "$(cat "$f_esc2")" "Long form section body"
show_lf="$(t show "$f_esc2" --tail=1)"
assert_eq "show --tail=1 prints one entry" "1" "$(grep -c '^### ' <<<"$show_lf")"
assert_contains "show --tail= includes the newest entry" "$show_lf" "Worker-LF2: Long form log entry"
refuse "new rejects an empty --name= value" new --id=ESC-9 --name=
refuse "report rejects an empty --slug= value" report "$f_esc2" --slug= --digest d
refuse "new rejects an unknown long-form option" new --bogus=x
assert_contains "usage documents the long-form escape" "$(t help)" '--name=--force'

echo "== concurrent set serializes (no lost update) =="
f_cs="$(t new --id API-4 --name "Concurrency Set Target")"
concdir="$(mktemp -d)"
concfail=0
file_field() { grep -oP "^\\*\\*$1:\\*\\*\\s+\\K.*" "$f_cs"; }
board_cell() { grep -F 'Concurrency Set Target' "$DASH" | cut -d'|' -f"$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
for round in 1 2 3 4 5 6 7 8 9 10 11 12; do
	# Two writers update concurrently: one rewrites Priority, the other
	# Updated. A stale read-modify-write reverts the other writer's field
	# while both exit 0; under the board lock both values land no matter
	# which writer goes first, so any mismatch is a lost update.
	t set "$f_cs" Priority=Medium Updated="2020-01-01 00:00" >/dev/null
	t set "$f_cs" Priority=High Updated="2030-01-01 12:00" >"$concdir/a.out" 2>&1 &
	a_pid=$!
	t set "$f_cs" Updated="2030-01-01 12:00" >"$concdir/b.out" 2>&1 &
	b_pid=$!
	wait "$a_pid"; a_code=$?
	wait "$b_pid"; b_code=$?
	[[ "$a_code" == 0 && "$b_code" == 0 ]] || concfail=$((concfail + 1))
	[[ "$(file_field Priority)" == "High" ]] || concfail=$((concfail + 1))
	[[ "$(file_field Updated)" == "2030-01-01 12:00" ]] || concfail=$((concfail + 1))
	# The same lock covers each render, so the dashboard row must equal the file.
	[[ "$(board_cell 3)" == "$(file_field Priority)" ]] || concfail=$((concfail + 1))
	[[ "$(board_cell 5)" == "$(file_field Updated)" ]] || concfail=$((concfail + 1))
done
assert_eq "concurrent set loses no update across rounds" "0" "$concfail"
rm -rf "$concdir"

echo "== status enum validation =="
refuse "set rejects an unknown status" set "$f_cs" Status=Bogus
assert_contains "rejected status leaves the file untouched" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_cs")" "Triage"
refuse "new rejects an unknown status" new --id API-5 --name "Bogus Status Task" --status Bogus
if t set "$f_cs" Status=Blocked "Status Reason=enum probe" >/dev/null 2>&1; then ok "set accepts a valid status"; else bad "set accepts a valid status"; fi
t set "$f_cs" Status=Triage >/dev/null

echo "== priority enum validation =="
# The Priority vocabulary is pinned to the corpus's own set (Low, Medium,
# High); new and set must reject anything else before any write lands.
f_pri="$(t new --id PRI-1 --name "Priority Enum Target")"
pri_before="$(cat "$f_pri")"
pri_err="$(t new --id PRI-2 --name "Bad Priority" --priority Critical 2>&1 >/dev/null || true)"
refuse "new rejects an unknown priority" new --id PRI-2 --name "Bad Priority" --priority Critical
assert_contains "new's priority refusal names the vocabulary" "$pri_err" "valid: Low, Medium, High"
pri_err="$(t set "$f_pri" Priority=Critical 2>&1 >/dev/null || true)"
refuse "set rejects an unknown priority" set "$f_pri" Priority=Critical
assert_contains "set's priority refusal names the vocabulary" "$pri_err" "valid: Low, Medium, High"
assert_eq "rejected priorities leave the file byte-identical" "$pri_before" "$(cat "$f_pri")"
refuse "set rejects an empty-value Priority pair" set "$f_pri" Priority=
if t set "$f_pri" Priority=High >/dev/null 2>&1; then ok "set accepts a valid priority"; else bad "set accepts a valid priority"; fi
f_pri_low="$(t new --id PRI-3 --name "Low Priority Task" --priority Low)"
assert_contains "new writes a valid priority" "$(grep -oP '^\*\*Priority:\*\*\s+\K.*' "$f_pri_low")" "Low"
rm -f "$f_pri" "$f_pri_low"
t render >/dev/null

echo "== set: Progress must be N% form =="
# The render's percent normalization is a legacy-file fallback, not a
# license for set: a bare number is refused outright instead of landing
# unmarked and getting silently coerced at render time.
f_prg="$(t new --id PRG-1 --name "Progress Format Target")"
prg_before="$(cat "$f_prg")"
prg_err="$(t set "$f_prg" Progress=45 2>&1 >/dev/null || true)"
refuse "set rejects a bare-number Progress" set "$f_prg" Progress=45
assert_contains "bare-number refusal names the N% contract" "$prg_err" "Progress must be an N% percentage"
refuse "set rejects a non-numeric Progress" set "$f_prg" Progress=half
refuse "set rejects a spaced Progress suffix" set "$f_prg" "Progress=45 %"
refuse "set validates Progress before applying other pairs" set "$f_prg" Priority=High Progress=45
assert_not_contains "a refused Progress writes none of the batch" "$(cat "$f_prg")" "**Priority:** High"
assert_eq "rejected Progress values leave the file byte-identical" "$prg_before" "$(cat "$f_prg")"
t set "$f_prg" Progress=45% >/dev/null
assert_contains "N%-form Progress still lands" "$(grep -oP '^\*\*Progress:\*\*\s+\K.*' "$f_prg")" "45%"
prg_err="$(t set "$f_prg" Progress=101% 2>&1 >/dev/null || true)"
refuse "set rejects Progress above 100" set "$f_prg" Progress=101%
assert_contains "the range refusal names the 0-100 bound" "$prg_err" "Progress must be 0-100 inclusive"
refuse "set rejects far-out-of-range Progress" set "$f_prg" Progress=456%
t set "$f_prg" Progress=100% >/dev/null
assert_contains "Progress 100% lands" "$(grep -oP '^\*\*Progress:\*\*\s+\K.*' "$f_prg")" "100%"
t set "$f_prg" Progress=0% >/dev/null
assert_contains "Progress 0% lands" "$(grep -oP '^\*\*Progress:\*\*\s+\K.*' "$f_prg")" "0%"
t set "$f_prg" Progress= >/dev/null
assert_eq "Progress deletion stays allowed" "0" "$(grep -c '^\*\*Progress:\*\*' "$f_prg")"
rm -f "$f_prg"
t render >/dev/null

echo "== new: duplicate ID guard =="
# An ID names one piece of work across the whole board: a second new with
# a live ID must refuse instead of silently splitting it across two files,
# current/ and archive/ alike. --force is the documented override for
# deliberate reuse, and the dash-anchored glob must not false-positive on
# a longer ID sharing a prefix.
f_d1="$(t new --id DUP-1 --name "Duplicate Guard First")"
dup_err="$(t new --id DUP-1 --name "Duplicate Guard Second" 2>&1 >/dev/null || true)"
refuse "new refuses a duplicate task ID in current/" new --id DUP-1 --name "Duplicate Guard Second"
assert_contains "duplicate refusal names the existing file" "$dup_err" "$(basename "$f_d1")"
assert_contains "duplicate refusal names the override" "$dup_err" "--force"
mv "$f_d1" "$TASKS_DIR/archive/"
t render >/dev/null
dup_err="$(t new --id DUP-1 --name "Duplicate Guard Third" 2>&1 >/dev/null || true)"
refuse "new refuses a duplicate task ID in archive/" new --id DUP-1 --name "Duplicate Guard Third"
assert_contains "archive-side refusal carries the same override note" "$dup_err" "--force"
mv "$TASKS_DIR/archive/$(basename "$f_d1")" "$TASKS_DIR/current/"
t render >/dev/null
f_d2="$(t new --id DUP-1 --name "Duplicate Guard Second" --force)"
[[ -f "$f_d2" ]] && ok "--force admits a deliberate ID reuse" || bad "--force admits a deliberate ID reuse"
f_d3="$(t new --id DUP-11 --name "Near Miss ID")"
[[ -f "$f_d3" ]] && ok "a longer ID sharing a prefix is not a duplicate" || bad "a longer ID sharing a prefix is not a duplicate"
rm -f "$f_d1" "$f_d2" "$f_d3"
t render >/dev/null

echo "== new: --name must be a single line =="
# The name titles the level-1 heading and the dashboard row; a newline
# would inject bogus structure into both, so it is refused outright.
nl_before="$(ls "$TASKS_DIR/current" | wc -l)"
nl_err="$(t new --id NL-1 --name "$(printf 'two\nlines')" 2>&1 >/dev/null || true)"
refuse "new rejects a multi-line --name" new --id NL-1 --name "$(printf 'two\nlines')"
assert_contains "multi-line refusal states the single-line contract" "$nl_err" "--name must be a single line"
refuse "new rejects a CR-bearing --name" new --id NL-2 --name "$(printf 'cr\rname')"
assert_eq "rejected names create no file" "$nl_before" "$(ls "$TASKS_DIR/current" | wc -l)"

echo "== new: --status is restricted to Triage and Ready outside the test seam =="
# Creation admits only the two intake states: deeper states are lifecycle
# positions (set/claim/release/close), a directly created Blocked file
# would skip the reason coupling, and a directly created terminal file
# would carry no closure stamps. Probes run with the clock seam unset, in
# production conditions, via env -u like the CLI-owned-fields guard above;
# the battery's own fixtures (created under the exported TASKS_TEST_CLOCK)
# keep the full vocabulary through the seam.
nst_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-1 --name "IP Status Probe" --status "In Progress" 2>&1 >/dev/null || true)"
assert_contains "new refuses --status In Progress outside the seam" "$nst_err" "--status accepts only Triage or Ready"
assert_contains "the refusal names the lifecycle route" "$nst_err" "set/claim/release/close"
nst_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-2 --name "Blocked Status Probe" --status Blocked 2>&1 >/dev/null || true)"
assert_contains "new refuses --status Blocked outside the seam" "$nst_err" "--status accepts only Triage or Ready"
nst_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-3 --name "Cancelled Status Probe" --status Cancelled 2>&1 >/dev/null || true)"
assert_contains "new refuses --status Cancelled outside the seam" "$nst_err" "--status accepts only Triage or Ready"
nst_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-4 --name "Completed Status Probe" --status Completed 2>&1 >/dev/null || true)"
assert_contains "new refuses --status Completed outside the seam" "$nst_err" "--status accepts only Triage or Ready"
assert_eq "the refused creations left no files behind" "0" "$(ls "$TASKS_DIR/current" | grep -c '^NST-[1-4]-')"
if env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-1 --name "IP Status Probe" --status "In Progress" </dev/null >/dev/null 2>&1; then bad "new --status In Progress exits nonzero outside the seam"; else ok "new --status In Progress exits nonzero outside the seam"; fi
nst_f="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-5 --name "Ready Status Probe" --status Ready)"
assert_contains "new accepts --status Ready outside the seam" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$nst_f")" "Ready"
nst_t="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-6 --name "Triage Status Probe" --status Triage)"
assert_contains "new accepts --status Triage outside the seam" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$nst_t")" "Triage"
nst_d="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" new --id NST-7 --name "Default Status Probe")"
assert_contains "the default status stays Triage outside the seam" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$nst_d")" "Triage"
nst_s="$(t new --id NST-8 --name "Seam Status Probe" --status "In Progress")"
assert_contains "the seam admits deeper states for fixtures" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$nst_s")" "In Progress"
rm -f "$nst_f" "$nst_t" "$nst_d" "$nst_s"
t render >/dev/null

echo "== set: Owner is claim-owned =="
# Ownership never moves through set: the Owner field is written by claim
# (atomically, alongside its O_EXCL sidecar) and cleared by release. The
# refusal is unconditional - it does not open under the battery's clock
# seam, which exists for timeline backdating, not ownership.
f_own="$(t new --id OWN-1 --name "Owner Guard Target")"
own_before="$(cat "$f_own")"
own_err="$(t set "$f_own" Owner=ghost-session 2>&1 >/dev/null || true)"
refuse "set refuses an Owner write" set "$f_own" Owner=ghost-session
assert_contains "Owner refusal names the claim path" "$own_err" "'tasks claim' and 'tasks release'"
own_err="$(t set "$f_own" Owner= 2>&1 >/dev/null || true)"
refuse "set refuses Owner deletion too" set "$f_own" Owner=
assert_contains "Owner deletion refusal names the claim path too" "$own_err" "claim-owned"
assert_eq "Owner refusals leave the file byte-identical" "$own_before" "$(cat "$f_own")"
if t claim "$f_own" --owner claim-owner >/dev/null 2>&1; then ok "claim stays the ownership write path"; else bad "claim stays the ownership write path"; fi
assert_contains "claim sets Owner" "$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_own")" "claim-owner"
t release "$f_own" >/dev/null
rm -f "$f_own"
t render >/dev/null

echo "== terminal status transitions release a live claim =="
# Mirroring close: a terminal task owns nothing. A Cancelled transition
# through set is the one terminal write that would otherwise leave the
# sidecar behind (Completed goes through close, and the seam-admitted
# Completed pair is pinned for the same guarantee).
f_t1="$(t new --id TRL-1 --name "Terminal Release Target")"
t claim "$f_t1" --owner sess-terminal >/dev/null
t set "$f_t1" Status=Cancelled "Status Reason=terminal probe" >/dev/null
[[ ! -f "$f_t1.claim" ]] && ok "set to Cancelled removes the claim sidecar" || bad "set to Cancelled removes the claim sidecar"
assert_eq "set to Cancelled leaves Owner present and empty" "1" "$(grep -c '^\*\*Owner:\*\*$' "$f_t1")"
assert_contains "set to Cancelled lands the status" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_t1")" "Cancelled"
f_t2="$(t new --id TRL-2 --name "Terminal Completed Target")"
t claim "$f_t2" --owner sess-completed >/dev/null
t set "$f_t2" Status=Completed >/dev/null
[[ ! -f "$f_t2.claim" ]] && ok "set to Completed removes the claim sidecar" || bad "set to Completed removes the claim sidecar"
assert_eq "set to Completed leaves Owner present and empty" "1" "$(grep -c '^\*\*Owner:\*\*$' "$f_t2")"
f_t3="$(t new --id TRL-3 --name "Stale Claim On Terminal")"
t set "$f_t3" Status=Cancelled "Status Reason=stale probe" >/dev/null
printf 'sess-stale\n' >"$f_t3.claim"
t set "$f_t3" Priority=High >/dev/null
[[ ! -f "$f_t3.claim" ]] && ok "a set on an already-terminal file releases its stale sidecar" || bad "a set on an already-terminal file releases its stale sidecar"
f_t4="$(t new --id TRL-4 --name "Open Set Claim Target")"
t claim "$f_t4" --owner sess-open >/dev/null
t set "$f_t4" Priority=High >/dev/null
[[ -f "$f_t4.claim" ]] && ok "an open-status set keeps the live claim" || bad "an open-status set keeps the live claim"
t release "$f_t4" >/dev/null
rm -f "$f_t1" "$f_t2" "$f_t3" "$f_t4"
t render >/dev/null

echo "== set: unknown header keys are rejected before any write =="
f_kv="$(t new --id SET-1 --name "Set Validation Target")"
kv_hdr() { awk '/^## /{exit} {print}' "$f_kv"; }
kv_before="$(cat "$f_kv")"
kv_err="$(t set "$f_kv" "StatusReason=blocked for probe" 2>&1 >/dev/null || true)"
assert_contains "set rejects the no-space Status Reason variant" "$kv_err" "unknown header key: StatusReason"
assert_contains "key refusal names the canonical fields" "$kv_err" "Status Reason"
refuse "set rejects an unknown key" set "$f_kv" Bogus=1
refuse "set rejects an empty key" set "$f_kv" "=value"
refuse "set validates every pair before writing" set "$f_kv" Priority=High Bogus=1
assert_not_contains "all-or-nothing refusal applies no valid pair" "$(kv_hdr)" "**Priority:** High"
assert_eq "rejected sets leave the file byte-identical" "$kv_before" "$(cat "$f_kv")"
assert_eq "rejected sets leave no temp file behind" "" \
	"$(ls "$TASKS_DIR/current" | grep -F "$(basename "$f_kv")." || true)"

echo "== set: empty value deletes the field; Status and Status Reason are coupled =="
t set "$f_kv" Status=Blocked "Status Reason=blocked for probe" >/dev/null
assert_contains "spaced Status Reason key writes the field" "$(kv_hdr)" "**Status Reason:** blocked for probe"
t set "$f_kv" Status=Ready "Status Reason=" >/dev/null
assert_not_contains "empty value deletes the stale reason" "$(kv_hdr)" "**Status Reason:**"
assert_not_contains "the no-space variant never appears" "$(kv_hdr)" "**StatusReason:**"
assert_contains "unblocking lands the status" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_kv")" "Ready"
t set "$f_kv" Status=Blocked "Status Reason=second block" >/dev/null
t set "$f_kv" Status=Ready >/dev/null
assert_not_contains "leaving Blocked without a reason pair drops it" "$(kv_hdr)" "**Status Reason:**"
kv_blocked_before="$(cat "$f_kv")"
refuse "Blocked without a Status Reason is rejected" set "$f_kv" Status=Blocked
assert_contains "Blocked refusal demands a reason" \
	"$(t set "$f_kv" Status=Blocked 2>&1 >/dev/null || true)" "Status Reason"
assert_eq "rejected Blocked transition leaves the file byte-identical" "$kv_blocked_before" "$(cat "$f_kv")"
t set "$f_kv" Status=Blocked "Status Reason=work stopped on dependency" >/dev/null
assert_contains "Blocked with a same-call reason lands both fields" "$(kv_hdr)" \
	"**Status Reason:** work stopped on dependency"
t set "$f_kv" Status=Blocked >/dev/null
assert_contains "re-Blocking with the reason already on file keeps it" "$(kv_hdr)" \
	"**Status Reason:** work stopped on dependency"
refuse "Blocked with an emptied reason pair is rejected" set "$f_kv" Status=Blocked "Status Reason="
kv_reason_before="$(cat "$f_kv")"
refuse "an explicit reason on a non-Blocked status is rejected" set "$f_kv" Status=Ready "Status Reason=still stuck"
assert_eq "reason-status mismatch refusal leaves the file byte-identical" "$kv_reason_before" "$(cat "$f_kv")"
t set "$f_kv" Status=Ready "Status Reason=" >/dev/null
assert_not_contains "explicit empty reason while unblocking deletes it" "$(kv_hdr)" "**Status Reason:**"
t set "$f_kv" "Status Reason=" >/dev/null
assert_not_contains "deleting an absent reason field stays absent" "$(kv_hdr)" "**Status Reason:**"
assert_not_contains "deleting an absent reason inserts no empty duplicate" "$(kv_hdr)" "**StatusReason:**"
assert_eq "deleting an absent field leaves one Updated line" "1" \
	"$(grep -c '^\*\*Updated:\*\*' "$f_kv")"
t set "$f_kv" Updated="2020-01-01 00:00" >/dev/null
t set "$f_kv" Updated= >/dev/null
kv_updated="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_kv")"
[[ "$kv_updated" == "$(clock_today)"* ]] \
	&& ok "an emptied Updated= pair refreshes instead of deleting" \
	|| bad "an emptied Updated= pair refreshes instead of deleting (got [$kv_updated])"

echo "== set: re-inserted template fields land at their canonical slot =="
# A field deleted with Key= must re-insert at its template position (the
# new-task scaffold's order), never at end of header; the dashboard parser
# and humans both key on that order.
f_pos="$(t new --id POS-1 --name "Canonical Insert Target")"
t set "$f_pos" "Checkpoint Gating=none" >/dev/null
pos_order() {
	awk '/^## /{exit} {if (match($0, /^\*\*[^*:]+:\*\*/)) print substr($0, RSTART+2, RLENGTH-5)}' "$f_pos"
}
POS_CANONICAL_ORDER="$(printf '%s\n' Created Status Priority Progress Owner "Checkpoint Gating" Updated "Latest Update")"
# Ownership refuses set (claim-owned), so the deletion/re-insert legs of
# this ordering pin drive the internal writer seam directly, the same
# sanctioned sourcing pattern the set_header_field section below uses:
# the subject is write_header_fields slot behavior, not the ownership
# protocol, and claim/release legs of the pin follow unchanged.
owner_seam() { # value; set or clear the fixture's Owner through the sourced writer seam
	local value="$1"
	(
		set -euo pipefail
		source "$TASKS_BIN" help >/dev/null 2>&1
		set_header_field "$f_pos" "Owner" "$value"
	)
}
owner_seam ""
assert_not_contains "Owner deletion removes the field" "$(awk '/^## /{exit}{print}' "$f_pos")" "**Owner:**"
owner_seam "worker-pos"
assert_eq "re-set Owner lands in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
owner_seam ""
t claim "$f_pos" --owner claim-pos >/dev/null
assert_eq "claimed Owner lands in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
t release "$f_pos" >/dev/null
assert_eq "release keeps Owner in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
owner_seam ""
t release "$f_pos" >/dev/null
assert_eq "blank-path Owner insert lands in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
assert_eq "blank-path Owner insert writes the bare field" "1" "$(grep -c '^\*\*Owner:\*\*$' "$f_pos")"
t set "$f_pos" "Latest Update=" >/dev/null
t set "$f_pos" "Latest Update=restored" >/dev/null
assert_eq "re-set Latest Update falls back to end of header" "$POS_CANONICAL_ORDER" "$(pos_order)"
rm -f "$f_pos"
t render >/dev/null

echo "== set: backslash values survive verbatim =="
f_bs="$(t new --id BS-1 --name "Backslash Target")"
# Checkpoint Gating and Duration are the free-form carriers here (the
# subject is backslash survival through the header writer, not the field
# semantics; Duration admits fixture values under the battery's clock seam).
t set "$f_bs" 'Checkpoint Gating=c\\d' 'Duration=e\tf' >/dev/null
assert_contains "double backslash in a set value survives verbatim" \
	"$(grep -m1 '^\*\*Checkpoint Gating:' "$f_bs")" 'Checkpoint Gating:** c\\d'
assert_contains "backslash-t in a set value survives verbatim" \
	"$(grep -m1 '^\*\*Duration:' "$f_bs")" 'Duration:** e\tf'
rm -f "$f_bs"
t render >/dev/null

echo "== malformed header resilience =="
malformed="$TASKS_DIR/current/20240101-1100-malformed-header.md"
cat >"$malformed" <<'EOF'
# Task: Malformed Header

**Status:**Weird No Space
**Priority:**Medium
**Updated:** 2024-01-01 11:00

## Objective
EOF
if t render >/dev/null 2>&1; then ok "render survives a malformed header"; else bad "render survives a malformed header"; fi
assert_contains "malformed status falls back to the Triage lane" \
	"$(awk '/^## Triage/{f=1} /^## Ready/{f=0} f' <"$DASH")" "Malformed Header"
mal_row="$(grep -F 'Malformed Header' "$DASH")"
assert_contains "malformed priority falls back to the default" "$mal_row" "| Medium |"
rm -f "$malformed"
t render >/dev/null

echo "== pipes and brackets in names/values render escaped =="
f_pipe="$(t new --id API-6 --name "Piped | Name ](evil")"
pipe_row="$(grep -F 'Piped' "$DASH")"
assert_contains "pipe and brackets in name are escaped" "$pipe_row" 'Piped \| Name \](evil'
assert_not_contains "raw pipe does not split the name cell" "$pipe_row" "Piped | Name"
if t set "$f_pipe" Status=Completed Completed="2026-06-15 12:00" 'Duration=1h | 2m' >/dev/null 2>&1; then ok "set accepts a pipe-bearing value"; else bad "set accepts a pipe-bearing value"; fi
t render >/dev/null
pipe_row="$(grep -F 'Piped' "$DASH")"
assert_contains "pipe in field value is escaped" "$pipe_row" '1h \| 2m'
assert_not_contains "field pipe does not add a column" "$pipe_row" "1h | 2m"
# Repeated renders must stay byte-identical even with escaped content present
esc_before="$(cat "$DASH")"
t render >/dev/null
esc_after="$(cat "$DASH")"
assert_eq "render is byte-identical with escaped content on the board" "$esc_before" "$esc_after"
rm -f "$f_pipe"
t render >/dev/null

echo "== backslash names and numeric slugs keep task ID parity =="
f_bs="$(t new --id API-7 --name "Back\\slash Name")"
printf '%s\n' \
	"# Task: Twelve Factor" \
	"" \
	"**Created:** 2020-05-01 12:00" \
	"**Status:** Ready" \
	"**Priority:** Low" \
	"**Updated:** 2020-05-02 13:00" \
	"" \
	"## Work Log" \
	> "$TASKS_DIR/current/NSF-5-20260101-1200-12-factor.md"
printf '%s\n' \
	"# Task: Three Body" \
	"" \
	"**Created:** 2019-04-01 09:00" \
	"**Status:** Ready" \
	"**Priority:** Low" \
	"**Updated:** 2019-04-02 09:00" \
	"" \
	"## Work Log" \
	> "$TASKS_DIR/current/NSF-5-20190101-0100-3-body.md"
t render >/dev/null
bs_row="$(grep -F 'API-7' "$DASH")"
assert_contains "backslash in name is doubled in the cell" "$bs_row" 'Back\\slash Name'
assert_not_contains "single backslash does not survive in the cell" "$bs_row" "Back\slash Name"
nsf_rows="$(grep -F 'NSF-5: ' "$DASH" | cut -d'|' -f2)"
assert_contains "numeric-inner slug keeps its ID prefix" "$nsf_rows" "NSF-5: Twelve Factor"
assert_eq "numeric slugs sort chronologically in their lane" \
	"$(printf '%s\n' "$nsf_rows" | head -1)" \
	"$(printf '%s\n' "$nsf_rows" | grep -F 'Three Body')"
rm -f "$f_bs" "$TASKS_DIR/current/NSF-5-20260101-1200-12-factor.md" "$TASKS_DIR/current/NSF-5-20190101-0100-3-body.md"
t render >/dev/null

echo "== task ID extraction: bash mirror and assembler taskid() agree =="
# Differential over adversarial basenames (numeric-only slugs, stamp
# forms with and without slugs, recreated stamps, segment-less names):
# one side runs the real bash mirror (task_id_of_basename, sourced from
# the script), the other the real assembler (render over fixture files,
# ID read back from the dashboard row's label). A disagreement would let
# a child declared by ID miss the very file the dashboard shows.
source <(awk '/^task_id_of_basename\(\)/{f=1} f{print} f&&/^\}$/{exit}' "$TASKS_BIN")
tid_names=("NUM-1.md" "NUM-2-20260101-1200.md" "NUM-3-20260101-1200-9-lives.md" \
	"NUM-4-20260101-1200-12.md" "NUM-5-20260101-1200-20260102-1300.md" \
	"NUM-6-20260101-1200-20260102-1300-again.md" "NUM-7-12.md" "NUM-8-2026.md" \
	"NUM-9-20260101-1200-lives.md" "9.md")
for fb in "${tid_names[@]}"; do
	printf '%s\n' "# Task: Tid Probe ${fb%.md}" "" "**Status:** Ready" "" "## Objective" \
		>"$TASKS_DIR/current/$fb"
done
t render >/dev/null
for fb in "${tid_names[@]}"; do
	tid_expected="$(task_id_of_basename "$fb")"
	tid_row="$(grep -F "(./current/$fb)" "$DASH")"
	tid_label="${tid_row#*| \[}"
	tid_label="${tid_label%%]*}"
	if [[ "$tid_label" == *": "* ]]; then tid_actual="${tid_label%%: *}"; else tid_actual=""; fi
	assert_eq "taskid extraction agrees on $fb" "$tid_expected" "$tid_actual"
done
rm -f "$TASKS_DIR/current/"NUM-*.md "$TASKS_DIR/current/9.md"
t render >/dev/null

echo "== claim/release with a stale sidecar =="
printf '%s\n' "stale-session" >"$f_cs.claim"
refuse "claim under a stale sidecar is rejected" claim "$f_cs" --owner newcomer
claim_err="$(t claim "$f_cs" --owner newcomer 2>&1 >/dev/null || true)"
assert_contains "rejection names the stale owner" "$claim_err" "stale-session"
t release "$f_cs" >/dev/null
[[ ! -f "$f_cs.claim" ]] && ok "release removes the stale sidecar" || bad "release removes the stale sidecar"
owner_now="$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_cs" || true)"
assert_eq "release clears Owner even for a stale claim" "" "${owner_now:-}"
	# With no sidecar present, a claim failure must be reported as a create
	# failure, not conflated with "already claimed". Root is immune to mode
	# bits, so under root the chmod cannot provoke the failure and the
	# assertions are skipped rather than run as happy-path no-ops.
	if ((EUID == 0)); then
		skip_test "permission failure is reported as a create failure (skipped under root)"
		skip_test "permission failure is not misreported as claimed (skipped under root)"
	else
		perm_dir="$TASKS_DIR/current"
		perm_mode="$(stat -c %a "$perm_dir")"
		chmod 500 "$perm_dir"
		perm_err="$(t claim "$f_cs" --owner someone 2>&1 >/dev/null || true)"
		chmod "$perm_mode" "$perm_dir"
		assert_contains "permission failure is reported as a create failure" "$perm_err" "cannot create"
		assert_not_contains "permission failure is not misreported as claimed" "$perm_err" "already claimed"
	fi
if t claim "$f_cs" --owner newcomer >/dev/null 2>&1; then ok "claim succeeds after stale release"; else bad "claim succeeds after stale release"; fi
t release "$f_cs" >/dev/null

echo "== render stays byte-identical across repeated runs =="
before="$(cat "$DASH")"
t render >/dev/null
mid="$(cat "$DASH")"
t render >/dev/null
after="$(cat "$DASH")"
assert_eq "repeated renders are byte-identical" "$before" "$after"
assert_eq "render output is stable between runs" "$mid" "$after"

echo "== render: one awk pass per file, zero grep spawns =="
spawn_dir="$ROOT/spawn-board"
t init --dir "$spawn_dir" >/dev/null
t new --dir "$spawn_dir" --id SPW-1 --name "Spawn Count Ready" --status Ready >/dev/null
t new --dir "$spawn_dir" --id SPW-2 --name "Spawn Count Wip" --status "In Progress" --priority High >/dev/null
t new --dir "$spawn_dir" --id SPW-3 --name "Spawn Count Done" --status Completed >/dev/null
printf '%s\n' \
	"# Task: Spawn Count Legacy" \
	"" \
	"*Created: 2020-06-01 09:00*" \
	"" \
	"## Work Log" \
	> "$spawn_dir/current/SPW-4-20200601-0900-spawn-count-legacy.md"
shim_dir="$ROOT/spawn-shim"
spawn_counts="$ROOT/spawn-counts"
mkdir -p "$shim_dir" "$spawn_counts"
write_spawn_shim() { # tool real_bin count_file; wrapper counts one invocation, then execs the real binary
	cat >"$shim_dir/$1" <<EOF
#!/bin/sh
printf x >>'$3'
exec '$2' "\$@"
EOF
	chmod +x "$shim_dir/$1"
}
write_spawn_shim awk "$(command -v awk)" "$spawn_counts/awk"
write_spawn_shim grep "$(command -v grep)" "$spawn_counts/grep"
count_spawns() { # count_file; shim invocation counter, zero when the tool never ran
	local count_file="$1"
	if [[ -f "$count_file" ]]; then wc -c <"$count_file"; else printf 0; fi
}
t render --dir "$spawn_dir" >/dev/null
unshimmed_board="$(cat "$spawn_dir/dashboard.md")"
PATH="$shim_dir:$PATH" "$TASKS_BIN" render --dir "$spawn_dir" >/dev/null
awk_spawns="$(count_spawns "$spawn_counts/awk")"
grep_spawns="$(count_spawns "$spawn_counts/grep")"
spawn_files=4
assert_eq "render spawns zero greps" "0" "$grep_spawns"
if ((awk_spawns <= spawn_files)); then
	ok "render spawns at most one awk per task file ($awk_spawns awk for $spawn_files files)"
else
	bad "render spawns at most one awk per task file ($awk_spawns awk for $spawn_files files)"
fi
assert_eq "shimmed render output equals the unshimmed render" "$unshimmed_board" "$(cat "$spawn_dir/dashboard.md")"

echo "== render: dash-leading relative --dir is guarded =="
dash_dir="$ROOT/-board"
t init --dir "$dash_dir" >/dev/null
t new --dir "$dash_dir" --id DSH-1 --name "Dash Leading Board" >/dev/null
if (cd "$ROOT" && t render --dir "-board" >/dev/null); then
	ok "render succeeds on a dash-leading relative dir"
else
	bad "render succeeds on a dash-leading relative dir"
fi
[[ -f "$dash_dir/dashboard.md" ]] && ok "dash-leading board renders its dashboard" \
	|| bad "dash-leading board renders its dashboard"
if compgen -G "$dash_dir/dashboard.md.*" >/dev/null; then
	bad "dash-leading render leaves no dashboard temp behind"
else
	ok "dash-leading render leaves no dashboard temp behind"
fi
tilde_dir="$ROOT/~board"
t init --dir "$tilde_dir" >/dev/null
t new --dir "$tilde_dir" --id TLB-1 --name "Tilde Board" >/dev/null
if (cd "$ROOT" && t render --dir "~board" >/dev/null); then
	ok "render succeeds on a tilde-leading relative dir"
else
	bad "render succeeds on a tilde-leading relative dir"
fi
if compgen -G "$tilde_dir/dashboard.md.*" >/dev/null; then
	bad "tilde-leading render leaves no dashboard temp behind"
else
	ok "tilde-leading render leaves no dashboard temp behind"
fi

echo "== render: mid-render failure leaves no temp residue =="
fail_dir="$ROOT/fail-board"
t init --dir "$fail_dir" >/dev/null
t new --dir "$fail_dir" --id FRL-1 --name "Failure Residue" --status Ready >/dev/null
t render --dir "$fail_dir" >/dev/null
board_before="$(cat "$fail_dir/dashboard.md")"
fail_shim="$ROOT/fail-shim"
mkdir -p "$fail_shim"
printf '#!/bin/sh\nexit 1\n' >"$fail_shim/sort"
chmod +x "$fail_shim/sort"
if PATH="$fail_shim:$PATH" "$TASKS_BIN" render --dir "$fail_dir" >/dev/null 2>&1; then
	bad "render fails when sort fails"
else
	ok "render fails when sort fails"
fi
if compgen -G "$fail_dir/dashboard.md.*" >/dev/null; then
	bad "failed render leaves no dashboard temp residue"
else
	ok "failed render leaves no dashboard temp residue"
fi
assert_eq "failed render leaves the board file untouched" "$board_before" "$(cat "$fail_dir/dashboard.md")"

echo "== multi-key header writes commit in one pass =="
mk_dir="$ROOT/mk-board"
t init --dir "$mk_dir" >/dev/null
t new --dir "$mk_dir" --id MKW-1 --name "Multi Key Target" --status Ready >/dev/null
mkfile="$(ls "$mk_dir/current" | grep MKW-1)"
mk_shim="$ROOT/mk-shim"
mk_counts="$ROOT/mk-counts"
mkdir -p "$mk_shim" "$mk_counts"
# write_spawn_shim writes into the spawn section's shim_dir global; point
# it at this section's shim directory before reusing it.
shim_dir="$mk_shim"
write_spawn_shim awk "$(command -v awk)" "$mk_counts/awk"
count_reset() { rm -f "$mk_counts/awk"; }
count_awks() { count_spawns "$mk_counts/awk"; }
# Composition per command: set = one whole-file header rewrite awk + one
# render assembler awk (the Status/Reason prelookups read the header in
# pure bash, spawning nothing); claim and release = one rewrite awk + one
# render assembler awk. At N+1 per-key passes these counts are strictly
# higher, so the exact totals pin the single-pass writer.
PATH="$mk_shim:$PATH" "$TASKS_BIN" set --dir "$mk_dir" "$mkfile" \
	"Status=In Progress" Priority=High Progress=25% >/dev/null
assert_eq "multi-pair set runs one rewrite awk" "2" "$(count_awks)"
count_reset
PATH="$mk_shim:$PATH" "$TASKS_BIN" claim --dir "$mk_dir" "$mkfile" --owner alice >/dev/null
assert_eq "claim runs one rewrite awk" "2" "$(count_awks)"
count_reset
PATH="$mk_shim:$PATH" "$TASKS_BIN" release --dir "$mk_dir" "$mkfile" >/dev/null
assert_eq "release runs one rewrite awk" "2" "$(count_awks)"
# Simultaneously-missing keys must land in canonical template order at
# their shared insertion anchor, exactly as the old sequential per-key
# passes did (Completed precedes Duration in TEMPLATE_HEADER_FIELDS).
t set --dir "$mk_dir" "$mkfile" "Duration=1h" "Completed=2026-09-21 10:00" >/dev/null
mk_fields="$(grep -oP '^\*\*(?:Completed|Duration):' "$mk_dir/current/$mkfile" | tr -d '*:')"
assert_eq "simultaneously-missing keys insert in canonical order" \
	"$(printf 'Completed\nDuration')" "$mk_fields"

echo "== set_header_field deletes on an empty value (internal seam) =="
sf_dir="$ROOT/seam-board"
t init --dir "$sf_dir" >/dev/null
t new --dir "$sf_dir" --id SFH-1 --name "Seam Fix Probe" --status Ready >/dev/null
sfname="$(ls "$sf_dir/current" | grep SFH-1)"
sffile="$sf_dir/current/$sfname"
grep -q '^\*\*Progress:\*\*' "$sffile" && ok "probe file carries the Progress field" \
	|| bad "probe file carries the Progress field"
(
	# Sourcing the script runs main with the given arguments; help is the
	# harmless no-op that leaves every function defined in this subshell,
	# including the internal writer seam no CLI path drives with an empty
	# value (cmd_edit's refresh always passes $(now)).
	set -euo pipefail
	source "$TASKS_BIN" help >/dev/null 2>&1
	set_header_field "$sffile" "Progress" ""
)
if grep -q '^\*\*Progress:\*\*' "$sffile"; then
	bad "empty-value set_header_field removes the field line"
else
	ok "empty-value set_header_field removes the field line"
fi
rm -rf "$sf_dir"

echo "== report: deposit path, numbering, Work Log entry =="
f_rp="$(t new --id RPT-1 --name "Report Deposit Target")"
rpbase="$(basename "$f_rp")"
rpdir="$TASKS_DIR/reports/$rpbase"
t set "$f_rp" Updated="2020-01-01 00:00" >/dev/null
contentfile="$ROOT/report-content.md"
cat >"$contentfile" <<'EOF'
## Findings

- Recon found the CLI patterns

## Decisions

- None needed

## Blocks

- None

## Next

- Implement
EOF
rep1="$(t report "$f_rp" --slug recon --from Worker-A --digest "Recon findings recorded" "$contentfile")"
assert_eq "report prints the deposit path" "$TASKS_DIR/reports/$rpbase/01-recon.md" "$rep1"
[[ -f "$rep1" ]] && ok "report deposits the file at the spec path" || bad "report deposits the file at the spec path"
assert_contains "report content is deposited verbatim" "$(cat "$rep1")" "Recon found the CLI patterns"
entry_line="$(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Worker-A: Report$' "$f_rp" || true)"
[[ -n "$entry_line" ]] && ok "report appends the pinned entry heading" || bad "report appends the pinned entry heading"
assert_contains "entry links the deposit via ../reports/" "$(cat "$f_rp")" \
	"**Report:** [01-recon.md](../reports/$rpbase/01-recon.md)"
assert_contains "entry carries the digest" "$(cat "$f_rp")" "**Digest:** Recon findings recorded"
rp_updated="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_rp")"
[[ "$rp_updated" == "$(clock_today)"* ]] \
	&& ok "report bumps Updated to today" || bad "report bumps Updated to today (got [$rp_updated])"
latest_line="$(grep -oP '^\*\*Latest Update:\*\*\s+\K.*' "$f_rp")"
assert_contains "Latest Update carries the digest" "$latest_line" "Recon findings recorded"
assert_contains "Latest Update links the report" "$latest_line" "([report](../reports/$rpbase/01-recon.md))"
assert_contains "dashboard reflects the report bump" "$(grep -F 'Report Deposit Target' "$DASH")" "$rp_updated"

echo "== report: stdin modes and sequence numbering =="
printf 'Second report body\n' | t report "$f_rp" --slug next-steps --digest "Second deposit" >/dev/null
[[ -f "$rpdir/02-next-steps.md" ]] && ok "piped stdin report lands as 02" || bad "piped stdin report lands as 02"
assert_eq "second deposit content is verbatim" "Second report body" "$(cat "$rpdir/02-next-steps.md")"
printf 'Dash body\n' | t report "$f_rp" --slug dash-input --digest "Dash input" - >/dev/null
[[ -f "$rpdir/03-dash-input.md" ]] && ok "explicit - reads stdin" || bad "explicit - reads stdin"
printf 'seeded gap marker\n' >"$rpdir/04-gap.md"
printf 'Gap body\n' | t report "$f_rp" --slug gap-check --digest "Gap check" >/dev/null
[[ -f "$rpdir/05-gap-check.md" ]] \
	&& ok "sequence is max NN + 1 across gaps (05 after seeded 04)" \
	|| bad "sequence is max NN + 1 across gaps (05 after seeded 04)"

echo "== report: validation refusals leave no trace =="
rp_entries_before="$(grep -c -E '^### .*: Report$' "$f_rp" || true)"
rp_updated_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_rp")"
refuse "report rejects a non-kebab slug" report "$f_rp" --slug "Bad Slug" --digest d
refuse "report rejects a traversal slug" report "$f_rp" --slug "../escape" --digest d
refuse "report rejects an empty slug" report "$f_rp" --slug "" --digest d
refuse "report rejects a trailing-hyphen slug" report "$f_rp" --slug "trailing-" --digest d
refuse "report rejects a missing slug" report "$f_rp" --digest d
refuse "report rejects a missing digest" report "$f_rp" --slug fine
refuse "report rejects a multi-line digest" report "$f_rp" --slug fine --digest "$(printf 'line1\nline2')"
refuse "report rejects an unknown option" report "$f_rp" --bogus x --slug fine --digest d
refuse "report rejects a missing task file" report NOPE-9.md --slug fine --digest d
refuse "report rejects a missing taskfile argument" report --slug fine --digest d
refuse "report rejects a valueless trailing --slug" report "$f_rp" --slug
refuse "report rejects a valueless trailing --digest" report "$f_rp" --digest
refuse "report rejects a valueless trailing --from" report "$f_rp" --from
refuse "report rejects a valueless trailing --dir" report "$f_rp" --dir
refuse "report rejects empty stdin content" report "$f_rp" --slug empty-case --digest "empty"
refuse "report rejects an unreadable content file" report "$f_rp" --slug unreadable --digest d "$ROOT/no-such-report.md"
slug_guard_err="$(t report "$f_rp" --slug --digest d </dev/null 2>&1 >/dev/null || true)"
assert_contains "report refuses a flag-shaped --slug value" "$slug_guard_err" "report: --slug requires a value"
from_guard_err="$(t report "$f_rp" --from --bogus --slug fine --digest d </dev/null 2>&1 >/dev/null || true)"
assert_contains "report refuses a flag-shaped --from value" "$from_guard_err" "report: --from requires a value"
digest_guard_err="$(t report "$f_rp" --digest --bogus --slug fine </dev/null 2>&1 >/dev/null || true)"
assert_contains "report refuses a flag-shaped --digest value" "$digest_guard_err" "report: --digest requires a value"
dir_guard_err="$(t report "$f_rp" --dir --bogus --slug fine --digest d </dev/null 2>&1 >/dev/null || true)"
assert_contains "report refuses a flag-shaped --dir value" "$dir_guard_err" "report: --dir requires a value"
assert_eq "refusals append no Work Log entry" "$rp_entries_before" "$(grep -c -E '^### .*: Report$' "$f_rp" || true)"
assert_eq "refusals leave Updated untouched" "$rp_updated_before" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_rp")"
assert_eq "refusals deposit no report files" "5" "$(ls "$rpdir" 2>/dev/null | wc -l)"

echo "== report: create failure is all-or-nothing =="
if ((EUID == 0)); then
	skip_test "failed deposit removes nothing and mutates nothing (skipped under root)"
	skip_test "failed deposit reports the create failure (skipped under root)"
else
	perm_mode="$(stat -c %a "$rpdir")"
	chmod 500 "$rpdir"
	perm_err="$(printf 'denied body\n' | t report "$f_rp" --slug denied --digest "should fail" 2>&1 >/dev/null || true)"
	chmod "$perm_mode" "$rpdir"
	assert_contains "failed deposit reports the create failure" "$perm_err" "cannot create"
	assert_eq "failed deposit leaves no report file" "" "$(ls "$rpdir" | grep -F denied || true)"
	assert_eq "failed deposit appends no Work Log entry" "$rp_entries_before" "$(grep -c -E '^### .*: Report$' "$f_rp" || true)"
	assert_eq "failed deposit leaves Updated untouched" "$rp_updated_before" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_rp")"
fi

echo "== report: whitespace-only --from re-defaults to Manager =="
mgr_reports_before="$(grep -cE '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Manager: Report$' "$f_rp" || true)"
printf 'Whitespace from body\n' | t report "$f_rp" --slug ws-from --from " " --digest "Whitespace from check" >/dev/null
mgr_reports_after="$(grep -cE '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Manager: Report$' "$f_rp" || true)"
assert_eq "report re-defaults a whitespace-only --from to Manager" "$((mgr_reports_before + 1))" "$mgr_reports_after"

echo "== report: links resolve from current/ and archive/ =="
f_res="$(t new --id RPT-2 --name "Link Resolution Target")"
resbase="$(basename "$f_res")"
printf 'resolution body\n' | t report "$f_res" --slug recon --from Worker-B --digest "resolution check" >/dev/null
[[ -f "$TASKS_DIR/current/../reports/$resbase/01-recon.md" ]] \
	&& ok "../reports/ link resolves from current/" || bad "../reports/ link resolves from current/"
assert_contains "task file carries the relative report link" "$(cat "$f_res")" \
	"(../reports/$resbase/01-recon.md)"
cp "$f_res" "$TASKS_DIR/archive/$resbase"
[[ -f "$TASKS_DIR/archive/../reports/$resbase/01-recon.md" ]] \
	&& ok "../reports/ link resolves from archive/" || bad "../reports/ link resolves from archive/"
printf 'archived body\n' | t report "$TASKS_DIR/archive/$resbase" --slug post-archive --digest "after archive" >/dev/null
[[ -f "$TASKS_DIR/reports/$resbase/02-post-archive.md" ]] \
	&& ok "reporting an archived task deposits under the same reports dir" \
	|| bad "reporting an archived task deposits under the same reports dir"
rm -f "$TASKS_DIR/archive/$resbase"

echo "== report: concurrent deposits serialize =="
f_cc="$(t new --id RPT-3 --name "Concurrent Report Target")"
ccbase="$(basename "$f_cc")"
ccdir="$(mktemp -d)"
for i in 1 2 3 4 5; do
	(
		printf 'report %s\n' "$i" | t report "$f_cc" --slug "worker-$i" --from "w-$i" --digest "report $i" \
			>"$ccdir/$i.out" 2>&1
		echo $? >"$ccdir/$i.code"
	) &
done
wait
cc_ok=0
for i in 1 2 3 4 5; do
	[[ "$(cat "$ccdir/$i.code")" == 0 ]] && cc_ok=$((cc_ok + 1))
done
assert_eq "all five concurrent reports succeed" "5" "$cc_ok"
# Which worker claims which number is scheduling-dependent; the guarantees
# are unique numbers 01..05 and all five slugs deposited exactly once.
cc_numbers="$(ls "$TASKS_DIR/reports/$ccbase" | grep -oE '^[0-9]+' | LC_ALL=C sort | tr '\n' ' ')"
assert_eq "concurrent deposits occupy 01..05 with no collision" "01 02 03 04 05 " "$cc_numbers"
cc_slugs="$(ls "$TASKS_DIR/reports/$ccbase" | sed -E 's/^[0-9]+-//; s/\.md$//' | LC_ALL=C sort | tr '\n' ' ')"
assert_eq "concurrent deposits carry all five slugs" "worker-1 worker-2 worker-3 worker-4 worker-5 " "$cc_slugs"
assert_eq "concurrent deposits append five Work Log entries" "5" \
	"$(grep -c -E '^### .*: Report$' "$f_cc" || true)"
assert_eq "concurrent deposits record all five digests" "5" \
	"$(grep -c -F '**Digest:** report ' "$f_cc" || true)"
rm -rf "$ccdir"

echo "== log: manager entry, Updated bump, render =="
f_lg="$(t new --id LOG-1 --name "Log Entry Target")"
t set "$f_lg" Updated="2020-01-01 00:00" >/dev/null
lg_latest_before="$(grep -oP '^\*\*Latest Update:\*\*\s+\K.*' "$f_lg")"
t log "$f_lg" "Dispatches held pending decision" >/dev/null
lg_entry="$(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Manager: Dispatches held pending decision$' "$f_lg" || true)"
[[ -n "$lg_entry" ]] && ok "log appends the timestamped manager heading" || bad "log appends the timestamped manager heading"
lg_updated="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lg")"
[[ "$lg_updated" == "$(clock_today)"* ]] \
	&& ok "log bumps Updated to today" || bad "log bumps Updated to today (got [$lg_updated])"
assert_eq "successful log leaves exactly one Updated line on a headed file" "1" \
	"$(grep -c '^\*\*Updated:\*\*' "$f_lg")"
assert_eq "log leaves Latest Update untouched" "$lg_latest_before" \
	"$(grep -oP '^\*\*Latest Update:\*\*\s+\K.*' "$f_lg")"
assert_contains "dashboard reflects the log bump" "$(grep -F 'Log Entry Target' "$DASH")" "$lg_updated"
lg_order="$(awk '/^## Work Log/{w=NR} /Manager: Dispatches held pending decision/{e=NR} /^## Execution Log/{x=NR} END{print (w<e && e<x) ? "ok" : "bad"}' "$f_lg")"
assert_eq "log entry lands at the end of the Work Log section" "ok" "$lg_order"
t log "$f_lg" "$(printf 'Multi heading line\nbody detail here')" >/dev/null
assert_contains "multiline log headings the first line" "$(cat "$f_lg")" "Manager: Multi heading line"
assert_contains "multiline log keeps the remaining body" \
	"$(grep -A2 'Manager: Multi heading line' "$f_lg")" "body detail here"

echo "== log: validation refusals =="
lg_updated_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lg")"
refuse "log rejects an empty message" log "$f_lg" ""
refuse "log rejects a missing message" log "$f_lg"
refuse "log rejects extra arguments" log "$f_lg" "one" "two"
refuse "log rejects a missing task file" log NOPE-9.md "msg"
assert_eq "rejected logs leave Updated untouched" "$lg_updated_before" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lg")"

echo "== log: --from attribution =="
f_lf="$(t new --id LOG-2 --name "Log From Target")"
t set "$f_lf" Updated="2020-01-01 00:00" >/dev/null
t log "$f_lf" --from Worker-C "Checkpoint reached, suite green" >/dev/null
lf_entry="$(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Worker-C: Checkpoint reached, suite green$' "$f_lf" || true)"
[[ -n "$lf_entry" ]] && ok "log --from headings the worker name" || bad "log --from headings the worker name"
t log "$f_lf" --from "" "Empty from falls back to Manager" >/dev/null
ef_entry="$(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Manager: Empty from falls back to Manager$' "$f_lf" || true)"
[[ -n "$ef_entry" ]] && ok "log re-defaults an empty --from to Manager" || bad "log re-defaults an empty --from to Manager"
t log "$f_lf" --from " " "Whitespace-only from falls back to Manager" >/dev/null
ws_entry="$(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Manager: Whitespace-only from falls back to Manager$' "$f_lf" || true)"
[[ -n "$ws_entry" ]] && ok "log re-defaults a whitespace-only --from to Manager" || bad "log re-defaults a whitespace-only --from to Manager"
# The Manager default stays covered by the log tests above (f_lg), which
# exercise the same re-default path without the flag.

echo "== log: heading-line and CR rejection =="
# The seven-hash line is not a markdown heading and is accepted (its entry
# lands first); the no-trace baseline is captured after it so the rejection
# assertions below prove the refused calls append nothing.
if t log "$f_lf" "$(printf 'text\n####### seven hashes is not a heading')" >/dev/null 2>&1; then ok "log accepts seven-hash lines (not markdown headings)"; else bad "log accepts seven-hash lines (not markdown headings)"; fi
lf_updated_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lf")"
lf_entries_before="$(grep -c '^### ' "$f_lf")"
head_err="$(t log "$f_lf" "$(printf 'fine first line\n## Injected Section')" 2>&1 >/dev/null || true)"
assert_contains "log rejects a body line beginning with a heading" "$head_err" "heading"
refuse "log rejects a heading first line" log "$f_lf" "## Heading first line"
cr_err="$(t log "$f_lf" "$(printf 'crlf first\rsecond line')" 2>&1 >/dev/null || true)"
assert_contains "log rejects CR characters in the message" "$cr_err" "carriage return"
refuse "log rejects a multi-line --from" log "$f_lf" --from "$(printf 'a\nb')" "msg"
refuse "log rejects a valueless trailing --from" log "$f_lf" --from
refuse "log rejects a valueless trailing --dir" log "$f_lf" --dir
assert_eq "rejected heading and CR logs leave Updated untouched" "$lf_updated_before" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lf")"
assert_eq "rejected heading and CR logs append no entry" "$lf_entries_before" \
	"$(grep -c '^### ' "$f_lf")"
from_flag_err="$(t log "$f_lf" --from --bogus "msg" 2>&1 >/dev/null || true)"
assert_contains "log refuses a flag-shaped --from value" "$from_flag_err" "log: --from requires a value"
logdir_flag_err="$(t log "$f_lf" --dir --bogus "msg" 2>&1 >/dev/null || true)"
assert_contains "log refuses a flag-shaped --dir value" "$logdir_flag_err" "log: --dir requires a value"

echo "== log: blank first line rejection =="
lf_blank_updated_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lf")"
lf_blank_entries_before="$(grep -c '^### ' "$f_lf")"
blank_err="$(t log "$f_lf" "$(printf '   \nbody under a blank first line')" 2>&1 >/dev/null || true)"
assert_contains "log rejects a whitespace-only first line" "$blank_err" "first line"
refuse "log rejects an empty first line" log "$f_lf" "$(printf '\nbody under an empty first line')"
refuse "log rejects a tab-only first line" log "$f_lf" "$(printf '\t\nbody under a tab-only first line')"
assert_eq "rejected blank-first-line logs leave Updated untouched" "$lf_blank_updated_before" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lf")"
assert_eq "rejected blank-first-line logs append no entry" "$lf_blank_entries_before" \
	"$(grep -c '^### ' "$f_lf")"

echo "== log: append failure is explicit and leaves no partial state =="
# Root is immune to mode bits, so the chmod cannot provoke the append's
# mktemp failure and the assertions are skipped rather than run as no-ops.
if ((EUID == 0)); then
	skip_test "log reports an append failure explicitly (skipped under root)"
	skip_test "a failed log append leaves the file untouched (skipped under root)"
else
	lg_fail_entries_before="$(grep -c '^### ' "$f_lg")"
	lg_fail_updated_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lg")"
	lg_perm_mode="$(stat -c %a "$TASKS_DIR/current")"
	chmod 500 "$TASKS_DIR/current"
	lg_fail_err="$(t log "$f_lg" "must never land" 2>&1 >/dev/null || true)"
	chmod "$lg_perm_mode" "$TASKS_DIR/current"
	assert_contains "log reports an append failure explicitly" "$lg_fail_err" "log: failed to update"
	assert_contains "append failure names the task file" "$lg_fail_err" "$(basename "$f_lg")"
	assert_eq "failed log append appends no entry" "$lg_fail_entries_before" "$(grep -c '^### ' "$f_lg")"
	assert_eq "failed log append leaves Updated untouched" "$lg_fail_updated_before" \
		"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_lg")"
	assert_eq "failed log append leaves no temp file behind" "" \
		"$(ls "$TASKS_DIR/current" | grep -F "$(basename "$f_lg")." || true)"
fi

echo "== log: headingless file still gets its Updated refresh =="
hless="$TASKS_DIR/current/20240101-1200-headingless-task.md"
cat >"$hless" <<'EOF'
# Task: Headingless Append Target

**Status:** Triage
EOF
t log "$hless" "Entry on a headingless file" >/dev/null
grep -q '^\*\*Updated:\*\*' "$hless" \
	&& ok "log refreshes Updated on a headingless file" || bad "log refreshes Updated on a headingless file"
assert_eq "headingless append writes exactly one Updated line" "1" \
	"$(grep -c '^\*\*Updated:\*\*' "$hless")"
hless_entry="$(grep -E '^### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: Manager: Entry on a headingless file$' "$hless" || true)"
[[ -n "$hless_entry" ]] && ok "headingless append still appends the entry" || bad "headingless append still appends the entry"
# With no "## " heading the header region never terminates, so an existing
# **Updated:** field must be swapped in place rather than joined by a second.
hless_predated="$TASKS_DIR/current/20240101-1230-headingless-predated.md"
cat >"$hless_predated" <<'EOF'
# Task: Headingless Predated Target

**Status:** Triage
**Updated:** 2024-01-01 12:00
EOF
t log "$hless_predated" "Entry on a predated headingless file" >/dev/null
assert_eq "headingless append replaces an existing Updated field in place" "1" \
	"$(grep -c '^\*\*Updated:\*\*' "$hless_predated")"
hless_predated_updated="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$hless_predated")"
[[ "$hless_predated_updated" == "$(clock_today)"* ]] \
	&& ok "headingless append bumps the predated Updated value" \
	|| bad "headingless append bumps the predated Updated value (got [$hless_predated_updated])"
rm -f "$hless_predated"
rm -f "$hless"
t render >/dev/null

echo "== edit: replace section body =="
f_ed="$(t new --id EDT-1 --name "Edit Section Target")"
t set "$f_ed" Updated="2020-01-01 00:00" >/dev/null
ed_body="$ROOT/edit-body.md"
cat >"$ed_body" <<'EOF'
New objective text from the edit channel.

Second line of the body.
EOF
t edit "$f_ed" --section Objective "$ed_body" >/dev/null
ed_region="$(awk '/^## Objective$/{f=1;next} /^## Success Criteria$/{f=0} f' "$f_ed")"
assert_eq "edit replaces the section body verbatim" \
	"$(printf '\nNew objective text from the edit channel.\n\nSecond line of the body.')" "$ed_region"
ed_next_region="$(awk '/^## Success Criteria$/{f=1;next} /^## Work Log$/{f=0} f' "$f_ed")"
assert_not_contains "edit leaves the following section untouched" "$ed_next_region" "New objective text"
printf 'Piped replacement body\n' | t edit "$f_ed" --section Objective >/dev/null
assert_contains "edit reads the body from piped stdin" "$(cat "$f_ed")" "Piped replacement body"
printf 'Dash stdin body\n' | t edit "$f_ed" --section Objective - >/dev/null
assert_contains "edit reads the body from explicit dash stdin" "$(cat "$f_ed")" "Dash stdin body"
printf 'Tail section body\n' | t edit "$f_ed" --section "Execution Log" >/dev/null
ed_tail="$(awk '/^## Execution Log$/{f=1} f' "$f_ed")"
assert_contains "replace reaches a section at end of file" "$ed_tail" "Tail section body"

echo "== edit: append under an existing section =="
f_ea="$(t new --id EDT-2 --name "Edit Append Target")"
t set "$f_ea" Updated="2020-01-01 00:00" >/dev/null
printf 'Appended tail line\n' | t edit "$f_ea" --section Objective --append >/dev/null
ea_region="$(awk '/^## Objective$/{f=1;next} /^## Success Criteria$/{f=0} f' "$f_ea")"
assert_eq "append keeps the existing body and adds the tail" \
	"$(printf '\n[EDT-2] Edit Append Target\n\nAppended tail line')" "$ea_region"
printf 'First appended line\n' | t edit "$f_ea" --section "Work Log" --append >/dev/null
ea_log="$(awk '/^## Work Log$/{f=1;next} /^## Execution Log$/{f=0} f' "$f_ea")"
assert_eq "append onto an empty section writes the body" \
	"$(printf '\nFirst appended line')" "$ea_log"
ea_snapshot="$(awk '/^## Objective$/{f=1;next} /^## Success Criteria$/{f=0} f' "$f_ea")"
if printf '' | t edit "$f_ea" --section Objective --append >/dev/null 2>&1; then
	ok "append with empty input succeeds as a no-op"
else
	bad "append with empty input succeeds as a no-op"
fi
assert_eq "empty append leaves the section body untouched" "$ea_snapshot" \
	"$(awk '/^## Objective$/{f=1;next} /^## Success Criteria$/{f=0} f' "$f_ea")"

echo "== edit: refusals leave the task file untouched =="
ed_before="$(cat "$f_ed")"
refuse "edit rejects an unknown section" edit "$f_ed" --section "No Such Section" "$ed_body"
refuse "edit rejects an empty replacement body (file)" edit "$f_ed" --section Objective /dev/null
refuse "edit rejects an empty replacement body (stdin)" edit "$f_ed" --section Objective
ed_bad="$ROOT/edit-heading-body.md"
printf 'leading text\n## Injected Section\ntrailing text\n' >"$ed_bad"
refuse "edit rejects a heading-shaped body line" edit "$f_ed" --section Objective "$ed_bad"
refuse "edit --append rejects a heading-shaped body line" edit "$f_ea" --section "Work Log" --append "$ed_bad"
refuse "edit rejects a missing --section" edit "$f_ed"
refuse "edit rejects a valueless trailing --section" edit "$f_ed" --section
refuse "edit rejects an unknown option" edit "$f_ed" --bogus x --section Objective "$ed_body"
refuse "edit rejects a missing task file" edit NOPE-9.md --section Objective "$ed_body"
refuse "edit rejects a missing body file" edit "$f_ed" --section Objective "$ROOT/no-such-body.md"
refuse "edit rejects extra arguments" edit "$f_ed" --section Objective "$ed_body" extra
ed_title="$(grep -m1 -oP '^# \K.*' "$f_ed")"
refuse "edit refuses the level-1 document title as a section" edit "$f_ed" --section "$ed_title" "$ed_body"
ea_updated_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_ea")"
refuse "empty append still rejects an unknown section" edit "$f_ea" --section "No Such Section" --append
assert_eq "edit refusals leave the file byte-identical" "$ed_before" "$(cat "$f_ed")"
title_err="$(edit_stderr_of "$f_ed" --section "$ed_title" "$ed_body")"
assert_contains "title refusal reports an unknown section" "$title_err" "unknown section"
assert_eq "refused empty append leaves Updated untouched" "$ea_updated_before" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_ea")"
ed_err="$(edit_stderr_of "$f_ed" --section "No Such Section" "$ed_body")"
assert_contains "unknown-section refusal names the section" "$ed_err" "unknown section"
ea_err="$(edit_stderr_of "$f_ea" --section "No Such Section" --append)"
assert_contains "empty-append refusal reports an unknown section" "$ea_err" "unknown section"
head_err="$(edit_stderr_of "$f_ed" --section Objective "$ed_bad")"
assert_contains "heading-line refusal names the hazard" "$head_err" "heading"
ed_dir_flag_err="$(edit_stderr_of --dir --bogus)"
assert_contains "edit refuses a flag-shaped --dir value" "$ed_dir_flag_err" "edit: --dir requires a value"
ed_sec_flag_err="$(edit_stderr_of "$f_ed" --section --bogus "$ed_body")"
assert_contains "edit refuses a flag-shaped --section value" "$ed_sec_flag_err" "edit: --section requires a value"
ed_dir_val_err="$(edit_stderr_of --dir)"
assert_contains "edit refuses a valueless trailing --dir" "$ed_dir_val_err" "edit: --dir requires a value"
ed_sec_val_err="$(edit_stderr_of "$f_ed" --section)"
assert_contains "edit refuses a valueless trailing --section" "$ed_sec_val_err" "edit: --section requires a value"
ed_updated_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_ed")"
refuse "edit refuses an empty stdin replacement without a trace" edit "$f_ed" --section Objective
assert_eq "refused edits leave Updated untouched" "$ed_updated_before" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_ed")"

echo "== edit: nested headings deeper than the section are accepted =="
# The skill's template nests "### Decision Log" inside "## Technical
# Approach" and "### Task PREFIX-N-N" entries inside "## Task Breakdown";
# only headings at or above the target section's own level are boundary
# injections and get refused. The template-shaped fixture carries the
# sections a fresh tasks-new scaffold does not (P1 covers creating those).
nested="$TASKS_DIR/current/20240101-1400-nested-headings.md"
cat >"$nested" <<'EOF'
# Task: Nested Heading Target

**Status:** Triage
**Updated:** 2024-01-01 14:00

## Objective

base objective

## Technical Approach

### Decision Log

**Decision: seed decision** - seed body

## Task Breakdown

## Work Log

## Execution Log

- 2024-01-01 14:00 - Task file created
EOF
printf 'Strategy line\n\n### Decision Log\n\n**Decision: template nesting works** - entry body\n' | t edit "$nested" --section "Technical Approach" >/dev/null
nested_ta="$(awk '/^## Technical Approach$/{f=1} /^## Task Breakdown$/{f=0} f' "$nested")"
assert_contains "edit accepts ### Decision Log inside ## Technical Approach" "$nested_ta" "### Decision Log"
assert_contains "nested decision body survives the write" "$nested_ta" "**Decision: template nesting works** - entry body"
printf '### Task EDT-4-1: Child Unit\n\n#### Acceptance Criteria\n\n- [ ] nested acceptance item\n' | t edit "$nested" --section "Task Breakdown" >/dev/null
nested_tb="$(awk '/^## Task Breakdown$/{f=1} /^## Work Log$/{f=0} f' "$nested")"
assert_contains "edit accepts ### Task entries inside ## Task Breakdown" "$nested_tb" "### Task EDT-4-1: Child Unit"
assert_contains "edit accepts #### headings inside a ### entry" "$nested_tb" "#### Acceptance Criteria"
printf 'deeper append\n#### Progress Log\n\n- checkpoint\n' | t edit "$nested" --section "Technical Approach" --append >/dev/null
nested_ap="$(awk '/^## Technical Approach$/{f=1} /^## Task Breakdown$/{f=0} f' "$nested")"
assert_contains "append accepts deeper headings too" "$nested_ap" "#### Progress Log"
assert_contains "append keeps the pre-existing nested content" "$nested_ap" "**Decision: template nesting works** - entry body"
# Hash runs longer than six are not markdown headings and stay acceptable
printf '####### seven hashes is not a heading\n' | t edit "$nested" --section "Objective" >/dev/null
assert_contains "seven-hash lines stay acceptable in edit bodies" "$(cat "$nested")" "####### seven hashes is not a heading"
nested_updated_after="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$nested")"
[[ "$nested_updated_after" == "$(clock_today)"* ]] \
	&& ok "nested-heading edits bump Updated" || bad "nested-heading edits bump Updated (got [$nested_updated_after])"

echo "== edit: same-or-higher-level headings stay refused =="
nested_before="$(cat "$nested")"
printf 'fine text\n## Injected Sibling\nmore text\n' >"$ROOT/edit-sibling-heading.md"
nested_sec_err="$(edit_stderr_of "$nested" --section "Technical Approach" "$ROOT/edit-sibling-heading.md")"
refuse "edit rejects a same-level heading inside a section" edit "$nested" --section "Technical Approach" "$ROOT/edit-sibling-heading.md"
assert_contains "same-level refusal names the hazard" "$nested_sec_err" "heading"
printf 'fine text\n# Forged Document Title\nmore text\n' >"$ROOT/edit-title-heading.md"
refuse "edit rejects a level-1 title line inside a section" edit "$nested" --section "Technical Approach" "$ROOT/edit-title-heading.md"
refuse "append rejects a same-level heading too" edit "$nested" --section "Technical Approach" --append "$ROOT/edit-sibling-heading.md"
deeptarget_err="$(printf '## Escape Attempt\n' | t edit "$nested" --section "Decision Log" 2>&1 >/dev/null || true)"
refuse "edit rejects a same-level heading inside a subsection" edit "$nested" --section "Decision Log" "$ROOT/edit-sibling-heading.md"
assert_contains "## inside a ### section is refused" "$deeptarget_err" "heading"
assert_eq "same-or-higher refusals leave the file byte-identical" "$nested_before" "$(cat "$nested")"
nested_upd_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$nested")"
refuse "refused nested edits leave no trace on Updated" edit "$nested" --section "Technical Approach" "$ROOT/edit-sibling-heading.md"
assert_eq "refused nested edits keep Updated untouched" "$nested_upd_before" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$nested")"
rm -f "$nested"
t render >/dev/null

echo "== edit: Work Log entry anchors are CLI-stamped (forgery stance: guarded) =="
# G9 stance: guarded. Entry anchors are the Duration-derivation input and
# the CLI's audit trail; Option-1's free-form principle covers prose, not
# CLI-shaped timeline data, so edit refuses anchor-shaped lines in Work
# Log bodies (append and replace alike) while every other section keeps
# taking them as ordinary deeper headings.
forge_anchor="$ROOT/forge-anchor.md"
printf '### 2026-01-01 00:00: Manager: forged entry\n' >"$forge_anchor"
f_forg="$(t new --id FRG-1 --name "Forgery Guard Target")"
forge_before="$(cat "$f_forg")"
forge_err="$(t edit "$f_forg" --section "Work Log" --append "$forge_anchor" 2>&1 >/dev/null || true)"
refuse "edit refuses an anchor line appended to Work Log" edit "$f_forg" --section "Work Log" --append "$forge_anchor"
assert_contains "anchor refusal names the CLI route" "$forge_err" "via 'tasks log'"
refuse "edit refuses an anchor line replacing Work Log" edit "$f_forg" --section "Work Log" "$forge_anchor"
assert_eq "refused anchor edits leave the file byte-identical" "$forge_before" "$(cat "$f_forg")"
printf 'status note for 2026-01-01 00:00 recorded here\n\n#### a deeper note heading\n' | t edit "$f_forg" --section "Work Log" --append >/dev/null
assert_contains "prose dates and deeper headings stay legal in Work Log" \
	"$(cat "$f_forg")" "status note for 2026-01-01 00:00 recorded here"
printf '### 2026-01-01 00:00: not an entry here\n' | t edit "$f_forg" --section "Objective" >/dev/null
assert_contains "anchor-shaped lines stay legal outside Work Log" \
	"$(cat "$f_forg")" "### 2026-01-01 00:00: not an entry here"
rm -f "$f_forg"
t render >/dev/null

echo "== edit: creates missing template sections at their canonical position =="
# The skill's planning pass needs Technical Approach, Risk Assessment,
# Testing Strategy, TDD Workflow, and Task Breakdown on a freshly created
# file; each must be creatable through edit at the template's slot, never
# requiring a hand edit. Creating them in reverse order forces every
# insertion to re-anchor, and the final layout must still be canonical.
f_cr="$(t new --id EDT-5 --name "Section Creation Target")"
t set "$f_cr" Updated="2020-01-01 00:00" >/dev/null
printf -- '- [ ] child criterion\n' | t edit "$f_cr" --section "Task Breakdown" >/dev/null
printf 'Red: repro tests first, then green\n' | t edit "$f_cr" --section "TDD Workflow" >/dev/null
printf 'Unit tests through tests/tasks/test-tasks.sh\n' | t edit "$f_cr" --section "Testing Strategy" >/dev/null
printf 'Risks: none beyond ordinary regression risk\n' | t edit "$f_cr" --section "Risk Assessment" >/dev/null
printf 'Strategy: reverse-order creation probe\n' | t edit "$f_cr" --section "Technical Approach" >/dev/null
cr_order_ok=1
cr_prev=0
for cr_sec in "Technical Approach" "Risk Assessment" "Testing Strategy" "TDD Workflow" "Task Breakdown" "Work Log"; do
	cr_line="$(grep -n "^## $cr_sec\$" "$f_cr" | cut -d: -f1)"
	if [[ -z "$cr_line" || "$cr_line" -le "$cr_prev" ]]; then cr_order_ok=0; break; fi
	cr_prev=$cr_line
done
[[ "$cr_order_ok" == 1 ]] \
	&& ok "template sections land in canonical order" || bad "template sections land in canonical order"
cr_sc_line="$(grep -n '^## Success Criteria$' "$f_cr" | cut -d: -f1)"
cr_ta_line="$(grep -n '^## Technical Approach$' "$f_cr" | cut -d: -f1)"
cr_wl_line="$(grep -n '^## Work Log$' "$f_cr" | cut -d: -f1)"
[[ "$cr_sc_line" -lt "$cr_ta_line" && "$cr_ta_line" -lt "$cr_wl_line" ]] \
	&& ok "created Technical Approach sits after Success Criteria and before Work Log" \
	|| bad "created Technical Approach sits after Success Criteria and before Work Log"
assert_contains "created section carries the supplied body" "$(cat "$f_cr")" "Risks: none beyond ordinary regression risk"
cr_updated="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_cr")"
[[ "$cr_updated" == "$(clock_today)"* ]] \
	&& ok "section creation bumps Updated" || bad "section creation bumps Updated (got [$cr_updated])"
assert_contains "dashboard reflects the creation bump" "$(grep -F 'Section Creation Target' "$DASH")" "$cr_updated"
# Append onto a just-created section appends, not replaces
printf 'appended planning line\n' | t edit "$f_cr" --section "Risk Assessment" --append >/dev/null
cr_ra="$(awk '/^## Risk Assessment$/{f=1} /^## Testing Strategy$/{f=0} f' "$f_cr")"
assert_contains "append works on a created section" "$cr_ra" "appended planning line"
assert_contains "append keeps the created body" "$cr_ra" "Risks: none beyond ordinary regression risk"
# Creation accepts nested headings per the level rule
printf '### Decision Log\n\n**Decision: nested on creation** - body\n' | t edit "$f_cr" --section "Task Breakdown" --append >/dev/null
assert_contains "creation accepts nested headings per the level rule" "$(cat "$f_cr")" "**Decision: nested on creation** - body"
# Unknown-to-template headings still refuse
cr_before="$(cat "$f_cr")"
cr_unknown_err="$(edit_stderr_of "$f_cr" --section "Made Up Section" "$ROOT/edit-body.md")"
refuse "edit still refuses an unknown-to-template section" edit "$f_cr" --section "Made Up Section" "$ROOT/edit-body.md"
assert_contains "unknown-to-template refusal names the section" "$cr_unknown_err" "unknown section"
assert_eq "refused creation leaves the file byte-identical" "$cr_before" "$(cat "$f_cr")"
# Creation is all-or-nothing on write failure: a whitelisted-but-absent
# section passes the check, so the provoked mktemp failure must leave the
# file untouched. Under root the chmod cannot provoke mktemp, so the
# assertions are skipped rather than run as no-ops.
if ((EUID != 0)); then
	f_cr2="$(t new --id EDT-6 --name "Creation Failure Target")"
	cr2_perm="$(stat -c %a "$TASKS_DIR/current")"
	chmod 500 "$TASKS_DIR/current"
	cr2_err="$(printf 'denied\n' | t edit "$f_cr2" --section "Risk Assessment" 2>&1 >/dev/null || true)"
	chmod "$cr2_perm" "$TASKS_DIR/current"
	assert_contains "creation write failure is reported explicitly" "$cr2_err" "failed to update"
	assert_not_contains "failed creation inserts no section" "$(cat "$f_cr2")" "## Risk Assessment"
	rm -f "$f_cr2"
fi
rm -f "$f_cr"
t render >/dev/null

echo "== edit: write failure is not misreported as unknown section =="
# Root is immune to mode bits, so the chmod cannot provoke the mktemp
# failure and the assertions are skipped rather than run as no-ops.
if ((EUID == 0)); then
	skip_test "edit reports a write failure explicitly (skipped under root)"
	skip_test "write failure is not misreported as unknown section (skipped under root)"
else
	ed_fail_updated="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_ed")"
	ed_perm_mode="$(stat -c %a "$TASKS_DIR/current")"
	chmod 500 "$TASKS_DIR/current"
	ed_perm_err="$(printf 'denied body\n' | t edit "$f_ed" --section Objective 2>&1 >/dev/null || true)"
	chmod "$ed_perm_mode" "$TASKS_DIR/current"
	assert_contains "edit reports a write failure explicitly" "$ed_perm_err" "failed to update"
	assert_contains "write failure names the task file" "$ed_perm_err" "$(basename "$f_ed")"
	assert_not_contains "write failure is not misreported as unknown section" "$ed_perm_err" "unknown section"
	assert_eq "failed edit leaves Updated untouched" "$ed_fail_updated" \
		"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_ed")"
	assert_eq "failed edit leaves no temp file behind" "" \
		"$(ls "$TASKS_DIR/current" | grep -F "$(basename "$f_ed")." || true)"
fi

echo "== edit: Updated refresh and dashboard render =="
t set "$f_ed" Updated="2020-01-01 00:00" >/dev/null
printf 'Render check body\n' | t edit "$f_ed" --section Objective >/dev/null
ed_updated="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_ed")"
[[ "$ed_updated" == "$(clock_today)"* ]] \
	&& ok "edit bumps Updated to today" || bad "edit bumps Updated to today (got [$ed_updated])"
assert_contains "dashboard reflects the edit bump" "$(grep -F 'Edit Section Target' "$DASH")" "$ed_updated"

echo "== edit: --dir flag =="
printf 'Dir flag edit body\n' | t edit --dir "$dirtasks" "$(basename "$f_dir")" --section Objective >/dev/null
assert_contains "edit --dir applies to the requested board" \
	"$(cat "$dirtasks/current/$(basename "$f_dir")")" "Dir flag edit body"

echo "== edit: subsection boundary semantics =="
subsec="$TASKS_DIR/current/20240101-1300-subsection-boundary.md"
cat >"$subsec" <<'EOF'
# Task: Subsection Boundary Target

**Status:** Triage
**Updated:** 2024-01-01 13:00

## Parent Section

parent intro line

### Child Section

child line

## Next Section

next body
EOF
printf 'replaced child body\n' | t edit "$subsec" --section "Child Section" >/dev/null
sub_child="$(awk '/^### Child Section$/{f=1;next} /^## Next Section$/{f=0} f' "$subsec")"
assert_eq "replace is bounded by the next same-or-higher heading" \
	"$(printf '\nreplaced child body')" "$sub_child"
printf 'appended at region end\n' | t edit "$subsec" --section "Parent Section" --append >/dev/null
sub_parent="$(awk '/^## Parent Section$/{f=1;next} /^## Next Section$/{f=0} f' "$subsec")"
assert_eq "append spans the section's whole region" \
	"$(printf '\nparent intro line\n\n### Child Section\n\nreplaced child body\n\nappended at region end')" "$sub_parent"
sub_next="$(awk '/^## Next Section$/{f=1} f' "$subsec")"
assert_contains "edit leaves the following section intact" "$sub_next" "next body"
rm -f "$subsec"
t render >/dev/null

echo "== concurrent edit and log serialize (no lost update) =="
f_ce="$(t new --id EDT-3 --name "Concurrency Edit Target")"
ce_body="$ROOT/conc-edit-body.md"
ce_concdir="$(mktemp -d)"
ce_fail=0
ce_field() { grep -oP "^\\*\\*$1:\\*\\*\\s+\\K.*" "$f_ce"; }
ce_cell() { grep -F 'Concurrency Edit Target' "$DASH" | cut -d'|' -f"$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
for round in 1 2 3 4 5 6 7 8 9 10 11 12; do
	# One writer replaces the Objective body through `tasks edit`, the other
	# appends a Work Log entry through `tasks log`. Both hold the board lock,
	# so whichever order they land in, the section body and the new entry
	# must both be present and the dashboard row must equal the file after
	# the round; a stale read-modify-write from either side would drop the
	# other's write while both exit 0, so any mismatch is a lost update.
	printf 'round %s baseline body\n' "$round" >"$ce_body"
	t edit "$f_ce" --section Objective "$ce_body" >/dev/null
	entries_before="$(grep -c '^### ' "$f_ce" || true)"
	printf 'race %s body\n' "$round" >"$ce_body"
	t edit "$f_ce" --section Objective "$ce_body" >"$ce_concdir/e.out" 2>&1 &
	e_pid=$!
	t log "$f_ce" --from "conc-$round" "round $round edit race entry" >"$ce_concdir/l.out" 2>&1 &
	l_pid=$!
	wait "$e_pid"; e_code=$?
	wait "$l_pid"; l_code=$?
	[[ "$e_code" == 0 && "$l_code" == 0 ]] || ce_fail=$((ce_fail + 1))
	ce_region="$(awk '/^## Objective$/{f=1;next} /^## Success Criteria$/{f=0} f' "$f_ce")"
	[[ "$ce_region" == *"race $round body"* ]] || ce_fail=$((ce_fail + 1))
	entries_after="$(grep -c '^### ' "$f_ce" || true)"
	[[ "$entries_after" == "$((entries_before + 1))" ]] || ce_fail=$((ce_fail + 1))
	[[ "$(ce_cell 5)" == "$(ce_field Updated)" ]] || ce_fail=$((ce_fail + 1))
done
assert_eq "concurrent edit and log lose no update across rounds" "0" "$ce_fail"
rm -rf "$ce_concdir"

echo "== show: header fields and last N entries =="
f_sh="$(t new --id SHW-1 --name "Show Target")"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do t log "$f_sh" "Entry number $i" >/dev/null; done
sh_md5_before="$(md5sum "$f_sh" | cut -d' ' -f1)"
dash_md5_before="$(md5sum "$DASH" | cut -d' ' -f1)"
out="$(t show "$f_sh")"
assert_contains "show prints the title" "$out" "# Task: Show Target"
assert_contains "show prints header fields" "$out" "**Status:**"
assert_contains "show prints Latest Update" "$out" "**Latest Update:**"
assert_eq "show defaults to the last 10 entries" "10" "$(grep -c '^### ' <<<"$out")"
assert_contains "show tail includes the newest entry" "$out" "Entry number 12"
assert_contains "show tail starts at the cutoff entry" "$out" "Entry number 3"
assert_not_contains "show tail omits older entries" "$out" "Entry number 2"
out3="$(t show "$f_sh" --tail 3)"
assert_eq "show --tail 3 prints three entries" "3" "$(grep -c '^### ' <<<"$out3")"
assert_contains "show --tail 3 includes the newest entry" "$out3" "Entry number 12"
assert_contains "show --tail 3 starts at its cutoff entry" "$out3" "Entry number 10"
assert_not_contains "show --tail 3 omits older entries" "$out3" "Entry number 9"
assert_eq "show is read-only on the task file" "$sh_md5_before" "$(md5sum "$f_sh" | cut -d' ' -f1)"
assert_eq "show leaves the dashboard untouched" "$dash_md5_before" "$(md5sum "$DASH" | cut -d' ' -f1)"
refuse "show rejects --tail 0" show "$f_sh" --tail 0
refuse "show rejects a non-numeric tail" show "$f_sh" --tail abc
refuse "show rejects a negative tail" show "$f_sh" --tail -1
refuse "show rejects a valueless trailing --tail" show "$f_sh" --tail
refuse "show rejects a valueless trailing --dir" show "$f_sh" --dir
tail_flag_err="$(t show "$f_sh" --tail --bogus 2>&1 >/dev/null || true)"
assert_contains "show refuses a flag-shaped --tail value" "$tail_flag_err" "show: --tail requires a value"
showdir_flag_err="$(t show "$f_sh" --dir --bogus 2>&1 >/dev/null || true)"
assert_contains "show refuses a flag-shaped --dir value" "$showdir_flag_err" "show: --dir requires a value"
refuse "show rejects a missing task file" show NOPE-9.md
f_nolog="$(t new --id SHW-2 --name "Show No Log Target")"
out_empty="$(t show "$f_nolog")"
assert_contains "show works on a task without entries" "$out_empty" "# Task: Show No Log Target"
assert_eq "show without entries prints none" "0" "$(grep -c '^### ' <<<"$out_empty")"

echo "== show: work_log_tail reads its snapshot from stdin =="
# The tail must come from the piped snapshot, never from a re-read of a
# file operand. The function is eval-extracted and $file is pointed at
# /dev/null, so only a stdin-reading implementation can produce the
# expected tail.
eval "$(awk '/^work_log_tail\(\)/{f=1} f{print} f&&/^}/{exit}' "$TASKS_BIN")"
wlt_sample="$(printf '## Objective\n\nbody\n\n## Work Log\n\n### 2026-01-01 09:00: Manager: first\n\nfirst body\n\n### 2026-01-01 09:05: Manager: second\n\nsecond body\n')"
wlt_out="$(printf '%s\n' "$wlt_sample" | file=/dev/null work_log_tail 1)"
assert_eq "work_log_tail reads its tail from piped stdin" \
	"### 2026-01-01 09:05: Manager: second

second body" "$wlt_out"
wlt_two="$(printf '%s\n' "$wlt_sample" | file=/dev/null work_log_tail 2)"
assert_contains "work_log_tail with n=2 reaches the first entry" "$wlt_two" \
	"### 2026-01-01 09:00: Manager: first"
wlt_none="$(printf '## Objective\n\nno Work Log section here\n' | file=/dev/null work_log_tail 5)"
assert_eq "work_log_tail without a Work Log section prints nothing" "" "$wlt_none"

echo "== render: lanes sort chronologically and cells carry task IDs =="
# Dedicated board: ordering needs controlled Created/Completed values,
# deliberate date ties, and undated fixtures, isolated from the main
# board's accumulated tasks. Active lanes must read in Created order,
# Completed/Archive in Completed order, undated rows last, date ties in
# segment-numeric task ID order (parent before child), and every Task
# cell must carry the filename-derived ID prefix.
orddir="$ROOT/order/.tasks"
t init --dir "$orddir" >/dev/null
ordboard="$orddir/dashboard.md"
ord_rows() { # lane next-lane; prints the lane's task rows
	awk -v lane="## $1" -v after="## ${2:-}" \
		'after != "" && index($0, after) == 1 { f = 0 }
		 index($0, lane) == 1 { f = 1; next }
		 f && index($0, "| [") == 1' "$ordboard"
}
ord_labels() { # lane next-lane; prints each row's link text in lane order
	ord_rows "$1" "${2:-}" | sed -E 's/^\| \[([^]]*)\]\(.*/\1/'
}
# Triage fixture: Created order deliberately disagrees with both filename
# order and ID order, and the tie group covers the segment-numeric rules
# (ORD-2 < ORD-2-1 < ORD-10 < ORD-1231).
f_o2="$(t new --id ORD-2 --name "Tie Task Two" --dir "$orddir")"
f_o21="$(t new --id ORD-2-1 --name "Tie Task Child" --dir "$orddir")"
f_o10="$(t new --id ORD-10 --name "Tie Task Ten" --dir "$orddir")"
f_o1231="$(t new --id ORD-1231 --name "Tie Task Twelve Thirty One" --dir "$orddir")"
f_o9="$(t new --id ORD-9 --name "Early Task" --dir "$orddir")"
f_o3="$(t new --id ORD-3 --name "Late Task" --dir "$orddir")"
for ord_f in "$f_o9" "$f_o2" "$f_o21" "$f_o10" "$f_o1231" "$f_o3"; do
	case "$(basename "$ord_f")" in
		ORD-9-*) ord_created="2025-01-15 08:30" ;;
		ORD-3-*) ord_created="2026-05-20 11:00" ;;
		*) ord_created="2026-03-02 10:00" ;;
	esac
	t set --dir "$orddir" "$(basename "$ord_f")" "Created=$ord_created" Updated="2026-01-01 00:00" >/dev/null
done
# A task file with no leading ID component and no Created field: bare
# name fallback and last place in its lane.
cat >"$orddir/current/99991231-2359-no-id-task.md" <<'EOF'
# Task: No ID Task

**Status:** Triage
**Priority:** Low
**Updated:** 2026-01-01 00:00

## Objective
EOF
t render --dir "$orddir" >/dev/null
assert_eq "Triage sorts by Created ascending, ties segment-numerically, undated last" \
	"$(printf '%s\n' \
		"ORD-9: Early Task" \
		"ORD-2: Tie Task Two" \
		"ORD-2-1: Tie Task Child" \
		"ORD-10: Tie Task Ten" \
		"ORD-1231: Tie Task Twelve Thirty One" \
		"ORD-3: Late Task" \
		"No ID Task")" \
	"$(ord_labels Triage Ready)"
assert_contains "task cell carries the ID prefix derived from the filename" \
	"$(ord_rows Triage Ready)" "| [ORD-9: Early Task](./current/"
assert_contains "filename without a leading ID renders the bare descriptive name" \
	"$(ord_rows Triage Ready)" "| [No ID Task](./current/99991231-2359-no-id-task.md) |"
assert_not_contains "no-ID fallback adds no ID prefix" \
	"$(ord_labels Triage Ready)" "No ID Task:"
f_o31="$(t new --id ORD-31 --name "Ready Older" --status Ready --dir "$orddir")"
f_o30="$(t new --id ORD-30 --name "Ready Younger" --status Ready --dir "$orddir")"
t set --dir "$orddir" "$(basename "$f_o31")" Created="2026-04-01 09:00" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_o30")" Created="2026-04-05 09:00" Updated="2026-01-01 00:00" >/dev/null
assert_eq "Ready sorts by Created ascending regardless of task ID order" \
	"$(printf '%s\n' "ORD-31: Ready Older" "ORD-30: Ready Younger")" \
	"$(ord_labels Ready "In Progress")"
f_o20="$(t new --id ORD-20 --name "Active Younger" --status "In Progress" --dir "$orddir")"
f_oa21="$(t new --id ORD-21 --name "Active Older" --status "In Progress" --dir "$orddir")"
t set --dir "$orddir" "$(basename "$f_o20")" Created="2026-03-10 09:00" Updated="2026-06-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_oa21")" Created="2026-01-10 09:00" Updated="2026-02-01 00:00" >/dev/null
assert_eq "In Progress sorts by Created even though the lane shows no Created column" \
	"$(printf '%s\n' "ORD-21: Active Older" "ORD-20: Active Younger")" \
	"$(ord_labels "In Progress" "Blocked/Cancelled")"
f_o32="$(t new --id ORD-32 --name "Stuck Younger" --dir "$orddir")"
f_o33="$(t new --id ORD-33 --name "Stuck Older" --dir "$orddir")"
t set --dir "$orddir" "$(basename "$f_o32")" Status=Blocked "Status Reason=order probe" Created="2026-02-02 09:00" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_o33")" Status=Blocked "Status Reason=order probe" Created="2026-02-01 09:00" Updated="2026-01-01 00:00" >/dev/null
assert_eq "Blocked/Cancelled sorts by Created ascending" \
	"$(printf '%s\n' "ORD-33: Stuck Older" "ORD-32: Stuck Younger")" \
	"$(ord_labels "Blocked/Cancelled" Completed)"
f_o6="$(t new --id ORD-6 --name "Done Early" --dir "$orddir")"
f_o7="$(t new --id ORD-7 --name "Done Mid" --dir "$orddir")"
f_o40="$(t new --id ORD-40 --name "Done Late" --dir "$orddir")"
f_o8="$(t new --id ORD-8 --name "Done Undated" --dir "$orddir")"
f_o5="$(t new --id ORD-5 --name "Done Tie Five" --dir "$orddir")"
f_o45="$(t new --id ORD-45 --name "Done Tie Forty Five" --dir "$orddir")"
t set --dir "$orddir" "$(basename "$f_o6")" Status=Completed Completed="2026-02-01 12:00" Duration="1h" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_o5")" Status=Completed Completed="2026-03-15 08:00" Duration="1h" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_o45")" Status=Completed Completed="2026-03-15 08:00" Duration="1h" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_o7")" Status=Completed Completed="2026-04-01 12:00" Duration="2h" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_o40")" Status=Completed Completed="2026-06-01 12:00" Duration="3h" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_o8")" Status=Completed Duration="4h" Updated="2026-01-01 00:00" >/dev/null
assert_eq "Completed sorts by Completed ascending, ties segment-numerically, undated last" \
	"$(printf '%s\n' \
		"ORD-6: Done Early" \
		"ORD-5: Done Tie Five" \
		"ORD-45: Done Tie Forty Five" \
		"ORD-7: Done Mid" \
		"ORD-40: Done Late" \
		"ORD-8: Done Undated")" \
	"$(ord_labels Completed Archive)"
mv "$f_o40" "$orddir/archive/"
f_o41="$(t new --id ORD-41 --name "Archived Undated" --dir "$orddir")"
t set --dir "$orddir" "$(basename "$f_o41")" Status=Completed Duration="5h" Updated="2026-01-01 00:00" >/dev/null
mv "$f_o41" "$orddir/archive/"
t render --dir "$orddir" >/dev/null
assert_eq "Archive sorts by Completed ascending with undated last" \
	"$(printf '%s\n' "ORD-40: Done Late" "ORD-41: Archived Undated")" \
	"$(ord_labels Archive)"
# Residual ties (same date, same task ID) still render exactly once each
# and repeated renders stay byte-identical.
f_dup1="$(t new --id ORD-50 --name "Duplicate ID Task" --dir "$orddir")"
# --force: the deliberate duplicate is the fixture under test here (the
# subject is residual-tie rendering, not the duplicate ID guard).
f_dup2="$(t new --id ORD-50 --name "Duplicate ID Task" --force --dir "$orddir")"
[[ "$f_dup1" != "$f_dup2" ]] && ok "duplicate-ID creation yields two files" || bad "duplicate-ID creation yields two files"
t set --dir "$orddir" "$(basename "$f_dup1")" Created="2026-07-07 07:07" Updated="2026-01-01 00:00" >/dev/null
t set --dir "$orddir" "$(basename "$f_dup2")" Created="2026-07-07 07:07" Updated="2026-01-01 00:00" >/dev/null
t render --dir "$orddir" >/dev/null
dup_count="$(ord_labels Triage Ready | grep -cF 'ORD-50: Duplicate ID Task')"
assert_eq "residual ties on date and task ID both render" "2" "$dup_count"
ord_before="$(cat "$ordboard")"
t render --dir "$orddir" >/dev/null
ord_after="$(cat "$ordboard")"
assert_eq "ordered render is byte-identical on repeat" "$ord_before" "$ord_after"

echo "== lint: read-only board protocol lint =="
# The lint fixture board lives inside its own tiny git repo so the
# push-reconcile pass has a real history to consult; --dir pins the board,
# so the battery's TASKS_DIR never interferes. Fixture files are written
# directly (lint is the subject under test, not the write path).
lint_repo="$ROOT/lintrepo"
lint_dir="$lint_repo/.tasks"
mkdir -p "$lint_repo"
git -C "$lint_repo" init -q .
git -C "$lint_repo" config user.email lint-probe@invalid
git -C "$lint_repo" config user.name "Lint Probe"
echo seed >"$lint_repo/seed.txt"
git -C "$lint_repo" add seed.txt
git -C "$lint_repo" commit -qm "seed"
lint_reach="$(git -C "$lint_repo" rev-parse HEAD)"
t init --dir "$lint_dir" >/dev/null
f_lp="$(t new --id LP-1 --name "Lint Probe Target" --dir "$lint_dir")"

if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "lint passes a clean board"; else bad "lint passes a clean board"; fi
lint_sum="$(t lint --dir "$lint_dir" | tail -1)"
assert_contains "clean lint reports zero hard" "$lint_sum" "0 hard"

# Header shape on an open task is a hard failure (the Option-1 split).
sed -i 's/^\*\*Latest Update:.*/**Latest Update:** [2026-10-23 10:1X] hand-stamped probe/' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags a hand-stamped header field as hard" "$lint_out" \
	"HARD current/LP-1-"
assert_contains "lint names the non-CLI-shaped field" "$lint_out" "header Latest Update not CLI-shaped"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then bad "lint exits 1 on hard findings"; else ok "lint exits 1 on hard findings"; fi

# Missing required template section on an open task is a hard failure.
awk '/^## Execution Log$/{skip=1} !skip' "$f_lp" >"$f_lp.tmp" && mv "$f_lp.tmp" "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags a missing required section" "$lint_out" "missing required section 'Execution Log'"

# Repair the structural findings (CLI-shaped timestamp restored, section
# re-added) so the following assertions read a board whose only remaining
# drift is the body-space kind.
sed -i 's/^\*\*Latest Update:.*/**Latest Update:** [2026-06-15 12:00] repaired probe/' "$f_lp"
printf '\n## Execution Log\n\n- restored\n' >>"$f_lp"

# Body-space drift stays advisory even on an open task (Option-1: prose is
# free-form), and dead-link detection resolves ../reports/ from the file's
# own directory.
printf '%s\n' 'see [report](../reports/LP-1-20260615-1200-lint-probe-target/01-gone.md) here' >>"$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags a dead report link" "$lint_out" "dead report link"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "dead links stay advisory on open tasks"; else bad "dead links stay advisory on open tasks"; fi
# Backticked format placeholders and explicitly annotated dead links are
# not live links and must not fire.
printf '%s\n' 'canonical form `[ts] digest ([report](../reports/...))` stays literal' >>"$f_lp"
printf '%s\n' '**Report:** [07-gone.md](../reports/LP-1-20260615-1200-lint-probe-target/07-gone.md) (dead link: renumbered before deposit)' >>"$f_lp"
lint_dead="$(t lint --dir "$lint_dir" --verbose | grep -c 'dead report link')"
assert_eq "the skipped pair adds no dead-link finding" "1" "$lint_dead"

# Push-reconcile: a reachable recorded hash is silent, an unreachable one
# is hard on an open task, and a line documenting known drift is skipped.
t log --dir "$lint_dir" "$(basename "$f_lp")" "landed commit $lint_reach on the branch" >/dev/null
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_not_contains "a reachable recorded commit is silent" "$lint_out" "unreachable from any branch"
printf '%s\n' 'commit deadbee99 pushed to origin' >>"$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags an unreachable recorded commit as hard" "$lint_out" \
	"recorded commit deadbee99"
printf '%s\n' 'commit deadbe00 recorded landed+pushed but unreachable everywhere; superseded by re-land' >>"$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_not_contains "a drift-disposition hash line is skipped" "$lint_out" "deadbe00"
sed -i '/commit deadbee99 pushed to origin/d' "$f_lp"

# Claim hygiene: Owner without sidecar, sidecar without Owner, and an
# owner mismatch are hard on an open task; parity passes silently. Owner
# is claim-owned now, so the drift fixtures are written directly into the
# header (sed), the same direct-fixture approach the rest of this section
# uses (lint is the subject under test, not the write path).
sed -i 's/^\*\*Owner:\*\*.*/**Owner:** ghost-session/' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags Owner without a claim sidecar" "$lint_out" "Owner 'ghost-session' set without a claim sidecar"
sed -i 's/^\*\*Owner:\*\*.*/**Owner:**/' "$f_lp"
printf 'orphan-owner\n' >"$f_lp.claim"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags a sidecar whose header Owner is empty" "$lint_out" \
	"claim sidecar present but header Owner is empty"
sed -i 's/^\*\*Owner:\*\*.*/**Owner:** live-owner/' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags a sidecar-owner mismatch" "$lint_out" "does not match header Owner 'live-owner'"
sed -i 's/^\*\*Owner:\*\*.*/**Owner:** orphan-owner/' "$f_lp"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "matching owner and sidecar passes"; else bad "matching owner and sidecar passes"; fi

# Terminal files are advisory-only: a Completed task with unchecked boxes
# and a stale sidecar never fails the exit code.
printf 'someone\n' >"$f_lp.claim"
sed -i 's/^\*\*Status:.*/**Status:** Completed/' "$f_lp"
sed -i '/^\*\*Updated:/a **Completed:** 2026-06-15 12:00' "$f_lp"
sed -i '/^\*\*Completed:/a **Duration:** N\/A' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint reports unchecked boxes on Completed as advisory" "$lint_out" \
	"unchecked Success Criteria boxes"
assert_contains "lint reports a stale sidecar on Completed as advisory" "$lint_out" \
	"stale claim sidecar"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "terminal-file drift keeps lint green"; else bad "terminal-file drift keeps lint green"; fi

# The ~ superseded annotation is its own lint state, neither an unchecked
# box nor a ticked lie: a ~-marked criterion never reports as unchecked
# on a terminal file, and an open file mixing ticked and ~ boxes is not
# reported as all-checked. Flipping the same line to a plain unticked
# box must report, so the pair pins the distinction.
f_lint_tilde="$lint_dir/current/20260601-0900-lint-tilde-probe.md"
printf '%s\n' '# Task: Lint Tilde Probe' '' '**Created:** 2026-06-01 09:00' '**Status:** Completed' '**Priority:** Low' '**Progress:** 0%' '**Owner:**' '**Updated:** 2026-06-01 09:30' '' '## Table of Contents' '' '## Objective' '' '## Success Criteria' '' '- ~ [ ] superseded criterion' '' '## Work Log' '' '## Execution Log' >"$f_lint_tilde"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_not_contains "a ~-marked criterion is not an unchecked box" "$lint_out" "lint-tilde-probe"
sed -i 's/^\*\*Status:.*/**Status:** Triage/' "$f_lint_tilde"
printf '%s\n' '- [x] done criterion' >>"$f_lint_tilde"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_not_contains "ticked and ~ boxes on an open task are not all-checked" "$lint_out" "lint-tilde-probe"
sed -i 's/^- ~ \[ \] superseded criterion$/- [ ] superseded criterion/' "$f_lint_tilde"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_not_contains "the unticked box alone stays quiet on an open task" "$lint_out" "lint-tilde-probe"
sed -i 's/^\*\*Status:.*/**Status:** Completed/' "$f_lint_tilde"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "the same line unticked reports as unchecked" "$lint_out" \
	"ADVISORY current/20260601-0900-lint-tilde-probe.md: Status Completed with 1 unchecked Success Criteria boxes"
rm -f "$f_lint_tilde"

# An orphan sidecar (no task file behind it) is board corruption: hard.
printf 'ghost\n' >"$lint_dir/current/20240101-0900-ghost-task.md.claim"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags an orphan claim sidecar as hard" "$lint_out" "claim sidecar with no task file"
rm -f "$lint_dir/current/20240101-0900-ghost-task.md.claim"

# Status Reason coupling: the header contract ties the reason to
# Blocked/Cancelled, so a Cancelled header without one is hard on an
# open task and advisory once archived. The stale-sidecar fixture above
# is dropped first: the archived leg must carry only the reason finding,
# and a stranded current/ sidecar would read as a harder orphan.
rm -f "$f_lp.claim"
sed -i 's/^\*\*Status:.*/**Status:** Cancelled/' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags Cancelled without a Status Reason as hard" "$lint_out" \
	"HARD current/LP-1-"
assert_contains "the Cancelled coupling finding names the missing reason" "$lint_out" \
	"Status Cancelled requires a Status Reason"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then bad "lint exits 1 on Cancelled without a reason"; else ok "lint exits 1 on Cancelled without a reason"; fi
mv "$f_lp" "$lint_dir/archive/$(basename "$f_lp")"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "archived Cancelled without a reason is advisory" "$lint_out" \
	"ADVISORY archive/$(basename "$f_lp"): Status Cancelled requires a Status Reason"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "archived Cancelled drift keeps lint green"; else bad "archived Cancelled drift keeps lint green"; fi
mv "$lint_dir/archive/$(basename "$f_lp")" "$f_lp"
sed -i 's/^\*\*Status:.*/**Status:** Completed/' "$f_lp"

# The Blocked leg of the same coupling: the set path refuses to land on
# Blocked without a reason (pinned in the set section), so lint owns the
# hand-edited and legacy drift. Owner is emptied first: an open status
# carrying this fixture's sidecar-less Owner would add the claim-drift
# hard finding and muddy the exit-code pins below.
sed -i 's/^\*\*Owner:\*\*.*/**Owner:**/' "$f_lp"
sed -i 's/^\*\*Status:.*/**Status:** Blocked/' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint flags Blocked without a Status Reason as hard" "$lint_out" \
	"HARD current/$(basename "$f_lp"): Status Blocked requires a Status Reason"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then bad "lint exits 1 on Blocked without a reason"; else ok "lint exits 1 on Blocked without a reason"; fi
sed -i '/^\*\*Status:.*/a **Status Reason:** waiting on upstream repair' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_not_contains "the reason clears the Blocked coupling finding" "$lint_out" "Status Blocked requires"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "Blocked with a reason keeps lint green"; else bad "Blocked with a reason keeps lint green"; fi
sed -i '/^\*\*Status Reason:/d' "$f_lp"
mv "$f_lp" "$lint_dir/archive/$(basename "$f_lp")"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "archived Blocked without a reason is advisory" "$lint_out" \
	"ADVISORY archive/$(basename "$f_lp"): Status Blocked requires a Status Reason"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "archived Blocked drift keeps lint green"; else bad "archived Blocked drift keeps lint green"; fi
mv "$lint_dir/archive/$(basename "$f_lp")" "$f_lp"
sed -i 's/^\*\*Status:.*/**Status:** Completed/' "$f_lp"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_not_contains "a Completed header owes no Status Reason" "$lint_out" "requires a Status Reason"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "terminal-file reason absence keeps lint green"; else bad "terminal-file reason absence keeps lint green"; fi

# Archive hygiene: archiving an open task is advisory.
printf '%s\n' '# Task: Archived Open' '' '**Created:** 2024-01-01 09:01' '**Status:** Triage' '**Priority:** Low' '**Progress:** 0%' '**Owner:**' '**Updated:** 2024-01-01 09:30' '' '## Table of Contents' '' '## Objective' '' '## Success Criteria' '' '## Work Log' '' '## Execution Log' >"$lint_dir/archive/20240101-0901-archived-open.md"
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "lint reports an archived open task as advisory" "$lint_out" "archived while Triage"
if t lint --dir "$lint_dir" >/dev/null 2>&1; then ok "archive drift keeps lint green"; else bad "archive drift keeps lint green"; fi
rm -f "$lint_dir/archive/20240101-0901-archived-open.md"

# Advisory cap: the default output truncates and names the remainder;
# --verbose lists every finding.
for i in $(seq 1 30); do
	printf '%s\n' "see [report](../reports/LP-1-20260615-1200-lint-probe-target/$i-filler.md)" >>"$f_lp"
done
lint_out="$(t lint --dir "$lint_dir" 2>&1 || true)"
assert_contains "default lint caps the advisory listing" "$lint_out" "more advisory findings (run tasks lint --verbose to list all)"
verbose_count="$(t lint --dir "$lint_dir" --verbose | grep -c '^ADVISORY')"
(( verbose_count >= 32 )) && ok "--verbose lists every advisory finding" || bad "--verbose lists every advisory finding (got $verbose_count)"
# Lint never writes: the fixture dashboard is byte-identical after a run.
board_before="$(cat "$lint_dir/dashboard.md")"
t lint --dir "$lint_dir" >/dev/null 2>&1 || true
assert_eq "lint leaves the dashboard untouched" "$board_before" "$(cat "$lint_dir/dashboard.md")"

echo "== set: CLI-owned header fields are refused outside the test seam =="
# The Option-1 contract: header timeline fields (Created, Updated,
# Completed, Duration, Latest Update) are stamped by the CLI's own
# operations, never written through set. The battery runs with
# TASKS_TEST_CLOCK exported, so these probes unset it locally; every
# assertion runs in the parent because the harness counters are
# in-process.
guard_target="$(t new --id GRD-5 --name "Guard Probe Target")"
guard_before="$(cat "$guard_target")"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" "Completed=2026-01-01 00:00" 2>&1 >/dev/null || true)"
assert_contains "set refuses Completed outside the seam" "$guard_err" "'Completed' is CLI-owned"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" Duration=1h 2>&1 >/dev/null || true)"
assert_contains "set refuses Duration outside the seam" "$guard_err" "'Duration' is CLI-owned"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" "Updated=2026-01-01 00:00" 2>&1 >/dev/null || true)"
assert_contains "set refuses Updated outside the seam" "$guard_err" "'Updated' is CLI-owned"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" "Created=2026-01-01 00:00" 2>&1 >/dev/null || true)"
assert_contains "set refuses Created outside the seam" "$guard_err" "'Created' is CLI-owned"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" "Latest Update=forged" 2>&1 >/dev/null || true)"
assert_contains "set refuses Latest Update outside the seam" "$guard_err" "'Latest Update' is CLI-owned"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" "Status=Completed" 2>&1 >/dev/null || true)"
assert_contains "set redirects Status=Completed to close" "$guard_err" "must go through 'tasks close'"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" "Status=Cancelled" 2>&1 >/dev/null || true)"
assert_contains "set redirects Status=Cancelled to close --cancelled" "$guard_err" "must go through 'tasks close --cancelled'"
assert_eq "the Status=Cancelled refusal leaves the file byte-identical" "$guard_before" "$(cat "$guard_target")"
guard_err="$(env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_target" "Completed=2026-01-01 00:00" 2>&1 >/dev/null || true)"
assert_contains "the refusal points at the stamping subcommands" "$guard_err" "log/report/claim/close/stamp"
assert_not_contains "the refusal no longer names the seam variable" "$guard_err" "TASKS_TEST_CLOCK"
assert_eq "guard refusals leave the file byte-identical" "$guard_before" "$(cat "$guard_target")"
# Under the seam the same writes land: the fixture backdating path.
t set "$guard_target" "Completed=2026-01-01 00:00" "Duration=2h 30m" >/dev/null
assert_contains "seam admits Completed for fixtures" "$(grep -oP '^\*\*Completed:\*\*\s+\K.*' "$guard_target")" "2026-01-01 00:00"
t set "$guard_target" Updated= >/dev/null
assert_eq "an emptied Updated= pair refreshes to the pinned clock" "2026-06-15 12:00" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$guard_target")"
guard_err="$(TASKS_TEST_CLOCK=garbage t show "$guard_target" 2>&1 >/dev/null || true)"
assert_contains "a malformed clock dies at startup" "$guard_err" "TASKS_TEST_CLOCK must be CLI-shaped"
guard_err="$(env -u TASKS_DIR "$TASKS_BIN" show "$guard_target" 2>&1 >/dev/null || true)"
assert_contains "the clock dies without an exported TASKS_DIR" "$guard_err" "honored only when TASKS_DIR is also exported"
# The redirect's target, pinned under the same production conditions: set
# cannot land Cancelled, so the reason rides Blocked and survives close
# --cancelled.
guard_reason="$(t new --id GRD-6 --name "Cancelled Reason Route Probe")"
env -u TASKS_TEST_CLOCK "$TASKS_BIN" set "$guard_reason" "Status=Blocked" "Status Reason=awaiting decision" >/dev/null
TASKS_TEST_CLOCK="2026-06-16 09:00" t close "$guard_reason" --cancelled >/dev/null
assert_eq "the sanctioned Cancelled route lands the closure" "Cancelled" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$guard_reason")"
assert_contains "the sanctioned Cancelled route keeps the reason set while Blocked" \
	"$(awk '/^## /{exit}{print}' "$guard_reason")" "**Status Reason:** awaiting decision"
rm -f "$guard_reason"
rm -f "$guard_target"
t render >/dev/null

 echo "== close and stamp: closure stamping through the locked write path =="
# close derives Duration from the Work Log anchors and stamps Completed
# from the CLI clock; the header rewrite rides write_header_fields, so
# field order stays canonical and the dashboard rows stay byte-compatible.
# Plain-close fixtures carry their Success Criteria checked: the completion
# gate (section below) refuses unchecked boxes, and these probes exercise
# the stamping, not the gate.
f_cl="$(t new --id CLS-9 --name "Closure Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_cl"
TASKS_TEST_CLOCK="2026-06-15 09:00" t log "$f_cl" "first anchor" >/dev/null
TASKS_TEST_CLOCK="2026-06-15 11:30" t log "$f_cl" "second anchor" >/dev/null
close_out="$(TASKS_TEST_CLOCK="2026-06-16 10:00" t close "$f_cl")"
assert_contains "close reports the stamped completion" "$close_out" "Completed 2026-06-16 10:00"
assert_contains "close reports the derived duration" "$close_out" "Duration 2h 30m"
assert_eq "close stamps Status Completed" "Completed" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_cl")"
assert_eq "close stamps Completed from the CLI clock" "2026-06-16 10:00" \
	"$(grep -oP '^\*\*Completed:\*\*\s+\K.*' "$f_cl")"
assert_eq "close derives Duration from the Work Log anchors" "2h 30m" \
	"$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_cl")"
assert_eq "close refreshes Updated" "2026-06-16 10:00" \
	"$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_cl")"
cls_order="$(awk '/^## /{exit} {if (match($0, /^\*\*[^*:]+:\*\*/)) print substr($0, RSTART+2, RLENGTH-5)}' "$f_cl")"
assert_eq "close keeps the canonical header order" \
	"$(printf '%s\n' Created Status Priority Progress Owner Updated Completed Duration "Latest Update")" \
	"$cls_order"
board="$(cat "$DASH")"
cls_row="$(grep -F 'Closure Probe' <<<"$board")"
assert_contains "the Completed lane carries the stamped timestamp" "$cls_row" "2026-06-16 10:00"
assert_contains "the Completed lane carries the derived duration" "$cls_row" "2h 30m"
refuse "close refuses an already-Completed task" close "$f_cl"

# stamp re-stamps an already-Completed task and re-derives Duration.
stamp_out="$(TASKS_TEST_CLOCK="2026-06-20 08:00" t stamp "$f_cl")"
assert_contains "stamp re-stamps Completed" "$stamp_out" "Completed 2026-06-20 08:00"
assert_eq "stamp keeps Duration derived from the anchors" "2h 30m" \
	"$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_cl")"

# A multi-day span renders in the compact d/h form; fewer than two
# parseable anchors yields N/A.
f_md="$(t new --id CLS-10 --name "Multi Day Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_md"
TASKS_TEST_CLOCK="2026-06-15 08:00" t log "$f_md" "day one" >/dev/null
TASKS_TEST_CLOCK="2026-06-18 11:00" t log "$f_md" "day four" >/dev/null
TASKS_TEST_CLOCK="2026-06-18 12:00" t close "$f_md" >/dev/null
assert_eq "close renders multi-day durations in the compact form" "3d 3h" \
	"$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_md")"
f_na="$(t new --id CLS-11 --name "No Anchor Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_na"
refuse "stamp refuses a task that is not Completed" stamp "$f_na"
TASKS_TEST_CLOCK="2026-06-16 12:00" t close "$f_na" >/dev/null
assert_eq "close without two anchors stamps N/A" "N/A" \
	"$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_na")"

# Closing from Blocked drops the Status Reason and releases the claim:
# the header contract carries the reason only under Blocked/Cancelled, and
# a closed task owns nothing.
f_blk="$(t new --id CLS-12 --name "Blocked Closure Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_blk"
t set "$f_blk" Status=Blocked "Status Reason=waiting on deps" >/dev/null
t claim "$f_blk" --owner sess-closer >/dev/null
TASKS_TEST_CLOCK="2026-06-16 11:00" t close "$f_blk" >/dev/null
assert_not_contains "close drops the Status Reason" "$(awk '/^## /{exit}{print}' "$f_blk")" "**Status Reason:**"
[[ ! -f "$f_blk.claim" ]] && ok "close removes the claim sidecar" || bad "close removes the claim sidecar"
assert_eq "close clears Owner" "1" "$(grep -c '^\*\*Owner:\*\*$' "$f_blk")"
refuse "close without a taskfile is refused" close
refuse "stamp without a taskfile is refused" stamp

echo "== close: the completion gate (unchecked boxes, named children, --force override) =="
# The gate refuses before any write when the Success Criteria carry
# unchecked boxes or a named child task is still open; a named child is a
# task-ID-shaped token in the file that resolves to a board file, with the
# file's own ID, tokens naming no board file, and terminal children
# ignored. --force closes past a refusing gate and records the override as
# a Work Log anchor stamped at closure, so the elapsed Duration spans
# first anchor to closure on the forced path.
f_gate="$(t new --id CGT-1 --name "Closure Gate Probe")"
TASKS_TEST_CLOCK="2026-06-15 09:00" t log "$f_gate" "first anchor" >/dev/null
TASKS_TEST_CLOCK="2026-06-15 10:00" t log "$f_gate" "second anchor" >/dev/null
gate_before="$(cat "$f_gate")"
gate_err="$(t close "$f_gate" 2>&1 >/dev/null || true)"
assert_contains "close refuses unchecked Success Criteria" "$gate_err" "fails the closure gate"
assert_contains "the refusal counts the unchecked boxes" "$gate_err" "unchecked Success Criteria boxes: 1"
assert_contains "the refusal offers the --force route" "$gate_err" "close anyway with --force"
assert_eq "the refused closure leaves the file byte-identical" "$gate_before" "$(cat "$f_gate")"
refuse "close without --force exits nonzero" close "$f_gate"

# A child declared on a dedicated dependency surface blocks even with
# every box checked, while a Work Log prose citation of the same open
# sibling closes clean (citation is not dependency): the dedicated
# surfaces are the ## Dependencies section, **Dependencies:** field
# lines, and **Child tasks:** declaration lines, with the parent's own ID
# and an ID that names no board file ignored there. Completing the child
# unlocks the parent.
f_gate_child="$(t new --id CGT-2 --name "Gate Child Probe")"
f_gate_prose="$(t new --id CGT-3 --name "Gate Prose Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_prose"
TASKS_TEST_CLOCK="2026-06-16 07:00" t log "$f_gate_prose" "work follows CGT-2; tracked here as CGT-3; NOPE-9 names no board task" >/dev/null
TASKS_TEST_CLOCK="2026-06-16 07:30" t close "$f_gate_prose" >/dev/null
assert_eq "a Work Log prose citation of an open sibling closes clean" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_gate_prose")"
f_gate_own="$(t new --id CGT-4 --name "Gate Own ID Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_own"
t edit "$f_gate_own" --section Dependencies --append <<<"- CGT-4 is this file's own ID and NOPE-9 names no board task" >/dev/null
t close "$f_gate_own" >/dev/null
assert_eq "own ID and unknown tokens on a dependency surface are ignored" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_gate_own")"
f_gate_parent="$(t new --id CGT-5 --name "Gate Parent Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_parent"
t edit "$f_gate_parent" --section Dependencies --append <<<"- CGT-2" >/dev/null
gate_err="$(t close "$f_gate_parent" 2>&1 >/dev/null || true)"
assert_contains "close refuses a child declared in the Dependencies section" "$gate_err" "unfinished named child task(s): CGT-2"
refuse "the child gate refuses before any write" close "$f_gate_parent"
f_gate_field="$(t new --id CGT-6 --name "Gate Dependencies Field Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_field"
t edit "$f_gate_field" --section Objective --append <<<"**Dependencies:** CGT-2" >/dev/null
gate_err="$(t close "$f_gate_field" 2>&1 >/dev/null || true)"
assert_contains "close refuses a child named on a Dependencies field line" "$gate_err" "unfinished named child task(s): CGT-2"
f_gate_decl="$(t new --id CGT-7 --name "Gate Declaration Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_decl"
t edit "$f_gate_decl" --section Objective --append <<<"**Child tasks:** CGT-2" >/dev/null
gate_err="$(t close "$f_gate_decl" 2>&1 >/dev/null || true)"
assert_contains "close refuses a declared child task" "$gate_err" "unfinished named child task(s): CGT-2"
gate_out="$(TASKS_TEST_CLOCK="2026-06-16 07:45" t close "$f_gate_field" --force)"
assert_contains "close --force closes past a declared child" "$gate_out" "closed $(basename "$f_gate_field")"
assert_contains "the override note names the declared child" \
	"$(awk '/^## Work Log/{f=1} f' "$f_gate_field")" "unfinished named child task(s): CGT-2"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_child"
TASKS_TEST_CLOCK="2026-06-16 08:00" t close "$f_gate_child" >/dev/null
t close "$f_gate_parent" >/dev/null
assert_eq "a parent closes once its declared child is terminal" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_gate_parent")"

# The override: --force closes past the refusing gate and records the
# note as a Work Log anchor at the closure clock, and the Duration
# re-derives after that append, so the stamped span reads first anchor
# (09:00) to closure (12:00), not the pre-existing 1h span.
gate_out="$(TASKS_TEST_CLOCK="2026-06-15 12:00" t close "$f_gate" --force)"
assert_contains "close --force closes past the gate" "$gate_out" "closed $(basename "$f_gate")"
gate_log="$(awk '/^## Work Log/{f=1} f' "$f_gate")"
assert_contains "the override is recorded in the Work Log" "$gate_log" "closure gate overridden (--force)"
assert_contains "the override note names the finding" "$gate_log" "unchecked Success Criteria boxes: 1"
assert_eq "close --force still stamps Completed" "Completed" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_gate")"
assert_eq "the override anchor bounds the elapsed Duration" "3h" \
	"$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_gate")"
gate_err="$(t close "$f_gate" --cancelled --force 2>&1 >/dev/null || true)"
assert_contains "the cancelled path refuses --force" "$gate_err" "--force gates the completion path only"

# --force on a gate that passes is a plain closure: no override note.
f_gate_ready="$(t new --id CGT-4 --name "Gate Ready Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_ready"
t close "$f_gate_ready" --force >/dev/null
assert_not_contains "close --force on a ready gate writes no override note" \
	"$(awk '/^## Work Log/{f=1} f' "$f_gate_ready")" "closure gate overridden"

# The field-form dependency surfaces bind only before the ## Work Log
# heading: a line-initial **Dependencies:** citation inside a Work Log
# entry quotes the template form as prose, so it closes clean, while the
# same line in the header region still refuses.
f_gate_logfield="$(t new --id CGT-8 --name "Gate Log Field Probe")"
f_gate_sibling="$(t new --id CGT-9 --name "Gate Log Field Sibling")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_logfield"
TASKS_TEST_CLOCK="2026-06-16 09:00" t log "$f_gate_logfield" "$(printf 'digest quoting the template field form\n**Dependencies:** CGT-9')" >/dev/null
TASKS_TEST_CLOCK="2026-06-16 09:15" t close "$f_gate_logfield" >/dev/null
assert_eq "a Work Log field-form citation of an open sibling closes clean" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_gate_logfield")"
f_gate_hdrfield="$(t new --id CGT-10 --name "Gate Header Field Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_hdrfield"
sed -i '0,/^## /s//**Dependencies:** CGT-9\n&/' "$f_gate_hdrfield"
gate_err="$(t close "$f_gate_hdrfield" 2>&1 >/dev/null || true)"
assert_contains "a header-region field-form line still refuses" "$gate_err" "unfinished named child task(s): CGT-9"

# The ^``` fence toggle rides the shared criteria counter: a fenced
# example box inside Success Criteria counts zero in both the closure
# gate and the lint, so close proceeds without --force and the closed
# file reports no unchecked-box advisory.
f_gate_fence="$(t new --id CGT-11 --name "Gate Fence Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_gate_fence"
t edit "$f_gate_fence" --section "Success Criteria" --append <<'IN' >/dev/null
Fenced example:

```
- [ ] example box, fenced
```
IN
TASKS_TEST_CLOCK="2026-06-16 09:30" t close "$f_gate_fence" >/dev/null
assert_eq "a fenced unticked example box does not block close" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_gate_fence")"
fence_lint="$(t lint --verbose 2>&1 || true)"
assert_not_contains "lint does not count the fenced box as unchecked" "$fence_lint" \
	"current/$(basename "$f_gate_fence"): Status Completed with 1 unchecked Success Criteria boxes"
rm -f "$f_gate" "$f_gate_child" "$f_gate_prose" "$f_gate_own" "$f_gate_parent" "$f_gate_field" "$f_gate_decl" "$f_gate_ready" "$f_gate_logfield" "$f_gate_sibling" "$f_gate_hdrfield" "$f_gate_fence"
t render >/dev/null

echo "== close: the ~ superseded annotation resolves unticked criteria =="
# A Success Criteria line marked '- ~ [ ] ' counts as resolved for the
# closure gate: close proceeds without --force and its Work Log entry
# lists the marked criteria as superseded, stamped at the closure clock
# so the elapsed Duration spans first anchor to closure. Plain unticked
# boxes still refuse, listing only themselves, and --force carries the
# superseded fragment in the override note.
f_tilde="$(t new --id TIL-1 --name "Superseded Annotation Probe")"
TASKS_TEST_CLOCK="2026-06-16 06:00" t log "$f_tilde" "only anchor" >/dev/null
sed -i 's/^- \[ \] TODO$/- ~ [ ] old criterion, superseded by the redesign/' "$f_tilde"
TASKS_TEST_CLOCK="2026-06-16 06:30" t close "$f_tilde" >/dev/null
assert_eq "a ~-marked file closes without --force" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_tilde")"
tilde_log="$(awk '/^## Work Log/{f=1} f' "$f_tilde")"
assert_contains "the close entry lists the superseded criteria" "$tilde_log" \
	"close: 1 superseded Success Criteria: old criterion, superseded by the redesign"
assert_eq "the superseded note anchor bounds the elapsed Duration" "30m" \
	"$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_tilde")"
f_tilde_mix="$(t new --id TIL-2 --name "Mixed Boxes Probe")"
sed -i 's/^- \[ \] TODO$/- ~ [ ] superseded criterion/' "$f_tilde_mix"
t edit "$f_tilde_mix" --section "Success Criteria" --append <<<"- [ ] still open criterion" >/dev/null
gate_err="$(t close "$f_tilde_mix" 2>&1 >/dev/null || true)"
assert_contains "mixed unticked and ~ criteria refuse" "$gate_err" "fails the closure gate"
assert_contains "the refusal counts only the unticked box" "$gate_err" "unchecked Success Criteria boxes: 1"
assert_not_contains "the refusal does not list the superseded criterion" "$gate_err" "superseded criterion"
refuse "mixed boxes refuse without --force" close "$f_tilde_mix"
TASKS_TEST_CLOCK="2026-06-16 07:00" t close "$f_tilde_mix" --force >/dev/null
mix_log="$(awk '/^## Work Log/{f=1} f' "$f_tilde_mix")"
assert_contains "the --force override lists the overridden finding" "$mix_log" "unchecked Success Criteria boxes: 1"
assert_contains "the --force override lists the superseded criteria" "$mix_log" "superseded Success Criteria: superseded criterion"
rm -f "$f_tilde" "$f_tilde_mix"
t render >/dev/null

echo "== close: verdict markers and the unverifiable gate =="
# The three-way verdict dimension rides the same shared criteria counter
# the gate and lint run: a Success Criteria line may carry (verdict:
# verified), (verdict: refuted), or (verdict: unverifiable), optionally
# with (exception: <text>) documenting on the same line why closure is
# acceptable without recorded evidence. The gate refuses a criterion
# whose unverifiable verdict lacks the documented exception (the
# mandatory-unverifiable class) and admits one that carries it; verified
# and refuted classify through the same counter without gate rules of
# their own. Fenced example markers count zero in both consumers, a
# verdict citation outside Success Criteria classifies as nothing, and
# plain-box files (no verdict tags) classify exactly as before.
f_vv="$(t new --id VVD-1 --name "Unverifiable Gate Probe")"
TASKS_TEST_CLOCK="2026-06-16 10:00" t log "$f_vv" "only anchor" >/dev/null
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_vv"
t edit "$f_vv" --section "Success Criteria" --append <<<"- [x] unestablishable claim (verdict: unverifiable)" >/dev/null
TASKS_TEST_CLOCK="2026-06-16 10:15" t log "$f_vv" "digest quoting (verdict: unverifiable) as prose" >/dev/null
vv_before="$(cat "$f_vv")"
vv_err="$(t close "$f_vv" 2>&1 >/dev/null || true)"
assert_contains "close refuses an unverifiable verdict without an exception" "$vv_err" "fails the closure gate"
assert_contains "the refusal names the unexcepted unverifiable criterion" "$vv_err" \
	"unverifiable Success Criteria verdict(s) without a documented exception: unestablishable claim (verdict: unverifiable)"
assert_not_contains "the refusal adds no unticked count for ticked criteria" "$vv_err" "unchecked Success Criteria boxes"
assert_not_contains "a Work Log prose citation of the verdict stays inert" "$vv_err" "digest quoting"
assert_eq "the refused verdict closure leaves the file byte-identical" "$vv_before" "$(cat "$f_vv")"
refuse "the verdict gate refuses without --force" close "$f_vv"
vv_out="$(TASKS_TEST_CLOCK="2026-06-16 10:30" t close "$f_vv" --force)"
assert_contains "close --force closes past the verdict gate" "$vv_out" "closed $(basename "$f_vv")"
vv_log="$(awk '/^## Work Log/{f=1} f' "$f_vv")"
assert_contains "the override note names the verdict finding" "$vv_log" \
	"unverifiable Success Criteria verdict(s) without a documented exception: unestablishable claim"

# The documented exception admits the closure: the same criterion with
# (exception: ...) on the line closes without --force.
f_vv_ok="$(t new --id VVD-2 --name "Excepted Verdict Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_vv_ok"
t edit "$f_vv_ok" --section "Success Criteria" --append \
	<<<"- [x] unestablishable claim (verdict: unverifiable) (exception: design-review sign-off recorded in the Decision Log)" >/dev/null
TASKS_TEST_CLOCK="2026-06-16 10:45" t close "$f_vv_ok" >/dev/null
assert_eq "the documented exception admits the closure" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_vv_ok")"

# Refuted and verified verdicts carry no gate rule of their own: a
# refuted claim left unticked refuses as a plain unticked box.
f_vv_ref="$(t new --id VVD-3 --name "Refuted Classification Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_vv_ref"
t edit "$f_vv_ref" --section "Success Criteria" --append <<<"- [ ] disproven claim (verdict: refuted)" >/dev/null
vv_err="$(t close "$f_vv_ref" 2>&1 >/dev/null || true)"
assert_contains "a refuted claim unticked refuses as a plain unticked box" "$vv_err" "unchecked Success Criteria boxes: 1"
assert_not_contains "the refuted verdict adds no gate finding of its own" "$vv_err" "verdict(s) without a documented exception"

# The verdict dimension is box-state-agnostic: a ~-superseded criterion
# carrying an unexcepted unverifiable verdict refuses too, and the
# finding names it stripped of the superseded marker prefix.
f_vv_sup="$(t new --id VVD-5 --name "Superseded Verdict Probe")"
sed -i 's/^- \[ \] TODO$/- ~ [ ] replaced claim (verdict: unverifiable)/' "$f_vv_sup"
vv_err="$(t close "$f_vv_sup" 2>&1 >/dev/null || true)"
assert_contains "a superseded criterion with an unexcepted unverifiable verdict refuses" "$vv_err" "fails the closure gate"
assert_contains "the verdict finding strips the superseded marker prefix" "$vv_err" \
	"unverifiable Success Criteria verdict(s) without a documented exception: replaced claim (verdict: unverifiable)"
assert_not_contains "the superseded verdict finding adds no unticked count" "$vv_err" "unchecked Success Criteria boxes"

# Fenced example verdict markers count zero in the gate and the lint.
f_vv_fence="$(t new --id VVD-4 --name "Verdict Fence Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_vv_fence"
t edit "$f_vv_fence" --section "Success Criteria" --append <<'IN' >/dev/null
Example markers:

```
- [ ] fenced example (verdict: unverifiable)
- [x] fenced established example (verdict: verified)
```
IN
TASKS_TEST_CLOCK="2026-06-16 11:15" t close "$f_vv_fence" >/dev/null
assert_eq "fenced verdict markers do not block close" "Completed" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_vv_fence")"
vv_lint="$(t lint --verbose 2>&1 || true)"
assert_not_contains "lint reports no drift for the fenced verdict criteria" "$vv_lint" "$(basename "$f_vv_fence")"

# Gate and lint classify through the ONE shared counter: the same body's
# counts agree across the gate's refusal findings (close leg, Status
# untouched) and the lint's advisories (lint leg, the same file hand-set
# Completed the way the lint section's direct fixtures are).
f_vv_agree="$(t new --id VVA-1 --name "Verdict Agreement Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_vv_agree"
t edit "$f_vv_agree" --section "Success Criteria" --append <<'IN' >/dev/null
- [x] verified claim (verdict: verified)
- [x] unestablishable claim (verdict: unverifiable)
- [x] disproven claim (verdict: refuted)
- [ ] open claim
IN
vv_err="$(t close "$f_vv_agree" 2>&1 >/dev/null || true)"
assert_contains "the gate counts the unticked box" "$vv_err" "unchecked Success Criteria boxes: 1"
assert_contains "the gate counts the unexcepted unverifiable verdict" "$vv_err" \
	"unverifiable Success Criteria verdict(s) without a documented exception: unestablishable claim (verdict: unverifiable)"
assert_not_contains "the gate states no refuted finding" "$vv_err" "refuted"
sed -i 's/^\*\*Status:.*/**Status:** Completed/' "$f_vv_agree"
vv_lint="$(t lint --verbose 2>&1 || true)"
assert_contains "lint counts the same unchecked box" "$vv_lint" \
	"ADVISORY current/$(basename "$f_vv_agree"): Status Completed with 1 unchecked Success Criteria boxes"
assert_contains "lint counts the same refuted verdict" "$vv_lint" \
	"ADVISORY current/$(basename "$f_vv_agree"): Status Completed with 1 refuted Success Criteria verdict(s)"
assert_contains "lint counts the same unverifiable verdict" "$vv_lint" \
	"ADVISORY current/$(basename "$f_vv_agree"): Status Completed with 1 unverifiable Success Criteria verdict(s) without a documented exception"
assert_not_contains "a verified verdict reports no drift anywhere" "$vv_lint" \
	"$(basename "$f_vv_agree"): Status Completed with 1 verified Success"

# The open-file nudge splits on the exception state: an all-checked open
# file with an unexcepted unverifiable gets the corrected refusal nudge
# instead of the closure nudge the gate would refuse, and documenting the
# exception restores the plain closure nudge.
f_vv_nudge="$(t new --id VVN-1 --name "Verdict Nudge Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO (verdict: unverifiable)/' "$f_vv_nudge"
vv_lint="$(t lint --verbose 2>&1 || true)"
assert_contains "the open all-checked nudge names the unverifiable block" "$vv_lint" \
	"ADVISORY current/$(basename "$f_vv_nudge"): all 1 Success Criteria boxes checked while Triage, but 1 unverifiable verdict(s) lack documented exceptions (closure refuses)"
assert_not_contains "the plain closure nudge stays silent while the block stands" "$vv_lint" \
	"$(basename "$f_vv_nudge"): all 1 Success Criteria boxes checked while Triage (closure is 'tasks close')"
sed -i 's/(verdict: unverifiable)/(verdict: unverifiable) (exception: recorded sign-off)/' "$f_vv_nudge"
vv_lint="$(t lint --verbose 2>&1 || true)"
assert_contains "the exception restores the plain closure nudge" "$vv_lint" \
	"ADVISORY current/$(basename "$f_vv_nudge"): all 1 Success Criteria boxes checked while Triage (closure is 'tasks close')"
rm -f "$f_vv" "$f_vv_ok" "$f_vv_ref" "$f_vv_sup" "$f_vv_fence" "$f_vv_agree" "$f_vv_nudge"
t render >/dev/null

echo "== archive: terminal tasks move to archive/ =="
# The sanctioned alternative to the hand mv the battery's earlier archive
# lane tests used: archive refuses open tasks, moves a terminal one under
# the lock, drops any claim sidecar on the way, and re-renders. Reports
# deposited before and after the move share one reports dir keyed by the
# preserved basename, so every ../reports/ link keeps resolving.
f_ar="$(t new --id ARC-1 --name "Archive Move Target")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_ar"
ar_err="$(t archive "$f_ar" 2>&1 >/dev/null || true)"
refuse "archive refuses a non-terminal task" archive "$f_ar"
assert_contains "archive refusal names the closure path" "$ar_err" "use 'tasks close'"
TASKS_TEST_CLOCK="2026-06-16 09:00" t close "$f_ar" >/dev/null
printf 'pre-archive report body\n' | t report "$f_ar" --slug pre-archive --digest "before the move" >/dev/null
ar_out="$(t archive "$f_ar")"
assert_contains "archive reports the moved file" "$ar_out" "$(basename "$f_ar")"
[[ -f "$TASKS_DIR/archive/$(basename "$f_ar")" ]] && ok "the archived file lives in archive/" || bad "the archived file lives in archive/"
[[ ! -e "$f_ar" ]] && ok "current/ no longer carries the file" || bad "current/ no longer carries the file"
[[ ! -f "$TASKS_DIR/archive/$(basename "$f_ar").claim" ]] && ok "no claim sidecar travels to archive/" || bad "no claim sidecar travels to archive/"
arch_lane="$(awk '/^## Archive/{f=1} f' <"$DASH")"
assert_contains "the Archive lane renders the moved task" "$arch_lane" "(./archive/$(basename "$f_ar"))"
comp_lane="$(awk '/^## Completed/{f=1} /^## Archive/{f=0} f' <"$DASH")"
assert_not_contains "the Completed lane drops the moved task" "$comp_lane" "Archive Move Target"
printf 'post-archive report body\n' | t report "$TASKS_DIR/archive/$(basename "$f_ar")" --slug post-archive --digest "after the move" >/dev/null
[[ -f "$TASKS_DIR/reports/$(basename "$f_ar")/02-post-archive.md" ]] \
	&& ok "post-archive report deposits under the same reports dir" || bad "post-archive report deposits under the same reports dir"
assert_contains "the archived file links the post-archive report" \
	"$(cat "$TASKS_DIR/archive/$(basename "$f_ar")")" "(../reports/$(basename "$f_ar")/02-post-archive.md)"
refuse "archive refuses an already-archived task" archive "$TASKS_DIR/archive/$(basename "$f_ar")"
refuse "archive refuses an unknown task file" archive NOPE-9.md
refuse "archive without a taskfile is refused" archive
f_ar2="$(t new --id ARC-2 --name "Archive Claim Drop")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_ar2"
t close "$f_ar2" >/dev/null
printf 'sess-ghost\n' >"$f_ar2.claim"
t archive "$f_ar2" >/dev/null
[[ ! -f "$TASKS_DIR/archive/$(basename "$f_ar2").claim" ]] && ok "archive drops a stale claim sidecar" || bad "archive drops a stale claim sidecar"
f_ar3="$(t new --id ARC-3 --name "Archive Cancelled Target")"
t set "$f_ar3" Status=Cancelled "Status Reason=archive probe" >/dev/null
t archive "$f_ar3" >/dev/null
[[ -f "$TASKS_DIR/archive/$(basename "$f_ar3")" ]] && ok "a Cancelled task archives" || bad "a Cancelled task archives"
assert_contains "the Archive lane renders the cancelled task too" "$(awk '/^## Archive/{f=1} f' <"$DASH")" "Archive Cancelled Target"
rm -f "$TASKS_DIR/archive/"ARC-*.md
rm -rf "$TASKS_DIR/reports/$(basename "$f_ar")"
t render >/dev/null

echo "== close --cancelled: terminal-transition symmetry =="
# G17: Cancelled files get the same CLI-stamped closure semantics as
# Completed ones, through close's second path, so neither terminal status
# carries hand-derived closure data. Both paths are pinned here and in the
# close/stamp section above: plain close stamps Completed+Duration+Updated,
# close --cancelled stamps Duration+Updated with no Completed field.
f_cc="$(t new --id CCX-1 --name "Cancelled Closure Probe")"
TASKS_TEST_CLOCK="2026-06-15 09:00" t log "$f_cc" "first anchor" >/dev/null
TASKS_TEST_CLOCK="2026-06-15 11:00" t log "$f_cc" "second anchor" >/dev/null
t set "$f_cc" Status=Blocked "Status Reason=waiting on requeue" >/dev/null
t claim "$f_cc" --owner sess-cancel >/dev/null
cc_out="$(TASKS_TEST_CLOCK="2026-06-16 10:00" t close "$f_cc" --cancelled)"
assert_contains "close --cancelled reports the cancellation" "$cc_out" "cancelled $(basename "$f_cc")"
assert_contains "close --cancelled reports the derived duration" "$cc_out" "Duration 2h"
assert_eq "close --cancelled stamps Status Cancelled" "Cancelled" "$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_cc")"
assert_eq "close --cancelled derives Duration from the anchors" "2h" "$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_cc")"
assert_eq "close --cancelled refreshes Updated from the clock" "2026-06-16 10:00" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_cc")"
assert_not_contains "close --cancelled stamps no Completed field" "$(awk '/^## /{exit}{print}' "$f_cc")" "**Completed:**"
assert_contains "close --cancelled keeps the Status Reason" "$(awk '/^## /{exit}{print}' "$f_cc")" "**Status Reason:** waiting on requeue"
[[ ! -f "$f_cc.claim" ]] && ok "close --cancelled releases the claim" || bad "close --cancelled releases the claim"
assert_eq "close --cancelled leaves Owner present and empty" "1" "$(grep -c '^\*\*Owner:\*\*$' "$f_cc")"
cc_lane="$(awk '/^## Blocked\/Cancelled/{f=1} /^## Completed/{f=0} f' <"$DASH")"
assert_contains "the cancelled closure renders in Blocked/Cancelled" "$cc_lane" "Cancelled Closure Probe"
refuse "close --cancelled refuses an already-Cancelled task" close "$f_cc" --cancelled
refuse "close --cancelled refuses a Completed task" close "$f_cl" --cancelled
cc_upd_before="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_cc")"
refuse "refused --cancelled calls leave no trace" close "$f_cc" --cancelled
assert_eq "the refused --cancelled keeps Updated untouched" "$cc_upd_before" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_cc")"

# The coupling close --cancelled enforces: cancelling a task that never
# carried a Status Reason is refused before any write (the header
# contract ties the reason to Blocked/Cancelled), naming the sanctioned
# route; a refused call leaves the file byte-identical. The reason reuse
# on the success path is pinned above (waiting on requeue survives).
f_cn="$(t new --id CCX-2 --name "Cancelled Reason Refusal Probe")"
cn_before="$(cat "$f_cn")"
cn_err="$(t close "$f_cn" --cancelled 2>&1 >/dev/null || true)"
assert_contains "close --cancelled refuses a task with no Status Reason" "$cn_err" \
	"requires a non-empty Status Reason"
assert_contains "the refusal names the sanctioned route" "$cn_err" \
	"set Status=Blocked with one first"
refuse "close --cancelled without a reason exits nonzero" close "$f_cn" --cancelled
assert_eq "the refused cancellation leaves the file byte-identical" "$cn_before" "$(cat "$f_cn")"
rm -f "$f_cn"
t render >/dev/null
rm -f "$f_cc"
t render >/dev/null

echo "== stamp --repair: malformed CLI-owned fields get a CLI route back =="
# The MGR-11 class: a malformed Latest Update left a file no CLI write
# could repair (log refreshes Updated but not Latest Update, set refuses
# the field). --repair re-stamps the stamped timeline in one locked
# write: Updated and Duration from clock and anchors, Latest Update as a
# dated line naming the tool that wrote it, Completed per the file's
# status (deleted on an open task, where absence is canonical).
f_rpr="$(t new --id RPR-1 --name "Repair Probe Target")"
TASKS_TEST_CLOCK="2026-06-15 09:00" t log "$f_rpr" "anchor one" >/dev/null
TASKS_TEST_CLOCK="2026-06-15 09:30" t log "$f_rpr" "anchor two" >/dev/null
sed -i 's/^\*\*Latest Update:.*/**Latest Update:** hand-mangled garbage/' "$f_rpr"
sed -i 's/^\*\*Updated:.*/**Updated:** 2026-06-15/' "$f_rpr"
sed -i '/^\*\*Updated:/a **Completed:** 2026-06-15 00:00' "$f_rpr"
rep_out="$(TASKS_TEST_CLOCK="2026-06-16 08:00" t stamp "$f_rpr" --repair)"
assert_contains "repair reports the repaired file" "$rep_out" "repaired $(basename "$f_rpr")"
assert_eq "repair re-stamps Updated to the clock" "2026-06-16 08:00" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_rpr")"
assert_contains "repair rewrites Latest Update as a dated repair line" \
	"$(grep -oP '^\*\*Latest Update:\*\*\s+\K.*' "$f_rpr")" \
	"[2026-06-16 08:00] CLI-owned header repaired via 'tasks stamp --repair'"
assert_eq "repair derives Duration from the anchors" "30m" "$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_rpr")"
assert_eq "repair on an open task deletes the stray Completed field" "0" "$(grep -c '^\*\*Completed:\*\*' "$f_rpr")"
assert_eq "repair keeps the canonical header order" \
	"$(printf '%s\n' Created Status Priority Progress Owner Updated Duration "Latest Update")" \
	"$(awk '/^## /{exit} {if (match($0, /^\*\*[^*:]+:\*\*/)) print substr($0, RSTART+2, RLENGTH-5)}' "$f_rpr")"
refuse "plain stamp still refuses an open task" stamp "$f_rpr"
rm -f "$f_rpr"

# Repair is scoped to the fields that actually fail their canonical
# shape: a repair triggered by a mangled Updated leaves a valid
# hand-curated Latest Update byte-identical, a mangled Duration re-derives
# alone, and a missing Completed re-stamps alone, each leaving the
# well-formed siblings untouched; a clean file reports nothing to repair
# without a write.
f_sc="$(t new --id RPR-2 --name "Repair Scope Probe")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_sc"
TASKS_TEST_CLOCK="2026-06-15 09:00" t log "$f_sc" "anchor one" >/dev/null
TASKS_TEST_CLOCK="2026-06-15 11:00" t log "$f_sc" "anchor two" >/dev/null
sed -i 's/^\*\*Updated:.*/**Updated:** not a stamp/' "$f_sc"
sc_lu="$(grep -oP '^\*\*Latest Update:\*\*\s+\K.*' "$f_sc")"
sc_out="$(TASKS_TEST_CLOCK="2026-06-16 08:00" t stamp "$f_sc" --repair)"
assert_contains "scoped repair names only the fields it rewrote" "$sc_out" "(Updated Duration)"
assert_eq "a repair triggered by a mangled Updated re-stamps it" "2026-06-16 08:00" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_sc")"
assert_eq "a valid Latest Update survives the repair untouched" "$sc_lu" "$(grep -oP '^\*\*Latest Update:\*\*\s+\K.*' "$f_sc")"
TASKS_TEST_CLOCK="2026-06-16 09:00" t close "$f_sc" >/dev/null
sed -i 's/^\*\*Duration:.*/**Duration:** garbage/' "$f_sc"
sc_out="$(TASKS_TEST_CLOCK="2026-06-16 10:00" t stamp "$f_sc" --repair)"
assert_contains "a repair triggered by a mangled Duration names only it" "$sc_out" "(Duration)"
assert_eq "a mangled Duration re-derives from the anchors" "2h" "$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_sc")"
assert_eq "the Duration repair leaves the close stamps alone" "2026-06-16 09:00" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_sc")"
sc_upd="$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_sc")"
sed -i '/^\*\*Completed:/d' "$f_sc"
sc_out="$(TASKS_TEST_CLOCK="2026-06-16 11:00" t stamp "$f_sc" --repair)"
assert_contains "a missing Completed on a Completed task is the only repair" "$sc_out" "(Completed)"
assert_eq "repair re-stamps the missing Completed from the clock" "2026-06-16 11:00" "$(grep -oP '^\*\*Completed:\*\*\s+\K.*' "$f_sc")"
assert_eq "the Completed re-stamp leaves a valid Updated untouched" "$sc_upd" "$(grep -oP '^\*\*Updated:\*\*\s+\K.*' "$f_sc")"
sc_before="$(cat "$f_sc")"
sc_out="$(t stamp "$f_sc" --repair)"
assert_contains "a clean file reports nothing to repair" "$sc_out" "nothing to repair in $(basename "$f_sc")"
assert_eq "the nothing-to-repair pass leaves the file byte-identical" "$sc_before" "$(cat "$f_sc")"
rm -f "$f_sc"

f_rpc="$(t new --id RPR-2 --name "Repair Completed Target")"
sed -i 's/^- \[ \] TODO$/- [x] TODO/' "$f_rpc"
TASKS_TEST_CLOCK="2026-06-15 08:00" t log "$f_rpc" "first anchor" >/dev/null
TASKS_TEST_CLOCK="2026-06-15 09:00" t log "$f_rpc" "second anchor" >/dev/null
TASKS_TEST_CLOCK="2026-06-15 09:00" t close "$f_rpc" >/dev/null
sed -i 's/^\*\*Latest Update:.*/**Latest Update:** broken/' "$f_rpc"
sed -i 's/^\*\*Completed:.*/**Completed:** garbage/' "$f_rpc"
TASKS_TEST_CLOCK="2026-06-17 07:00" t stamp "$f_rpc" --repair >/dev/null
assert_eq "repair on a Completed task re-stamps Completed" "2026-06-17 07:00" "$(grep -oP '^\*\*Completed:\*\*\s+\K.*' "$f_rpc")"
assert_contains "repair on a Completed task fixes Latest Update too" \
	"$(grep -oP '^\*\*Latest Update:\*\*\s+\K.*' "$f_rpc")" "repaired via 'tasks stamp --repair'"
assert_eq "repair on a Completed task keeps Duration derived" "1h" "$(grep -oP '^\*\*Duration:\*\*\s+\K.*' "$f_rpc")"
refuse "repair without a taskfile is refused" stamp --repair
rm -f "$f_rpc"
t render >/dev/null

 echo "== usage: canonical option order =="
usage_out="$(t help)"
assert_contains "usage places --from between --slug and --digest" "$usage_out" \
	"--slug SLUG [--from WORKER] --digest TEXT"
assert_not_contains "usage does not place --from after --digest" "$usage_out" \
	"--digest TEXT [--from"
assert_contains "usage places --append after --section" "$usage_out" \
	"--section HEADING [--append] [<file>|-]"
assert_not_contains "usage does not place --append before --section" "$usage_out" \
	"--append] --section"

echo "== canonical-root guard (fallback root: writes refuse, reads warn) =="
# The guard fixture must sit OUTSIDE the battery root's chain: walk-up from
# anywhere under ROOT finds the battery board, so a sibling temp root whose
# ancestors carry no board is what puts the CLI in bare-fallback territory
# (a host with a board at /tmp or / would fail these probes loudly). Probes
# run inside command substitutions; every assert runs in the parent because
# the harness counters are in-process and a subshell assert is lost. The
# subshells also unset the pinned clock: a TASKS_TEST_CLOCK export without
# TASKS_DIR dies at startup under the clock's co-gate, which would mask
# the fallback behavior under test.
guard_root="$(mktemp -d)"
guard_board="$guard_root/.tasks"
trap 'rm -rf "$ROOT" "$guard_root"' EXIT

refuse_err="$( cd "$guard_root" && unset TASKS_DIR TASKS_TEST_CLOCK && t new --id GRD-1 --name "Fallback Refusal Probe" </dev/null 2>&1 >/dev/null || true )"
assert_contains "new refuses the bare fallback root" "$refuse_err" "refusing to write to the bare ./.tasks fallback"
assert_contains "fallback refusal carries the pin remediation" "$refuse_err" "pass --dir, export TASKS_DIR"
set_err="$( cd "$guard_root" && unset TASKS_DIR TASKS_TEST_CLOCK && t set nosuchfile.md Progress=5% </dev/null 2>&1 >/dev/null || true )"
assert_contains "set refuses the bare fallback root" "$set_err" "refusing to write to the bare ./.tasks fallback"
log_err="$( cd "$guard_root" && unset TASKS_DIR TASKS_TEST_CLOCK && t log nosuchfile.md "guard probe message" </dev/null 2>&1 >/dev/null || true )"
assert_contains "log refuses the bare fallback root" "$log_err" "refusing to write to the bare ./.tasks fallback"
report_err="$( cd "$guard_root" && unset TASKS_DIR TASKS_TEST_CLOCK && t report nosuchfile.md --slug guard-probe --digest "probe" </dev/null 2>&1 >/dev/null || true )"
assert_contains "report refuses the bare fallback root" "$report_err" "refusing to write to the bare ./.tasks fallback"
init_err="$( cd "$guard_root" && unset TASKS_DIR TASKS_TEST_CLOCK && t init </dev/null 2>&1 >/dev/null || true )"
assert_contains "init refuses to scaffold the bare fallback root" "$init_err" "refusing to write to the bare ./.tasks fallback"
[[ -e "$guard_root/.tasks" ]] && bad "refused probes leave no fallback root behind" || ok "refused probes leave no fallback root behind"

render_err="$( cd "$guard_root" && unset TASKS_DIR TASKS_TEST_CLOCK && t render </dev/null 2>&1 >/dev/null || true )"
assert_contains "render warns on the bare fallback root" "$render_err" "warning: no board found walking up from"
assert_contains "render keeps the missing-board die on the fallback root" "$render_err" "no .tasks directory"
show_err="$( cd "$guard_root" && unset TASKS_DIR TASKS_TEST_CLOCK && t show nosuchfile.md </dev/null 2>&1 >/dev/null || true )"
assert_contains "show warns on the bare fallback root" "$show_err" "warning: no board found walking up from"
assert_contains "show keeps the missing-board die on the fallback root" "$show_err" "no .tasks directory"

# The accepted pins, probed in the same walk-up-empty territory: explicit
# --dir, exported TASKS_DIR, and the upward find each let writes through.
t init --dir "$guard_board" >/dev/null
flag_file="$(t new --id GRD-2 --name "Flag Pin Probe" --dir "$guard_board")"
[[ -f "$flag_file" ]] && ok "write lands under an explicit --dir pin" || bad "write lands under an explicit --dir pin"
env_file="$( TASKS_DIR="$guard_board"; t new --id GRD-3 --name "Env Pin Probe" )"
[[ -f "$env_file" ]] && ok "write lands under a TASKS_DIR pin" || bad "write lands under a TASKS_DIR pin"
mkdir "$guard_root/nested"
walk_file="$( cd "$guard_root/nested" && unset TASKS_DIR TASKS_TEST_CLOCK && t new --id GRD-4 --name "Walk-up Probe" )"
[[ -f "$walk_file" ]] && ok "write walks up to the found board" || bad "write walks up to the found board"
assert_contains "walk-up write lands in the walked-up board" "$walk_file" "$guard_board/"
walk_show_err="$( cd "$guard_root/nested" && unset TASKS_DIR TASKS_TEST_CLOCK && t show "$(basename "$walk_file")" </dev/null 2>&1 >/dev/null )"
assert_eq "walk-up read succeeds" "0" "$?"
assert_not_contains "walk-up read emits no fallback warning" "$walk_show_err" "warning:"

echo "== resolve: task file arguments are contained to the board root =="
# resolve_task_file admits bare names, in-board paths, and archive paths,
# but every existing-file candidate must resolve inside the resolved board
# root (readlink -f, so traversal and symlinks cannot smuggle a write past
# a string prefix). Explicit --dir boards and relative in-board paths keep
# working: containment compares resolved paths, not spellings.
f_ctn="$(t new --id CTN-1 --name "Containment Probe")"
refuse "a nonexistent path outside the board is not found" show "$ROOT/outside.md"
printf 'not a task file\n' >"$ROOT/outside.md"
ctn_err="$(t show "$ROOT/outside.md" 2>&1 >/dev/null || true)"
refuse "an existing file outside the board root is refused" show "$ROOT/outside.md"
assert_contains "the containment refusal names the board root" "$ctn_err" "escapes the board root"
ctn_err="$(t show "$TASKS_DIR/current/../../outside.md" 2>&1 >/dev/null || true)"
refuse "traversal escaping the board root is refused" show "$TASKS_DIR/current/../../outside.md"
assert_contains "the traversal refusal resolves the real path" "$ctn_err" "resolves to"
ln -s "$ROOT/outside.md" "$TASKS_DIR/current/escape.md"
refuse "a symlink pointing outside the board is refused" show "$TASKS_DIR/current/escape.md"
rm -f "$TASKS_DIR/current/escape.md" "$ROOT/outside.md"
f_ctn2="$(t new --id CTN-2 --name "Traversal Probe")"
mv "$f_ctn2" "$TASKS_DIR/archive/"
t show "$TASKS_DIR/current/../archive/$(basename "$f_ctn2")" >/dev/null \
	&& ok "in-board traversal remains readable" || bad "in-board traversal remains readable"
( cd "$TASKS_DIR" && t show "current/$(basename "$f_ctn")" ) >/dev/null \
	&& ok "a relative in-board path remains readable" || bad "a relative in-board path remains readable"
rm -f "$f_ctn" "$TASKS_DIR/archive/$(basename "$f_ctn2")"
t render >/dev/null

# --- versioned JSON readers (ORCH-4-4-2) -----------------------------------

# Test-local JSON string decoder for the emitters' own escape set (the
# reverse of the CLI's json_escape: backslash escapes, named controls, and
# \u00XX). Keeps the round-trip proofs self-contained so a decoder bug
# cannot fail silently; the one place an independent parser is required is
# the live-shape parse gate below, which pipes a full payload through
# python3 or jq exactly because the local decoder shares the emitters'
# escape set and could mirror an emitter bug.
readonly RDR_HEX="0123456789abcdef"
rdr_unesc() { # JSON-escaped string content on stdin; prints the raw text
	awk -v hexd="$RDR_HEX" '
		function hexv(c) { return index(hexd, tolower(c)) - 1 }
		{
			s = $0; out = ""; n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (c != "\\") { out = out c; continue }
				i++; c = substr(s, i, 1)
				if (c == "n") out = out "\n"
				else if (c == "r") out = out "\r"
				else if (c == "t") out = out "\t"
				else if (c == "b") out = out "\b"
				else if (c == "f") out = out "\f"
				else if (c == "u") {
					code = hexv(substr(s, i + 1, 1)) * 4096 + hexv(substr(s, i + 2, 1)) * 256 \
						+ hexv(substr(s, i + 3, 1)) * 16 + hexv(substr(s, i + 4, 1))
					out = out sprintf("%c", code)
					i += 4
				}
				else out = out c
			}
			printf "%s", out
		}
	'
}
# Extract one top-level or nested string field ("key":"...") from a compact
# JSON line, honoring backslash escapes; prints the ESCAPED content. The
# payload rides the environment, not awk -v: -v escape-processes backslash
# sequences and would corrupt the very bytes this scanner decodes.
rdr_jfield() { # line key
	line="$1" key="$2" awk '
		BEGIN {
			line = ENVIRON["line"]; key = ENVIRON["key"]
			pre = "\"" key "\":\""
			pos = index(line, pre)
			if (pos == 0) { print "@MISSING@"; exit }
			rest = substr(line, pos + length(pre))
			n = length(rest)
			for (i = 1; i <= n; i++) {
				c = substr(rest, i, 1)
				if (c == "\\") { out = out c substr(rest, i + 1, 1); i++; continue }
				if (c == "\"") { print out; exit }
				out = out c
			}
			print "@UNTERMINATED@"
		}
	'
}
# List the top-level keys of a compact JSON object line, in order. Same
# environment transport as rdr_jfield, and bracket-aware: nested objects and
# arrays (and commas inside strings) must never surface as keys.
rdr_topkeys() { # line
	line="$1" awk '
		BEGIN {
			line = ENVIRON["line"]
			depth = 0; inq = 0; esc = 0; buf = ""; nk = 0; keydone = 0
			n = length(line)
			for (i = 1; i <= n; i++) {
				c = substr(line, i, 1)
				if (esc) { esc = 0; if (!keydone && depth == 1) buf = buf c; continue }
				if (inq) {
					if (c == "\\") { esc = 1; if (!keydone && depth == 1) buf = buf c; continue }
					if (c == "\"") inq = 0
					if (!keydone && depth == 1) buf = buf c
					continue
				}
				if (c == "\"") { inq = 1; if (!keydone && depth == 1) buf = buf c; continue }
				if (c == "{" || c == "[") { depth++; continue }
				if (c == "}" || c == "]") { depth--; if (depth == 0) break; continue }
				if (depth == 1 && c == ":" && !keydone) { keys[++nk] = buf; keydone = 1; continue }
				if (depth == 1 && c == ",") { buf = ""; keydone = 0; continue }
				if (!keydone && depth == 1) buf = buf c
			}
			for (i = 1; i <= nk; i++) print keys[i]
		}
	'
}

echo "== show: --json schema pin and read completeness =="
# Dedicated board: the pinned fixture corpus carries the shapes read
# completeness must survive (nested deeper headings, fenced marker text
# inside a body, an unknown section, verdict markers, quote/backslash/unicode
# values, an archived task, a claim sidecar). The corpus itself is written
# directly: the readers are the subject under test, not the write path.
rdr_dir="$ROOT/rdr/.tasks"
t init --dir "$rdr_dir" >/dev/null
rdr_board="$rdr_dir/dashboard.md"
cat >"$rdr_dir/current/FIX-1-20260615-1200-reader-fixture.md" <<'FIXEOF'
# Task: Reader Fixture

**Created:** 2026-06-15 12:00
**Status:** In Progress
**Priority:** High
**Progress:** 40%
**Owner:** fixture-owner
**Updated:** 2026-06-15 12:30
**Latest Update:** [2026-06-15 12:30] fixture digest

## Table of Contents

- [Objective](#objective)

---

## Objective

Top objective text with "quotes" and \backslash and cafe-lambda unicode

### Sub approach

nested content under a deeper heading
more nested text

## Success Criteria

- [x] landed criterion
- [ ] open criterion
- ~ [ ] superseded note

```
- [ ] fenced box counts nowhere
### fenced deep heading stays body
```

## Mystery Section

unknown section body
line two with "quoted pipes"

## Work Log

### 2026-06-15 12:00: planner: created fixture

entry body with
"quote" and \backslash

### 2026-06-15 12:30: worker: second entry

second body

## Execution Log

- 2026-06-15 12:00 - fixture created
FIXEOF
cat >"$rdr_dir/archive/FIX-2-20260615-0900-archived-fixture.md" <<'FIXEOF'
# Task: Archived Fixture

**Created:** 2026-06-15 09:00
**Status:** Completed
**Priority:** Low
**Progress:** 100%
**Owner:**
**Updated:** 2026-06-15 10:00
**Completed:** 2026-06-15 10:00
**Duration:** 1h

## Objective

archived body

## Success Criteria

- [x] done

## Work Log

## Execution Log

- 2026-06-15 10:00 - archived
FIXEOF
f_rdr1="$rdr_dir/current/FIX-1-20260615-1200-reader-fixture.md"
TASKS_SESSION=sess-fix t claim --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md >/dev/null
rdr_json="$(t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json)"
assert_contains "show --json carries the schema_version 1 marker" "$rdr_json" '{"schema_version":1,'
assert_eq "show --json top-level keys are exactly the documented set" \
	'"schema_version" "type" "id" "file" "archived" "header" "sections" "work_log"' \
	"$(rdr_topkeys "$rdr_json" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "show --json pins the task id from the filename" "FIX-1" "$(rdr_jfield "$rdr_json" id)"
assert_eq "show --json pins the board-relative file" "current/FIX-1-20260615-1200-reader-fixture.md" "$(rdr_jfield "$rdr_json" file)"
assert_contains "show --json header carries the logical Status" "$rdr_json" '"Status":"In Progress"'
assert_contains "show --json header carries Progress verbatim" "$rdr_json" '"Progress":"40%"'
assert_contains "show --json header carries the claim Owner" "$rdr_json" '"Owner":"sess-fix"'
assert_contains "show --json header carries an absent field as empty" "$rdr_json" '"Checkpoint Gating":""'
rdr_headings="$(printf '%s' "$rdr_json" | grep -o '"heading":"[^"]*"' | tr '\n' ' ')"
rdr_headings="${rdr_headings% }"
assert_contains "show --json carries every section in file order" "$rdr_headings" \
	"$(printf '"heading":"Table of Contents" "heading":"Objective" "heading":"Success Criteria" "heading":"Mystery Section" "heading":"Work Log" "heading":"Execution Log"')"
assert_contains "show --json body carries the nested deeper heading" "$rdr_json" '### Sub approach\n\nnested content'
assert_contains "show --json body carries the fenced deep heading as body" "$rdr_json" '### fenced deep heading stays body'
assert_contains "show --json body carries the unknown section" "$rdr_json" 'unknown section body'
assert_contains "show --json escapes quotes in body text" "$rdr_json" 'with \"quotes\" and'
assert_contains "show --json escapes backslashes in body text" "$rdr_json" '\\backslash'
assert_contains "show --json passes unicode through byte-for-byte" "$rdr_json" 'cafe-lambda unicode'
assert_contains "show --json structures work log entries" "$rdr_json" '"stamp":"2026-06-15 12:00","title":"planner: created fixture"'
assert_contains "show --json structures the newest entry last" "$rdr_json" '"stamp":"2026-06-15 12:30","title":"worker: second entry"'
assert_eq "show --json pins the entry count" "2" "$(printf '%s' "$rdr_json" | grep -o '"stamp":"' | wc -l)"
rdr_arch="$(t show --dir "$rdr_dir" FIX-2-20260615-0900-archived-fixture.md --json)"
assert_contains "show --json marks archived tasks" "$rdr_arch" '"archived":true'
rdr_json2="$(t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json)"
assert_eq "show --json is byte-stable across runs" "$rdr_json" "$rdr_json2"

# Independent-parser gate over the full current fixture: json.load refuses
# trailing data, so the verifier's live-file class (one complete value
# followed by an unmatched closing brace) fails here even though the local
# decoder above tolerates it. python3 first, jq fallback, and neither
# parser present is a failed check, not a skip: the gate must run.
rdr_live="$(t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json)"
if command -v python3 >/dev/null 2>&1; then
	if printf '%s\n' "$rdr_live" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null; then
		ok "show --json parses as one complete JSON document (python3)"
	else
		bad "show --json parses as one complete JSON document (python3)"
	fi
elif command -v jq >/dev/null 2>&1; then
	if printf '%s\n' "$rdr_live" | jq -e . >/dev/null 2>&1; then
		ok "show --json parses as one complete JSON document (jq)"
	else
		bad "show --json parses as one complete JSON document (jq)"
	fi
else
	bad "no independent JSON parser on the host (python3 nor jq)"
fi

echo "== show: --section canonical body and --raw hatch =="
rdr_sec="$(t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section Objective)"
assert_eq "show --section prints the canonical body byte-exact" \
	"$(printf 'Top objective text with "quotes" and \\backslash and cafe-lambda unicode\n\n### Sub approach\n\nnested content under a deeper heading\nmore nested text')" \
	"$rdr_sec"
assert_eq "show --section addresses a deeper heading like edit" \
	"$(printf 'nested content under a deeper heading\nmore nested text')" \
	"$(t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section 'Sub approach')"
refuse "show --section refuses an unknown section" show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section Nope
rdr_sec_err="$(t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section Nope 2>&1 >/dev/null || true)"
assert_contains "the section refusal carries SECTION_NOT_FOUND" "$rdr_sec_err" "(code: SECTION_NOT_FOUND)"
rdr_secjson="$(t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section Objective --json)"
assert_contains "show --json --section wraps the canonical body" "$rdr_secjson" '{"schema_version":1,"type":"section","file":"current/FIX-1'
assert_contains "show --json --section pins the heading and level" "$rdr_secjson" '"heading":"Objective","level":2'
assert_eq "show --json --section body equals the text mode" \
	"$rdr_sec" "$(rdr_jfield "$rdr_secjson" body | rdr_unesc)"
refuse "show refuses --json with --tail" show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json --tail 3
refuse "show refuses --raw with --json" show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --raw --json
refuse "show refuses --raw with --section" show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --raw --section Objective
refuse "show refuses --raw with --tail" show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --raw --tail 3
t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --raw >"$ROOT/rdr-raw.md"
cmp -s "$ROOT/rdr-raw.md" "$f_rdr1" \
	&& ok "show --raw is byte-exact against the file" || bad "show --raw is byte-exact against the file"
# Read == write agreement: the canonical body piped back through edit leaves
# the whole file byte-identical (the pinned clock keeps the Updated stamp).
t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section Objective \
	| t edit --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section Objective - >/dev/null
cmp -s "$ROOT/rdr-raw.md" "$f_rdr1" \
	&& ok "show --section pipes back through edit byte-identically" || bad "show --section pipes back through edit byte-identically"

echo "== list: --json rows, lanes, and pagination =="
rdr_lst="$(t list --dir "$rdr_dir" --json)"
assert_contains "list --json carries the schema_version 1 marker" "$rdr_lst" '{"schema_version":1,'
assert_contains "list --json counts the board" "$rdr_lst" '"total":2,"count":2'
assert_contains "list --json places the fixture in In Progress" "$rdr_lst" '"lane":"In Progress"'
assert_contains "list --json places the archived task in Archive" "$rdr_lst" '"lane":"Archive"'
assert_contains "list --json carries the claim restriction" "$rdr_lst" '"claim_owner":"sess-fix"'
assert_contains "list --json carries the header owner" "$rdr_lst" '"owner":"sess-fix"'
assert_eq "list --json orders dashboard-lanes first" "In Progress" \
	"$(rdr_jfield "$(printf '%s' "$rdr_lst" | grep -o '{"schema_version":1,"type":"task_row"[^}]*}' | head -1)" lane)"
rdr_lane="$(t list --dir "$rdr_dir" --json --lane Archive)"
assert_contains "list --lane filters one lane" "$rdr_lane" '"total":1,"count":1'
assert_contains "list --lane drops the other lane" \
	"$(rdr_jfield "$(printf '%s' "$rdr_lane" | grep -o '{"schema_version":1,"type":"task_row"[^}]*}' | head -1)" id)" \
	"FIX-2"
rdr_page="$(t list --dir "$rdr_dir" --json --limit 1 --offset 1)"
assert_contains "list --limit/--offset pages the sorted set" "$rdr_page" '"total":2,"count":1,"offset":1,"limit":1'
refuse "list refuses an unknown lane" list --dir "$rdr_dir" --lane Bogus
refuse "list refuses a non-numeric limit" list --dir "$rdr_dir" --limit abc
refuse "list refuses a negative offset" list --dir "$rdr_dir" --offset -1
rdr_lst_err="$(t list --dir "$rdr_dir" --lane Bogus 2>&1 >/dev/null || true)"
assert_contains "the lane refusal carries USAGE" "$rdr_lst_err" "(code: USAGE)"
rdr_human="$(t list --dir "$rdr_dir")"
assert_contains "list human view prints tab-separated rows" "$rdr_human" \
	"$(printf 'FIX-1\tIn Progress\tIn Progress\tcurrent/FIX-1-20260615-1200-reader-fixture.md')"

echo "== reports: --json provenance and bodies =="
printf 'deposit one body\n' | t report --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --slug one --digest "first digest" >/dev/null
printf 'deposit two\n' | t report --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --slug two --digest "second digest" --from sess-fix >/dev/null
printf 'ghost report never linked\n' >"$rdr_dir/reports/FIX-1-20260615-1200-reader-fixture.md/05-ghost.md"
rdr_rpt="$(t reports --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json)"
assert_contains "reports --json carries the schema_version 1 marker" "$rdr_rpt" '{"schema_version":1,"type":"reports"'
assert_contains "reports --json counts the deposits" "$rdr_rpt" '"total":3,"count":3'
assert_contains "reports --json pins the linked provenance" "$rdr_rpt" '"seq":1,"name":"01-one.md","file":"reports/FIX-1-20260615-1200-reader-fixture.md/01-one.md","linked":true,"stamp":"2026-06-15 12:00","from":"Manager","digest":"first digest"'
assert_contains "reports --json carries the second attribution" "$rdr_rpt" '"from":"sess-fix","digest":"second digest"'
assert_contains "reports --json marks an unlinked on-disk report" "$rdr_rpt" '"seq":5,"name":"05-ghost.md","file":"reports/FIX-1-20260615-1200-reader-fixture.md/05-ghost.md","linked":false'
# rdr_jfield grabs the first occurrence, so --limit 1 pins the decode target.
rdr_rpt_lim="$(t reports --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json --include-body --limit 1)"
rdr_rpt_body_decoded="$(printf '%s\n' "$rdr_rpt_lim" | rdr_jfield "$rdr_rpt_lim" body | rdr_unesc; echo)"
assert_eq "reports --include-body reconstructs the deposit byte-exact" \
	"$(printf 'deposit one body\n')" "$rdr_rpt_body_decoded"
assert_contains "reports human view prints name and digest" "$(t reports --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md)" \
	"$(printf '01-one.md\tfirst digest')"
rdr_rpt_page="$(t reports --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json --limit 1 --offset 1)"
assert_contains "reports --limit/--offset page by sequence" "$rdr_rpt_page" '"total":3,"count":1,"offset":1,"limit":1'
assert_contains "the paged report is the second deposit" "$rdr_rpt_page" '"digest":"second digest"'
refuse "reports refuses --include-body without --json" reports --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --include-body
rdr_empty="$(t reports --dir "$rdr_dir" FIX-2-20260615-0900-archived-fixture.md --json)"
assert_contains "reports on a task without deposits is an empty success" "$rdr_empty" '"total":0,"count":0,"offset":0,"limit":0,"reports":[]'

echo "== export: lossless JSONL round-trip =="
rdr_export="$ROOT/rdr-export.jsonl"
t export --dir "$rdr_dir" --include-reports >"$rdr_export"
rdr_export_lines="$(wc -l <"$rdr_export")"
rdr_export_expected="$(( $(find "$rdr_dir/current" "$rdr_dir/archive" -type f -name '*.md' | wc -l) + $(find "$rdr_dir/reports" -type f -name '*.md' 2>/dev/null | wc -l) ))"
assert_eq "export emits one record per board file" "$rdr_export_expected" "$rdr_export_lines"
rt_fail=0
rt_root="$ROOT/rdr-roundtrip"
mkdir -p "$rt_root"
while IFS= read -r line; do
	[[ "$line" == '{"schema_version":1,'* ]] || { rt_fail=$((rt_fail + 1)); continue; }
	rf="$(rdr_jfield "$line" file)"
	rc="$(rdr_jfield "$line" content)"
	rc_dec="$(printf '%s' "$rc" | rdr_unesc)"
	[[ "$line" == *'"final_newline":true'* ]] && rc_dec+=$'\n'
	rt_path="$rdr_dir/$rf"
	mkdir -p "$(dirname "$rt_root/$rf")"
	printf '%s' "$rc_dec" >"$rt_root/$rf"
	cmp -s "$rt_root/$rf" "$rt_path" || rt_fail=$((rt_fail + 1))
done <"$rdr_export"
assert_eq "exported records reconstruct every file byte-exactly" "0" "$rt_fail"
assert_contains "export includes the archived task" "$(cat "$rdr_export")" '"file":"archive/FIX-2-20260615-0900-archived-fixture.md"'
assert_contains "export includes report bodies under --include-reports" "$(cat "$rdr_export")" '"file":"reports/FIX-1-20260615-1200-reader-fixture.md/01-one.md"'
assert_eq "export --format jsonl is the explicit default" \
	"$(t export --dir "$rdr_dir" --include-reports --format jsonl)" "$(cat "$rdr_export")"
refuse "export refuses an unsupported format" export --dir "$rdr_dir" --format yaml

echo "== show/edit: fenced level-2 headings are sections on both sides =="
# The heading model is fence-blind repo-wide (lint scanner, closure gate,
# edit, readers), and the skill documents the phantom-section hazard that
# follows: a heading-looking line inside a fenced block is a real section
# boundary. This pin makes the documented semantics contract rather than
# accident, on both sides of the read==write invariant: the fenced level-2
# line is addressable by show --section (read) and by edit --section
# (write), and the fence splits the enclosing section identically for both.
cat >"$rdr_dir/current/FIX-3-20260615-1100-fenced-probe.md" <<'FIXEOF'
# Task: Fenced Probe

**Created:** 2026-06-15 11:00
**Status:** Triage
**Priority:** Medium
**Progress:** 0%
**Owner:**
**Updated:** 2026-06-15 11:00

## Objective

fenced probe objective

## Testing Strategy

body before the fence

```
fenced line one
## Fenced Demo
still fenced body
```

tail after the fence
FIXEOF
assert_eq "a fenced level-2 heading reads as a section" \
	"$(printf 'still fenced body\n```\n\ntail after the fence')" \
	"$(t show --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Fenced Demo')"
rdr_fencejson="$(t show --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Fenced Demo' --json)"
assert_contains "the fenced heading pins as level 2 in the section envelope" \
	"$rdr_fencejson" '"heading":"Fenced Demo","level":2'
assert_eq "the enclosing section ends at the fenced heading like edit" \
	"$(printf 'body before the fence\n\n```\nfenced line one')" \
	"$(t show --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Testing Strategy')"
printf 'appended inside the phantom section\n' \
	| t edit --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Fenced Demo' --append - >/dev/null
assert_eq "edit --append lands inside the fenced section like read" \
	"$(printf 'still fenced body\n```\n\ntail after the fence\n\nappended inside the phantom section')" \
	"$(t show --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Fenced Demo')"
t show --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Fenced Demo' \
	| t edit --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Fenced Demo' - >/dev/null
assert_eq "the fenced section round-trips through edit byte-exact" \
	"$(printf 'still fenced body\n```\n\ntail after the fence\n\nappended inside the phantom section')" \
	"$(t show --dir "$rdr_dir" FIX-3-20260615-1100-fenced-probe.md --section 'Fenced Demo')"

echo "== readers: read-only guarantee =="
# Every reader run over the fixture board must leave the whole tree
# untouched: no lock, no render, no Updated bump, no sidecar, no temp.
rdr_tree_before="$(find "$rdr_dir" -type f -exec sha1sum {} \; | LC_ALL=C sort)"
t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md >/dev/null
t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json >/dev/null
t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --section Objective >/dev/null
t show --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --raw >/dev/null
t list --dir "$rdr_dir" --json >/dev/null
t list --dir "$rdr_dir" >/dev/null
t reports --dir "$rdr_dir" FIX-1-20260615-1200-reader-fixture.md --json --include-body >/dev/null
t export --dir "$rdr_dir" --include-reports >/dev/null
rdr_tree_after="$(find "$rdr_dir" -type f -exec sha1sum {} \; | LC_ALL=C sort)"
assert_eq "the reader surface leaves the board tree untouched" "$rdr_tree_before" "$rdr_tree_after"

echo "== reader error codes =="
rdr_nf_err="$(t show --dir "$rdr_dir" NOPE-9.md 2>&1 >/dev/null || true)"
assert_contains "show on a missing file carries TASK_NOT_FOUND" "$rdr_nf_err" "(code: TASK_NOT_FOUND)"
printf 'outside\n' >"$ROOT/outside-rdr.md"
rdr_esc_err="$(t show --dir "$rdr_dir" "$ROOT/outside-rdr.md" 2>&1 >/dev/null || true)"
assert_contains "show outside the board root carries BOARD_ROOT_ESCAPE" "$rdr_esc_err" "(code: BOARD_ROOT_ESCAPE)"
rm -f "$ROOT/outside-rdr.md"
rdr_nb_err="$(t show --dir "$ROOT/no-such-board" x.md 2>&1 >/dev/null || true)"
assert_contains "show on a missing board carries NO_BOARD" "$rdr_nb_err" "(code: NO_BOARD)"
rdr_usage_err="$(t show 2>&1 >/dev/null || true)"
assert_contains "show usage failure carries USAGE" "$rdr_usage_err" "(code: USAGE)"
rdr_nb_board="$ROOT/rdr-noboard"
mkdir -p "$rdr_nb_board"
rdr_list_empty="$(t list --dir "$rdr_nb_board" --json)"
assert_contains "list on an empty root prints the empty payload" "$rdr_list_empty" '{"schema_version":1,"type":"list","total":0,"count":0,"offset":0,"limit":0,"tasks":[]}'
assert_eq "list on an empty root prints the no-tasks line" "no tasks" "$(t list --dir "$rdr_nb_board")"

echo "== readers: EXIT-trap cleanup under metacharacter TMPDIR =="
# The readers stage their row maps through mktemp in ${TMPDIR:-/tmp} and
# hand cleanup to an EXIT trap carrying %-q-escaped paths baked in at set
# time (the render_unlocked discipline). Under a TMPDIR holding spaces and
# quotes, the old fired-string form re-ran %-q inside double quotes at
# trap time, so rm received the literal backslashes and silently leaked
# the temp. SIGHUP is the one untrapped signal bash services through the
# EXIT trap, so each probe round launches list under the metacharacter
# TMPDIR and HUPs only once the staged temp provably exists AND the process
# has a live awk/sort child: bash is then blocked waiting on that child, so
# the queued signal is processed while the trap is still armed and can
# never land in the post-clear boundary window where the explicit rm has
# not run yet. The catch assertion keeps a probe that never entered the
# armed window from passing vacuously.
rdr_meta_root="$ROOT/rdr-meta tmp'dir"
mkdir -p "$rdr_meta_root/.tasks/current"
for fmn in $(seq -w 1 120); do
	cat >"$rdr_meta_root/.tasks/current/META-$fmn-20260615-1200-meta-filler.md" <<EOF
# Task: Meta Filler $fmn

**Created:** 2026-06-15 12:00
**Status:** Triage
**Priority:** Medium
**Progress:** 0%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

filler $fmn body

## Work Log

## Execution Log
EOF
done
rdr_meta_caught=0
rdr_meta_leak=0
for rdr_round in 1 2 3; do
	TMPDIR="$rdr_meta_root" "$TASKS_BIN" list --dir "$rdr_meta_root/.tasks" >/dev/null 2>&1 &
	rdr_meta_pid=$!
	rdr_meta_hit=0
	for rdr_poll in $(seq 1 300); do
		if compgen -G "$rdr_meta_root/tasks-list.*" >/dev/null 2>&1 \
			&& [[ -n "$(ps --ppid "$rdr_meta_pid" -o pid= 2>/dev/null)" ]]; then
			rdr_meta_hit=1
			break
		fi
		sleep 0.01
	done
	kill -HUP "$rdr_meta_pid" 2>/dev/null
	wait "$rdr_meta_pid" 2>/dev/null
	if ((rdr_meta_hit == 1)); then
		rdr_meta_caught=$((rdr_meta_caught + 1))
		[[ -z "$(compgen -G "$rdr_meta_root/tasks-list.*" 2>/dev/null)" ]] || rdr_meta_leak=$((rdr_meta_leak + 1))
	fi
done
((rdr_meta_caught >= 1)) \
	&& ok "the metacharacter-TMPDIR probe catches the trap's armed window" \
	|| bad "the metacharacter-TMPDIR probe catches the trap's armed window"
assert_eq "no temp leaks through the EXIT trap under metacharacter TMPDIR" "0" "$rdr_meta_leak"
rm -rf "$rdr_meta_root"

# --- expanded doctor (ORCH-4-4-2) -------------------------------------------

echo "== doctor: grandfathering pins a legacy-shaped board at zero =="
# Dedicated fixture board carrying every grandfathered shape the live board
# probe recorded (archived dup IDs, all-archived cycles, Ready-file future
# children, archived claim sidecars, archived dead links) plus healthy live
# shapes, so the doctor pins at zero before any live problem is introduced.
doc_dir="$ROOT/doc/.tasks"
t init --dir "$doc_dir" >/dev/null
mkdir -p "$doc_dir/archive"
cat >"$doc_dir/current/CY-1-20260615-1200-cycle-a.md" <<'EOF'
# Task: Cycle A

**Created:** 2026-06-15 12:00
**Status:** In Progress
**Priority:** Medium
**Progress:** 10%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

cycle a body

## Dependencies

- CY-2

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/CY-2-20260615-1200-cycle-b.md" <<'EOF'
# Task: Cycle B

**Created:** 2026-06-15 12:00
**Status:** Ready
**Priority:** Medium
**Progress:** 0%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

cycle b body

## Dependencies

- CY-1

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/DEP-1-20260615-1200-missing-dep.md" <<'EOF'
# Task: Missing Dep

**Created:** 2026-06-15 12:00
**Status:** In Progress
**Priority:** Medium
**Progress:** 10%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

dep body

## Dependencies

- GHOST-9

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/FUT-1-20260615-1200-future-child.md" <<'EOF'
# Task: Future Child

**Created:** 2026-06-15 12:00
**Status:** Ready
**Priority:** Medium
**Progress:** 0%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

future child body

## Dependencies

- FUTURE-7

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/REASON-1-20260615-1200-no-reason.md" <<'EOF'
# Task: No Reason

**Created:** 2026-06-15 12:00
**Status:** Blocked
**Priority:** Medium
**Progress:** 10%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

blocked without a reason body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/REASON-2-20260615-1200-with-reason.md" <<'EOF'
# Task: With Reason

**Created:** 2026-06-15 12:00
**Status:** Blocked
**Status Reason:** waiting on an external review
**Priority:** Medium
**Progress:** 10%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

blocked with a reason body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/archive/REASON-3-20260615-1200-archived-no-reason.md" <<'EOF'
# Task: Archived No Reason

**Created:** 2026-06-15 09:00
**Status:** Blocked
**Priority:** Medium
**Progress:** 10%
**Owner:**
**Updated:** 2026-06-15 09:30

## Objective

archived blocked body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/DUP-1-20260615-1200-one.md" <<'EOF'
# Task: Dup One

**Created:** 2026-06-15 12:00
**Status:** In Progress
**Priority:** Medium
**Progress:** 10%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

dup one body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/DUP-1-20260615-1300-two.md" <<'EOF'
# Task: Dup Two

**Created:** 2026-06-15 13:00
**Status:** Triage
**Priority:** Medium
**Progress:** 0%
**Owner:**
**Updated:** 2026-06-15 13:00

## Objective

dup two body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/archive/DUP-2-20260601-0900-one.md" <<'EOF'
# Task: Archived Dup One

**Created:** 2026-06-01 09:00
**Status:** Completed
**Priority:** Medium
**Progress:** 100%
**Owner:**
**Updated:** 2026-06-01 10:00
**Completed:** 2026-06-01 10:00

## Objective

archived dup one body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/archive/DUP-2-20260601-0930-two.md" <<'EOF'
# Task: Archived Dup Two

**Created:** 2026-06-01 09:30
**Status:** Completed
**Priority:** Medium
**Progress:** 100%
**Owner:**
**Updated:** 2026-06-01 10:00
**Completed:** 2026-06-01 10:00

## Objective

archived dup two body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/archive/ACY-1-20260601-0900-archived-cycle-a.md" <<'EOF'
# Task: Archived Cycle A

**Created:** 2026-06-01 09:00
**Status:** Completed
**Priority:** Medium
**Progress:** 100%
**Owner:**
**Updated:** 2026-06-01 10:00
**Completed:** 2026-06-01 10:00

## Objective

archived cycle a body

## Dependencies

- ACY-2

## Work Log

## Execution Log
EOF
cat >"$doc_dir/archive/ACY-2-20260601-0930-archived-cycle-b.md" <<'EOF'
# Task: Archived Cycle B

**Created:** 2026-06-01 09:30
**Status:** Completed
**Priority:** Medium
**Progress:** 100%
**Owner:**
**Updated:** 2026-06-01 10:00
**Completed:** 2026-06-01 10:00

## Objective

archived cycle b body

## Dependencies

- ACY-1

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/LINK-1-20260615-1200-dead-link.md" <<'EOF'
# Task: Dead Link

**Created:** 2026-06-15 12:00
**Status:** Triage
**Priority:** Medium
**Progress:** 0%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

context [report](../reports/GHOST-9-20260615-1200-x/99-missing.md) body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/archive/LINK-2-20260601-0900-archived-dead-link.md" <<'EOF'
# Task: Archived Dead Link

**Created:** 2026-06-01 09:00
**Status:** Completed
**Priority:** Medium
**Progress:** 100%
**Owner:**
**Updated:** 2026-06-01 10:00
**Completed:** 2026-06-01 10:00

## Objective

context [report](../reports/GHOST-9-20260615-1200-x/99-missing.md) body

## Work Log

## Execution Log
EOF
cat >"$doc_dir/current/CLAIM-1-20260615-1200-claimed.md" <<'EOF'
# Task: Claimed

**Created:** 2026-06-15 12:00
**Status:** In Progress
**Priority:** Medium
**Progress:** 40%
**Owner:** sess-doc
**Updated:** 2026-06-15 12:00

## Objective

claimed body

## Work Log

## Execution Log
EOF
printf 'sess-doc\n' >"$doc_dir/current/CLAIM-1-20260615-1200-claimed.md.claim"
cat >"$doc_dir/current/CLAIM-2-20260615-1200-done-with-claim.md" <<'EOF'
# Task: Done With Claim

**Created:** 2026-06-15 12:00
**Status:** Completed
**Priority:** Medium
**Progress:** 100%
**Owner:** sess-doc
**Updated:** 2026-06-15 12:30
**Completed:** 2026-06-15 12:30

## Objective

done with claim body

## Work Log

## Execution Log
EOF
printf 'sess-doc\n' >"$doc_dir/current/CLAIM-2-20260615-1200-done-with-claim.md.claim"
cat >"$doc_dir/archive/CLAIM-3-20260601-0900-archived-with-claim.md" <<'EOF'
# Task: Archived With Claim

**Created:** 2026-06-01 09:00
**Status:** Completed
**Priority:** Medium
**Progress:** 100%
**Owner:**
**Updated:** 2026-06-01 10:00
**Completed:** 2026-06-01 10:00

## Objective

archived with claim body

## Work Log

## Execution Log
EOF
printf 'sess-old\n' >"$doc_dir/archive/CLAIM-3-20260601-0900-archived-with-claim.md.claim"
printf 'ghost\n' >"$doc_dir/ORPHAN-9-20260615-1200-gone.md.claim"
cat >"$doc_dir/current/broken-name.md" <<'EOF'
# Task: Broken Name

**Created:** 2026-06-15 12:00
**Status:** Triage
**Priority:** Medium
**Progress:** 0%
**Owner:**
**Updated:** 2026-06-15 12:00

## Objective

broken name body

## Work Log

## Execution Log
EOF
# Render syncs the dashboard with the fixture board, so divergence starts quiet.
t render --dir "$doc_dir" >/dev/null
doc_out="$(t doctor --dir "$doc_dir")"
doc_expected="$(printf 'DEAD_REPORT_LINK %s: dead report link (line 12): ../reports/GHOST-9-20260615-1200-x/99-missing.md\nDEP_CYCLE %s: dependency cycle: CY-1 -> CY-2 -> CY-1 (open: %s)\nDUPLICATE_ID %s: Task ID DUP-1 shared by: %s %s\nFILE_NAMING %s: file name misses the CLI convention (ID-stamp-slug.md): broken-name.md\nMISSING_DEP %s: dependency token '\''GHOST-9'\'' names no board file\nSTALE_CLAIM %s: claim sidecar with no task file\nSTALE_CLAIM %s: stale claim sidecar on Completed task\nSTATUS_REASON %s: Status Blocked requires a Status Reason (the header contract ties it to Blocked/Cancelled)\ndoctor: 8 problem(s) across 19 task files' \
	"current/LINK-1-20260615-1200-dead-link.md" \
	"current/CY-1-20260615-1200-cycle-a.md" "current/CY-1-20260615-1200-cycle-a.md" \
	"current/DUP-1-20260615-1200-one.md" \
	"current/DUP-1-20260615-1200-one.md" "current/DUP-1-20260615-1300-two.md" \
	"current/broken-name.md" \
	"current/DEP-1-20260615-1200-missing-dep.md" \
	"ORPHAN-9-20260615-1200-gone.md.claim" \
	"current/CLAIM-2-20260615-1200-done-with-claim.md.claim" \
	"current/REASON-1-20260615-1200-no-reason.md")"
assert_eq "doctor fires exactly the live-set problems" "$doc_expected" "$doc_out"
doc_rc=0; t doctor --dir "$doc_dir" >/dev/null 2>&1 || doc_rc=1
assert_eq "doctor exits 0 even with problems" "0" "$doc_rc"
assert_not_contains "doctor grandfathers the archived dup group" "$doc_out" "DUP-2"
assert_not_contains "doctor grandfathers the all-archived cycle" "$doc_out" "ACY"
assert_not_contains "doctor grandfathers the archived no-reason file" "$doc_out" "REASON-3"
assert_not_contains "doctor grandfathers the Ready future-child token" "$doc_out" "FUTURE-7"
assert_not_contains "doctor grandfathers the archived dead link" "$doc_out" "LINK-2"
assert_not_contains "doctor grandfathers the archived claim sidecar" "$doc_out" "CLAIM-3"
assert_not_contains "doctor stays quiet on the healthy claim" "$doc_out" "CLAIM-1"
assert_not_contains "doctor stays quiet on the reasoned Blocked file" "$doc_out" "REASON-2"
assert_not_contains "doctor stays quiet when a cycle token resolves" "$doc_out" "DEP-1-20260615-1200-missing-dep.md: dependency token 'CY-2'"

echo "== doctor: --json envelope =="
doc_json="$(t doctor --dir "$doc_dir" --json)"
assert_contains "doctor --json carries the schema_version 1 marker" "$doc_json" '{"schema_version":1,"type":"doctor"'
assert_eq "doctor --json counts all eight codes in fixed order" \
	'"counts":{"DUPLICATE_ID":1,"FILE_NAMING":1,"STATUS_REASON":1,"STALE_CLAIM":2,"MISSING_DEP":1,"DEP_CYCLE":1,"DEAD_REPORT_LINK":1,"DASHBOARD_DIVERGENCE":0}' \
	"$(printf '%s' "$doc_json" | grep -o '"counts":{[^}]*}')"
assert_eq "doctor --json pins the total" '"total":8' "$(printf '%s' "$doc_json" | grep -o '"total":[0-9]*')"
assert_contains "doctor --json records carry code, file, and detail" "$doc_json" \
	'{"code":"DEP_CYCLE","file":"current/CY-1-20260615-1200-cycle-a.md","detail":"dependency cycle: CY-1 -> CY-2 -> CY-1 (open: current/CY-1-20260615-1200-cycle-a.md)"}'
doc_json_err="$(t doctor --dir "$doc_dir" --bogus 2>&1 >/dev/null || true)"
assert_contains "doctor refuses an unknown argument with USAGE" "$doc_json_err" "(code: USAGE)"

echo "== doctor: --all surfaces the grandfathered findings =="
doc_all="$(t doctor --dir "$doc_dir" --all)"
doc_all_expected="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\nGRANDFATHERED %s\nGRANDFATHERED %s\nGRANDFATHERED %s\nGRANDFATHERED %s\nGRANDFATHERED %s\nGRANDFATHERED %s\ndoctor: 8 problem(s), 6 grandfathered across 19 task files' \
	'DEAD_REPORT_LINK current/LINK-1-20260615-1200-dead-link.md: dead report link (line 12): ../reports/GHOST-9-20260615-1200-x/99-missing.md' \
	'DEP_CYCLE current/CY-1-20260615-1200-cycle-a.md: dependency cycle: CY-1 -> CY-2 -> CY-1 (open: current/CY-1-20260615-1200-cycle-a.md)' \
	'DUPLICATE_ID current/DUP-1-20260615-1200-one.md: Task ID DUP-1 shared by: current/DUP-1-20260615-1200-one.md current/DUP-1-20260615-1300-two.md' \
	'FILE_NAMING current/broken-name.md: file name misses the CLI convention (ID-stamp-slug.md): broken-name.md' \
	'MISSING_DEP current/DEP-1-20260615-1200-missing-dep.md: dependency token '\''GHOST-9'\'' names no board file' \
	'STALE_CLAIM ORPHAN-9-20260615-1200-gone.md.claim: claim sidecar with no task file' \
	'STALE_CLAIM current/CLAIM-2-20260615-1200-done-with-claim.md.claim: stale claim sidecar on Completed task' \
	'STATUS_REASON current/REASON-1-20260615-1200-no-reason.md: Status Blocked requires a Status Reason (the header contract ties it to Blocked/Cancelled)' \
	'DEAD_REPORT_LINK archive/LINK-2-20260601-0900-archived-dead-link.md: dead report link (line 13): ../reports/GHOST-9-20260615-1200-x/99-missing.md' \
	'DEP_CYCLE archive/ACY-1-20260601-0900-archived-cycle-a.md: dependency cycle: ACY-1 -> ACY-2 -> ACY-1' \
	'DUPLICATE_ID archive/DUP-2-20260601-0900-one.md: Task ID DUP-2 shared by: archive/DUP-2-20260601-0900-one.md archive/DUP-2-20260601-0930-two.md' \
	'MISSING_DEP current/FUT-1-20260615-1200-future-child.md: dependency token '\''FUTURE-7'\'' names no board file' \
	'STALE_CLAIM archive/CLAIM-3-20260601-0900-archived-with-claim.md.claim: claim sidecar on archived task' \
	'STATUS_REASON archive/REASON-3-20260615-1200-archived-no-reason.md: Status Blocked requires a Status Reason (the header contract ties it to Blocked/Cancelled)')"
assert_eq "doctor --all lists grandfathered findings under their own marker and count" "$doc_all_expected" "$doc_all"
assert_not_contains "doctor without --all stays silent on the grandfathered findings" "$doc_out" "GRANDFATHERED"
assert_not_contains "doctor --json default carries no grandfathered fields" "$doc_json" "grandfathered"
doc_all_json="$(t doctor --dir "$doc_dir" --all --json)"
assert_eq "doctor --all --json pins the grandfathered total" '"grandfathered_total":6' "$(printf '%s' "$doc_all_json" | grep -o '"grandfathered_total":[0-9]*')"
assert_contains "doctor --all --json carries the grandfathered records" "$doc_all_json" \
	'{"code":"DEP_CYCLE","file":"archive/ACY-1-20260601-0900-archived-cycle-a.md","detail":"dependency cycle: ACY-1 -> ACY-2 -> ACY-1"}'
assert_eq "doctor --all --json keeps the live totals" '"total":8' "$(printf '%s' "$doc_all_json" | grep -o '"total":[0-9]*')"
# The --all envelope extends the base object, so the same independent-parser
# gate that pins the readers' single-document shape guards it too: json.load
# refuses trailing data, which is exactly how the --all extension first
# landed outside the closing brace.
if command -v python3 >/dev/null 2>&1; then
	if printf '%s\n' "$doc_all_json" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null; then
		ok "doctor --all --json parses as one complete JSON document (python3)"
	else
		bad "doctor --all --json parses as one complete JSON document (python3)"
	fi
elif command -v jq >/dev/null 2>&1; then
	if printf '%s\n' "$doc_all_json" | jq -e . >/dev/null 2>&1; then
		ok "doctor --all --json parses as one complete JSON document (jq)"
	else
		bad "doctor --all --json parses as one complete JSON document (jq)"
	fi
else
	bad "no independent JSON parser on the host (python3 nor jq)"
fi
doc_all_rc=0; t doctor --dir "$doc_dir" --all >/dev/null 2>&1 || doc_all_rc=1
assert_eq "doctor --all keeps the always-exit-0 contract" "0" "$doc_all_rc"

echo "== doctor: dashboard divergence =="
printf '\nstray line\n' >>"$doc_dir/dashboard.md"
doc_div="$(t doctor --dir "$doc_dir")"
assert_contains "doctor reports a diverged dashboard" "$doc_div" 'DASHBOARD_DIVERGENCE dashboard.md: dashboard.md differs from the assembled board'
t render --dir "$doc_dir" >/dev/null
assert_not_contains "doctor clears the divergence after render" "$(t doctor --dir "$doc_dir")" "DASHBOARD_DIVERGENCE"
rm -f "$doc_dir/dashboard.md"
assert_contains "doctor reports a missing dashboard" "$(t doctor --dir "$doc_dir")" 'DASHBOARD_DIVERGENCE dashboard.md: dashboard.md is missing (render would create it)'
t render --dir "$doc_dir" >/dev/null

echo "== doctor: read-only guarantee =="
doc_tree_before="$(find "$doc_dir" -type f -exec sha1sum {} \; | LC_ALL=C sort)"
t doctor --dir "$doc_dir" >/dev/null
t doctor --dir "$doc_dir" --json >/dev/null
t doctor --dir "$doc_dir" --all >/dev/null
t doctor --dir "$doc_dir" --all --json >/dev/null
doc_tree_after="$(find "$doc_dir" -type f -exec sha1sum {} \; | LC_ALL=C sort)"
assert_eq "the doctor leaves the board tree untouched" "$doc_tree_before" "$doc_tree_after"

# --- AC-06 write parity (ORCH-4-4-2) ----------------------------------------

echo "== write parity: every permitted mutation has an authorized CLI path =="
# The AC-06 inventory walk: each permitted mutation class performs through
# its one authorized command on a scaffolded fixture, with a read-back so
# the read surface proves the landing. Lifecycle transitions (claim,
# release, close, archive) keep their dedicated commands and close the walk.
wp_dir="$ROOT/wp/.tasks"
t init --dir "$wp_dir" >/dev/null
f_wp="$(t new --dir "$wp_dir" --id WP-1 --name "Write Parity Fixture")"
t set --dir "$wp_dir" "$(basename "$f_wp")" Priority=High >/dev/null
assert_contains "header mutations ride tasks set" "$(grep -oP '^\*\*Priority:\*\*\s+\K.*' "$f_wp")" "High"
printf -- '- [x] landed criterion\n' | t edit --dir "$wp_dir" "$(basename "$f_wp")" --section "Success Criteria" - >/dev/null
assert_eq "criteria changes ride tasks edit and read back byte-exact" \
	"$(printf -- '- [x] landed criterion')" \
	"$(t show --dir "$wp_dir" "$(basename "$f_wp")" --section "Success Criteria")"
printf 'planning prose\n\n### Decision Log\n\nnested planner note\n' | t edit --dir "$wp_dir" "$(basename "$f_wp")" --section "Technical Approach" - >/dev/null
assert_contains "planner nested edits keep deeper headings" \
	"$(t show --dir "$wp_dir" "$(basename "$f_wp")" --section "Technical Approach")" "### Decision Log"
printf 'appended prose\n' | t edit --dir "$wp_dir" "$(basename "$f_wp")" --section "Technical Approach" --append - >/dev/null
assert_contains "cumulative appends grow the section" \
	"$(t show --dir "$wp_dir" "$(basename "$f_wp")" --section "Technical Approach")" "appended prose"
printf 'open question: does the gate accept this?\n' | t edit --dir "$wp_dir" "$(basename "$f_wp")" --section "Questions" --append - >/dev/null
printf -- '- evidence: [01-evi.md](../reports/%s/01-evi.md)\n' "$(basename "$f_wp")" | t edit --dir "$wp_dir" "$(basename "$f_wp")" --section "Evidence" --append - >/dev/null
printf 'evidence deposit\n' | t report --dir "$wp_dir" "$(basename "$f_wp")" --slug evi --digest "evidence deposit" >/dev/null
wp_order="$(grep '^## ' "$f_wp" | sed 's/^## //' | tr '\n' '|')"
assert_contains "question updates create Questions at the canonical slot" "$wp_order" "|Success Criteria|Technical Approach|Questions|Evidence|Work Log|"
assert_eq "evidence links create Evidence between Questions and Work Log" \
	"Table of Contents|Objective|Success Criteria|Technical Approach|Questions|Evidence|Work Log|Execution Log|" "$wp_order"
assert_contains "the created sections ride the versioned snapshot" \
	"$(t show --dir "$wp_dir" "$(basename "$f_wp")" --json)" '"heading":"Questions"'
assert_contains "evidence links name a real deposit" \
	"$(t show --dir "$wp_dir" "$(basename "$f_wp")" --section Evidence)" "../reports/$(basename "$f_wp")/01-evi.md"
t log --dir "$wp_dir" "$(basename "$f_wp")" "inventory walk entry" >/dev/null
assert_contains "work log entries ride tasks log" "$(t show --dir "$wp_dir" "$(basename "$f_wp")" --tail 1)" "inventory walk entry"
wp_lint_rc=0; t lint --dir "$wp_dir" >/dev/null 2>&1 || wp_lint_rc=1
assert_eq "the fixture board stays lint-clean after the walk" "0" "$wp_lint_rc"
t close --dir "$wp_dir" "$(basename "$f_wp")" >/dev/null
t archive --dir "$wp_dir" "$(basename "$f_wp")" >/dev/null
[[ -f "$wp_dir/archive/$(basename "$f_wp")" ]] \
	&& ok "terminal transitions ride close and archive" || bad "terminal transitions ride close and archive"

echo "== write parity: concurrent edit --append serializes (no lost append) =="
# Without a seam, whether two writers' lock windows overlap is scheduler
# luck and the assertion can pass with the lock removed whenever the
# processes serialize naturally. Both writers carry the test-only
# TASKS_TEST_LOCK_HOLD_MS seam (validated under the same TASKS_DIR co-gate
# as the clock): the second writer provably blocks on the flock, the
# round's wall clock proves the serialization (two serialized 600ms holds
# plus startup and render cannot finish under 1100ms, while the lockless
# parallel shape runs both holds concurrently around 800ms and a red
# scratch run of exactly that shape lost an update outright), and the
# no-lost-update assertion rides on a race that actually ran.
f_wpc="$(t new --dir "$wp_dir" --id WP-2 --name "Append Concurrency Fixture")"
wpdir="$(mktemp -d)"
wpfail=0
for wp_round in 1 2 3 4 5 6; do
	wp_t0="$EPOCHREALTIME"
	printf 'alpha round %s\n' "$wp_round" | TASKS_TEST_LOCK_HOLD_MS=600 t edit --dir "$wp_dir" "$(basename "$f_wpc")" --section "Risk Assessment" --append - >"$wpdir/a.out" 2>&1 &
	a_pid=$!
	printf 'beta round %s\n' "$wp_round" | TASKS_TEST_LOCK_HOLD_MS=600 t edit --dir "$wp_dir" "$(basename "$f_wpc")" --section "Risk Assessment" --append - >"$wpdir/b.out" 2>&1 &
	b_pid=$!
	wait "$a_pid"; a_code=$?
	wait "$b_pid"; b_code=$?
	wp_t1="$EPOCHREALTIME"
	wp_ms="$(awk -v a="$wp_t0" -v b="$wp_t1" 'BEGIN { printf "%d", (b - a) * 1000 }')"
	[[ "$a_code" == 0 && "$b_code" == 0 ]] || wpfail=$((wpfail + 1))
	((wp_ms >= 1100)) || wpfail=$((wpfail + 1))
	wp_sec="$(t show --dir "$wp_dir" "$(basename "$f_wpc")" --section "Risk Assessment")"
	[[ "$wp_sec" == *"alpha round $wp_round"* ]] || wpfail=$((wpfail + 1))
	[[ "$wp_sec" == *"beta round $wp_round"* ]] || wpfail=$((wpfail + 1))
	[[ "$wp_sec" == *"alpha round 1"* ]] || wpfail=$((wpfail + 1))
done
assert_eq "concurrent appends serialize under the lock-hold seam and lose no update" "0" "$wpfail"
rm -rf "$wpdir"

echo "== write parity: crash safety (kill inside the commit window never tears the file) =="
# A fixed post-launch sleep kills during bash startup, before the staging
# write, so the interesting window (staged tmp written, mv not yet) never
# ran and the invariant's substance stayed untested. Each round arms the
# test-only TASKS_TEST_CRASH_POINT seam (same TASKS_DIR co-gate as the
# clock), which pauses the edit write path between the staged awk write
# and the committing mv, and kills only after the staged temp provably
# exists, so every round exercises the old-or-new invariant inside the
# real window.
f_wpk="$(t new --dir "$wp_dir" --id WP-3 --name "Crash Safety Fixture")"
printf 'baseline body\n' | t edit --dir "$wp_dir" "$(basename "$f_wpk")" --section "Testing Strategy" - >/dev/null
wpk_big="$(awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "filler %d\n", i }')"
printf '%s\n' "$wpk_big" | t edit --dir "$wp_dir" "$(basename "$f_wpk")" --section "Testing Strategy" --append - >/dev/null
wpk_fail=0
for wp_round in 1 2 3 4 5 6 7 8; do
	wpk_pre="$(t show --dir "$wp_dir" "$(basename "$f_wpk")" --section "Testing Strategy")"
	find "$wp_dir/current" -name '*.md.??????' -delete
	# The binary is launched directly, not through the t wrapper: a
	# backgrounded function call forks a subshell the kill would hit
	# instead of the CLI, leaving the seam-paused process alive holding
	# the board lock and starving the next round's writer.
	printf 'marker round %s\n' "$wp_round" | TASKS_TEST_CRASH_POINT=5 "$TASKS_BIN" edit --dir "$wp_dir" "$(basename "$f_wpk")" --section "Testing Strategy" --append - >/dev/null 2>&1 &
	wpk_pid=$!
	wpk_staged=0
	for wpk_poll in $(seq 1 100); do
		[[ -n "$(find "$wp_dir/current" -name '*.md.??????' -print -quit)" ]] && { wpk_staged=1; break; }
		sleep 0.02
	done
	kill -9 "$wpk_pid" 2>/dev/null
	wait "$wpk_pid" 2>/dev/null
	((wpk_staged == 1)) || wpk_fail=$((wpk_fail + 1))
	wpk_post="$(t show --dir "$wp_dir" "$(basename "$f_wpk")" --section "Testing Strategy")"
	[[ "$wpk_post" == "$wpk_pre" \
		|| "$wpk_post" == "$wpk_pre"$'\n\n'marker\ round\ $wp_round ]] || wpk_fail=$((wpk_fail + 1))
done
assert_eq "killed appends provably enter the commit window and leave old-or-new state" "0" "$wpk_fail"
find "$wp_dir/current" -name '*.md.??????' -delete
printf 'after-crash marker\n' | t edit --dir "$wp_dir" "$(basename "$f_wpk")" --section "Testing Strategy" --append - >/dev/null
assert_contains "a normal append lands after the crash rounds" \
	"$(t show --dir "$wp_dir" "$(basename "$f_wpk")" --section "Testing Strategy")" "after-crash marker"

 print_result
((fail == 0)) || exit 1
