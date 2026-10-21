#!/usr/bin/env bash
#
# Staleness check for the generated pi instruction file: regenerates
# AGENTS.md into a temp scratch dir through the generator's output-path
# argument and diffs it against ~/.pi/agent/AGENTS.md. The generator's
# output-path contract runs on every host (scratch-only); only the host
# compare and the comparator self-test skip when ~/.pi/agent/AGENTS.md
# is absent (CI has no pi deployment and no artifact). The staleness
# check fails with a summarized diff and the sync remediation when
# stale. The comparator is self-tested against a doctored scratch copy
# so a comparator that can no longer detect drift fails loudly instead
# of passing vacuously. Host state is never written.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATOR="$REPO_ROOT/pi/generate-agents-md.sh"
HOST_FILE="$HOME/.pi/agent/AGENTS.md"
REMEDIATION="run make sync-agents-md"
DIFF_SUMMARY_LINES=12

source "$REPO_ROOT/tests/lib/harness.sh"

report_stale() { # fresh actual; prints the diff summary and the remediation
	echo "  Stale AGENTS.md: $2 does not match a fresh generation of the rules."
	echo "  Diff summary (first $DIFF_SUMMARY_LINES lines, fresh vs host):"
	diff -u "$1" "$2" | sed -n "1,${DIFF_SUMMARY_LINES}p" | sed 's/^/    /' || true
	echo "  Remediation: $REMEDIATION"
}

compare_fresh() { # label fresh actual; ok on byte-identity, bad plus summary otherwise
	if cmp -s "$2" "$3"; then
		ok "$1"
		return 0
	fi
	bad "$1"
	report_stale "$2" "$3"
	return 1
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# Pre-generation snapshot for the host-untouched assertion below; unset
# on hosts without the file, which skip the host section that uses it.
if [[ -f "$HOST_FILE" ]]; then
	host_before="$(cat "$HOST_FILE")"
fi

echo "== generator: output-path contract (scratch only) =="
# Both runs land in the scratch dir, so this section is host-independent
# and guards the generator on CI too. Each path nests one level so the
# runs also prove the generator creates a missing output parent; the
# first copy doubles as the fresh reference for the staleness check.
fresh="$ROOT/fresh/AGENTS.md"
fresh_again="$ROOT/again/deeper/AGENTS.md"
if "$GENERATOR" "$fresh" >/dev/null 2>&1; then
	ok "generator accepts an output-path argument"
else
	bad "generator accepts an output-path argument"
fi
[[ -s "$fresh" ]] && ok "explicit output path receives a non-empty file" \
	|| bad "explicit output path receives a non-empty file"
if "$GENERATOR" "$fresh_again" >/dev/null 2>&1; then
	ok "repeat generation to another path succeeds"
else
	bad "repeat generation to another path succeeds"
fi
cmp -s "$fresh" "$fresh_again" \
	&& ok "repeat generation to another path is byte-identical (deterministic)" \
	|| bad "repeat generation to another path is byte-identical (deterministic)"

# Overwrite idempotence: a third run against the SAME scratch path as the
# first run. Every path above was fresh, so a generator regression that
# appends its header instead of truncating still passes the determinism
# check; against an already-populated path it doubles the file and fails.
first_pass="$ROOT/first-pass.md"
cp "$fresh" "$first_pass"
if overwrite_out="$("$GENERATOR" "$fresh" 2>/dev/null)"; then
	ok "repeat generation to the same path succeeds"
else
	bad "repeat generation to the same path succeeds"
fi
cmp -s "$first_pass" "$fresh" \
	&& ok "repeat generation to the same path is byte-identical (idempotent overwrite)" \
	|| bad "repeat generation to the same path is byte-identical (idempotent overwrite)"

# Header contract: the provenance paragraph names the exact reconcile
# commands, independent of host state so the pin holds on CI too.
header="$(sed -n '3p' "$fresh")"
assert_contains "provenance paragraph names make sync-agents-md" "$header" "make sync-agents-md"
assert_contains "provenance paragraph names make test-agents-md" "$header" "make test-agents-md"

# Section order: the four rule bodies appear in the documented fixed
# order. The actual sequence is derived at test time from the rules
# directory the generator itself resolved (printed on its stdout), so a
# deterministic reordering inside the generator fails, and a rule file
# added to the rules dir fails too: the doc's contract is the named four,
# so widening it must be a deliberate spec change.
rules_dir="$(sed -n 's/^[[:space:]]*Rules source: //p' <<<"$overwrite_out")"
expected_order="core.md"$'\n'"coding-standards.md"$'\n'"execution-standards.md"$'\n'"qhaway-memory.md"
actual_order="$(for rule_path in "$rules_dir"/*.md; do
	[[ -e "$rule_path" ]] || continue
	anchor="$(head -n 1 "$rule_path")"
	line="$(grep -nF -- "$anchor" "$fresh" | head -n1 | cut -d: -f1)"
	printf '%s %s\n' "$line" "${rule_path##*/}"
done | sort -n | cut -d' ' -f2)"
assert_eq "rule bodies follow the documented fixed order" \
	"$expected_order" "$actual_order"

if [[ ! -f "$HOST_FILE" ]]; then
	skip_test "no ~/.pi/agent/AGENTS.md on this host; host sync check skipped"
else
	echo "== sync: regenerated file matches the host copy =="
	assert_eq "host AGENTS.md untouched by the scratch runs" \
		"$host_before" "$(cat "$HOST_FILE")"
	compare_fresh "regenerated AGENTS.md is byte-identical to ~/.pi/agent/AGENTS.md" \
		"$fresh" "$HOST_FILE"

	echo "== comparator self-test (doctored scratch copy, host untouched) =="
	doctored="$ROOT/doctored-AGENTS.md"
	tail -n +2 "$fresh" >"$doctored"
	# The command substitution is a subshell, so the probe's verdict lands in
	# selftest_rc instead of the suite counters.
	selftest_out="$(compare_fresh "comparator probe" "$fresh" "$doctored")"
	selftest_rc=$?
	assert_eq "comparator detects a deleted line as stale" "1" "$selftest_rc"
	assert_contains "stale report carries the remediation line" "$selftest_out" "$REMEDIATION"
	assert_contains "stale report summarizes the diff" "$selftest_out" "-# User Instructions (AGENTS.md)"
fi

print_result
((fail == 0)) || exit 1
