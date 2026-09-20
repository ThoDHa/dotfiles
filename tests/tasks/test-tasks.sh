#!/usr/bin/env bash
#
# Tests for the `tasks` board tool. Self-contained: builds a scratch .tasks/
# dir under a temp root, exercises each command, and asserts the derived
# dashboard, idempotency, atomic claiming, and lane placement.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASKS_BIN="$REPO_ROOT/opencode/.local/bin/tasks"

pass=0
fail=0
skip=0

ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }
skip_test() { printf '  \033[0;33m- skipped\033[0m %s\n' "$1"; skip=$((skip + 1)); }

assert_eq() { # label expected actual
	if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
assert_contains() { # label haystack needle
	if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing [$3])"; fi
}
assert_not_contains() { # label haystack needle
	if grep -qF -- "$3" <<<"$2"; then bad "$1 (unexpected [$3])"; else ok "$1"; fi
}

refuse() { # label; rest is the command to attempt
	local label="$1"; shift
	if t "$@" </dev/null >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export TASKS_DIR="$ROOT/.tasks"
DASH="$TASKS_DIR/dashboard.md"

t() { "$TASKS_BIN" "$@"; }

edit_stderr_of() { # rest is the edit invocation; echoes its stderr
	# edit consumes stdin even when refusing, so detach it
	t edit "$@" </dev/null 2>&1 >/dev/null || true
}

echo "== init =="
t init >/dev/null
[[ -d "$TASKS_DIR/current" && -d "$TASKS_DIR/archive" && -f "$DASH" ]] \
	&& ok "init scaffolds dirs and dashboard" || bad "init scaffolds dirs and dashboard"
board="$(cat "$DASH")"
for lane in "## Triage" "## Ready" "## In Progress" "## Blocked/Cancelled" "## Completed" "## Archive"; do
	assert_contains "board has lane $lane" "$board" "$lane"
done

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
refuse "entering Blocked without a Status Reason is rejected" set "$f_kv" Status=Blocked
assert_contains "Blocked refusal demands a reason" \
	"$(t set "$f_kv" Status=Blocked 2>&1 >/dev/null || true)" "Status Reason"
assert_eq "rejected Blocked transition leaves the file byte-identical" "$kv_blocked_before" "$(cat "$f_kv")"
t set "$f_kv" Status=Blocked "Status Reason=work stopped on dependency" >/dev/null
assert_contains "Blocked with a same-call reason lands both fields" "$(kv_hdr)" \
	"**Status Reason:** work stopped on dependency"
t set "$f_kv" Status=Blocked >/dev/null
assert_contains "re-Blocking with the reason already on file keeps it" "$(kv_hdr)" \
	"**Status Reason:** work stopped on dependency"
refuse "entering Blocked with an emptied reason pair is rejected" set "$f_kv" Status=Blocked "Status Reason="
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
[[ "$kv_updated" == "$(date '+%Y-%m-%d')"* ]] \
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
t set "$f_pos" Owner= >/dev/null
assert_not_contains "Owner deletion removes the field" "$(awk '/^## /{exit}{print}' "$f_pos")" "**Owner:**"
t set "$f_pos" Owner=worker-pos >/dev/null
assert_eq "re-set Owner lands in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
t set "$f_pos" Owner= >/dev/null
t claim "$f_pos" --owner claim-pos >/dev/null
assert_eq "claimed Owner lands in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
t release "$f_pos" >/dev/null
assert_eq "release keeps Owner in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
t set "$f_pos" Owner= >/dev/null
t release "$f_pos" >/dev/null
assert_eq "blank-path Owner insert lands in canonical order" "$POS_CANONICAL_ORDER" "$(pos_order)"
assert_eq "blank-path Owner insert writes the bare field" "1" "$(grep -c '^\*\*Owner:\*\*$' "$f_pos")"
t set "$f_pos" "Latest Update=" >/dev/null
t set "$f_pos" "Latest Update=restored" >/dev/null
assert_eq "re-set Latest Update falls back to end of header" "$POS_CANONICAL_ORDER" "$(pos_order)"
rm -f "$f_pos"
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
if t set "$f_pipe" 'Priority=High | Critical' >/dev/null 2>&1; then ok "set accepts a pipe-bearing value"; else bad "set accepts a pipe-bearing value"; fi
t render >/dev/null
pipe_row="$(grep -F 'Piped' "$DASH")"
assert_contains "pipe in field value is escaped" "$pipe_row" 'High \| Critical'
assert_not_contains "field pipe does not add a column" "$pipe_row" "High | Critical"
# Repeated renders must stay byte-identical even with escaped content present
esc_before="$(cat "$DASH")"
t render >/dev/null
esc_after="$(cat "$DASH")"
assert_eq "render is byte-identical with escaped content on the board" "$esc_before" "$esc_after"
rm -f "$f_pipe"
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
[[ "$rp_updated" == "$(date '+%Y-%m-%d')"* ]] \
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
[[ "$lg_updated" == "$(date '+%Y-%m-%d')"* ]] \
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
[[ "$hless_predated_updated" == "$(date '+%Y-%m-%d')"* ]] \
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
[[ "$nested_updated_after" == "$(date '+%Y-%m-%d')"* ]] \
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
[[ "$cr_updated" == "$(date '+%Y-%m-%d')"* ]] \
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
[[ "$ed_updated" == "$(date '+%Y-%m-%d')"* ]] \
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

echo
printf 'Result: \033[0;32m%d passed\033[0m, ' "$pass"
if ((fail > 0)); then printf '\033[0;31m%d failed\033[0m' "$fail"; else printf '%d failed' "$fail"; fi
if ((skip > 0)); then printf ', \033[0;33m%d skipped\033[0m' "$skip"; fi
printf '\n'
((fail == 0)) || exit 1
