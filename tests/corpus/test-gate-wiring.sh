#!/usr/bin/env bash
#
# Wiring pin for the corpus gates (the 10-3 gate-list gap): CORP-1
# proved a landing gate list can cherry-pick suites and never run the
# corpus checks (advisor.md landed 99 lines against the 95 budget
# undetected), so the Makefile wires the gates as prerequisites of
# every suite target a gate list can name and this suite pins that
# wiring. For every pinned target, a make -n dry run must execute all
# four corpus gates: lint-corpus (the INVENTORY census checks ride
# inside it), test-agents-md, test-pi-agents, and test-pi-extensions.
# The gate targets themselves are excluded from the pin list: they are
# the gates, and keeping them prerequisite-free is what keeps the
# graph acyclic. Any gate list naming any test target then meets all
# four gates. The gate detector is self-tested against gate-less dry
# run output so a detector that can no longer spot missing wiring
# fails loudly instead of passing vacuously. Beside the per-target
# loop, the review-fold pins hold the outer edges and the wiring
# surface itself: make -n check must expose all four gate recipes
# transitively and make -n verify must chain to verify-inner (the
# aggregate outer edges a gate list can name); an aggregate dry run
# must emit no Circular warning (the acyclic graph is pinned, not
# accidental); and the wired set is derived against the Makefile
# text - the count of ': $(CORPUS_GATES)' wiring lines and the
# universe of declared test targets are diffed against this suite's
# lists, so a suite target added with or without the gates, or any
# other edit to the wiring surface, fails loudly in both directions
# until the pin is consciously updated. Dry-run only: make -n
# executes no recipe, and the suite writes nothing outside this
# process.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$REPO_ROOT/tests/lib/harness.sh"

# Assertion total for the self-pin: 19 pinned targets x 5 (one make -n
# exit check plus four gate checks) + 5 detector self-test checks + 5
# outer-edge and derived-set checks (check gates, acyclicity, verify
# chain, wiring-line count, target-universe diff).
EXPECTED_ASSERTIONS=105

# Every suite target a landing gate list can name that is not itself a
# corpus gate, the pin's own target, and the two aggregates whose
# explicit prerequisite lists must not lose the gates.
WIRED_TARGETS=(
	test-smoke
	test-links
	test-rules
	test-tasks
	test-tasks-hazard
	test-task-metrics
	test-task-access-drift
	test-task-access-replay
	test-task-access-tierb
	test-pi-extractor
	test-oc-continue
	test-pi-continue
	test-pi
	test-task-storage-pi
	test-task-storage-opencode
	test-task-storage-adversarial
	test-gate-wiring
	test
	verify-inner
)

# The recipe line each corpus gate contributes to a make -n dry run.
GATE_RECIPE_LINES=(
	"bash tests/corpus/lint-corpus.sh"
	"bash tests/agents-md/test-sync.sh"
	"bash tests/pi-agents/test-sync.sh"
	"bash tests/pi-extensions/test-sync.sh"
)

missing_gates() { # dry-run output; prints each gate recipe line absent from it
	local output="$1" gate
	for gate in "${GATE_RECIPE_LINES[@]}"; do
		grep -qF -- "$gate" <<<"$output" || printf '%s\n' "$gate"
	done
}

gate_lines_minus() { # omit-index; prints the gate recipe lines except that one
	local omit="$1" i
	for ((i = 0; i < ${#GATE_RECIPE_LINES[@]}; i++)); do
		((i == omit)) || printf '%s\n' "${GATE_RECIPE_LINES[$i]}"
	done
}

section "detector self-test (gate-less dry runs must be flagged)"
for ((i = 0; i < ${#GATE_RECIPE_LINES[@]}; i++)); do
	missing="$(missing_gates "$(gate_lines_minus "$i")")"
	assert_eq "detector flags a dry run missing ${GATE_RECIPE_LINES[$i]}" "${GATE_RECIPE_LINES[$i]}" "$missing"
done
missing="$(missing_gates "$(printf '%s\n' "${GATE_RECIPE_LINES[@]}")")"
assert_eq "detector passes a dry run carrying every gate" "" "$missing"

section "wiring (every gate-listable target runs the corpus gates)"
for target in "${WIRED_TARGETS[@]}"; do
	output="$(make -C "$REPO_ROOT" -n "$target" 2>&1)"; rc=$?
	assert_eq "$target: make -n dry run exits clean" "0" "$rc"
	for gate in "${GATE_RECIPE_LINES[@]}"; do
		assert_contains "$target: dry run executes $gate" "$output" "$gate"
	done
done

section "outer edges and derived wired set (review L1 L2 DC1)"
check_dry_run="$(make -C "$REPO_ROOT" -n check 2>&1)"
assert_eq "check: dry run executes every corpus gate transitively" "" "$(missing_gates "$check_dry_run")"
assert_not_contains "aggregate dry run emits no Circular warning (acyclicity pin)" "$check_dry_run" "Circular"
verify_dry_run="$(make -C "$REPO_ROOT" -n verify 2>&1)"
assert_contains "verify: dry run chains to verify-inner (the gate-carrying aggregate)" "$verify_dry_run" "make verify-inner"

wired_line_count="$(grep -cE '^[A-Za-z0-9_.-]+:[[:space:]]*\$\(CORPUS_GATES\)' "$REPO_ROOT/Makefile")"
assert_eq 'Makefile wiring lines matching ": $(CORPUS_GATES)" number exactly 17' "17" "$wired_line_count"

declared_gates="$(sed -nE 's/^CORPUS_GATES[[:space:]]*[:?+]?=[[:space:]]*(.*)$/\1/p' "$REPO_ROOT/Makefile")"
discovered_universe="$(grep -oE '^test[A-Za-z0-9_-]*:' "$REPO_ROOT/Makefile" | sed 's/:$//' | LC_ALL=C sort -u)"
expected_universe="$( { printf '%s\n' "${WIRED_TARGETS[@]}"; printf '%s\n' "$declared_gates"; } | tr ' ' '\n' | grep -E '^test[A-Za-z0-9_-]*$' | LC_ALL=C sort -u )"
assert_eq "wired-set derivation: every Makefile test target is pinned or a declared gate" "" "$(LC_ALL=C comm -3 <(printf '%s\n' "$expected_universe") <(printf '%s\n' "$discovered_universe"))"

print_result
((fail == 0)) || exit 1
