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

ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }

assert_eq() { # label expected actual
	if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
assert_contains() { # label haystack needle
	if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing [$3])"; fi
}
assert_not_contains() { # label haystack needle
	if grep -qF -- "$3" <<<"$2"; then bad "$1 (unexpected [$3])"; else ok "$1"; fi
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export TASKS_DIR="$ROOT/.tasks"
DASH="$TASKS_DIR/dashboard.md"

t() { "$TASKS_BIN" "$@"; }

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
t claim "$f_tr" --owner "intruder" >/dev/null 2>&1 && bad "second claim should fail" || ok "second claim rejected"

echo "== release clears claim and owner =="
t release "$f_tr" >/dev/null
[[ ! -f "$f_tr.claim" ]] && ok "sidecar removed on release" || bad "sidecar removed on release"
owner_after="$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_tr" || true)"
assert_eq "Owner cleared on release" "" "${owner_after:-}"

echo "== blocked lane =="
t set "$f_tr" Status=Blocked >/dev/null
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
t set "$f_cs" Status=Bogus >/dev/null 2>&1 && bad "set rejects an unknown status" || ok "set rejects an unknown status"
assert_contains "rejected status leaves the file untouched" \
	"$(grep -oP '^\*\*Status:\*\*\s+\K.*' "$f_cs")" "Triage"
t new --id API-5 --name "Bogus Status Task" --status Bogus >/dev/null 2>&1 \
	&& bad "new rejects an unknown status" || ok "new rejects an unknown status"
if t set "$f_cs" Status=Blocked >/dev/null 2>&1; then ok "set accepts a valid status"; else bad "set accepts a valid status"; fi
t set "$f_cs" Status=Triage >/dev/null

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
t claim "$f_cs" --owner newcomer >/dev/null 2>&1 \
	&& bad "claim under a stale sidecar is rejected" || ok "claim under a stale sidecar is rejected"
claim_err="$(t claim "$f_cs" --owner newcomer 2>&1 >/dev/null || true)"
assert_contains "rejection names the stale owner" "$claim_err" "stale-session"
t release "$f_cs" >/dev/null
[[ ! -f "$f_cs.claim" ]] && ok "release removes the stale sidecar" || bad "release removes the stale sidecar"
owner_now="$(grep -oP '^\*\*Owner:\*\*\s+\K.*' "$f_cs" || true)"
assert_eq "release clears Owner even for a stale claim" "" "${owner_now:-}"
# With no sidecar present, a claim failure must be reported as a create
# failure, not conflated with "already claimed".
perm_dir="$TASKS_DIR/current"
perm_mode="$(stat -c %a "$perm_dir")"
chmod 500 "$perm_dir"
perm_err="$(t claim "$f_cs" --owner someone 2>&1 >/dev/null || true)"
chmod "$perm_mode" "$perm_dir"
assert_contains "permission failure is reported as a create failure" "$perm_err" "cannot create"
assert_not_contains "permission failure is not misreported as claimed" "$perm_err" "already claimed"
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

echo
printf 'Result: \033[0;32m%d passed\033[0m, ' "$pass"
if ((fail > 0)); then printf '\033[0;31m%d failed\033[0m\n' "$fail"; exit 1; fi
printf '%d failed\n' "$fail"
