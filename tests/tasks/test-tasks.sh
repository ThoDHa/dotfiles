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

echo
printf 'Result: \033[0;32m%d passed\033[0m, ' "$pass"
if ((fail > 0)); then printf '\033[0;31m%d failed\033[0m\n' "$fail"; exit 1; fi
printf '%d failed\n' "$fail"
