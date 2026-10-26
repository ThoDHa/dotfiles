#!/usr/bin/env bash
#
# Staleness check for the generated Claude Code instruction file:
# regenerates CLAUDE.md into a temp scratch dir through the generator's
# output-path argument and diffs it against ~/.claude/CLAUDE.md. The
# generator's output-path contract runs on every host (scratch-only);
# only the host compare and the comparator self-test skip when
# ~/.claude/CLAUDE.md is absent (CI has no claude and no artifact).
# The staleness check fails with a summarized diff and the sync
# remediation when stale. The comparator is self-tested against a
# doctored scratch copy so a comparator that can no longer detect drift
# fails loudly instead of passing vacuously. Host state is never written.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATOR="$REPO_ROOT/claudecode/.claude/generate-claude-md.sh"
HOST_FILE="$HOME/.claude/CLAUDE.md"
REMEDIATION="run make sync-claudecode"
DIFF_SUMMARY_LINES=12

source "$REPO_ROOT/tests/lib/harness.sh"

ARTIFACT_NOUN="CLAUDE.md"
PROVENANCE_PHRASE="does not match a fresh generation of the rules."
source "$REPO_ROOT/tests/lib/sync-comparator.sh"

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
fresh="$ROOT/fresh/CLAUDE.md"
fresh_again="$ROOT/again/deeper/CLAUDE.md"
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

# Section order: core.md first, then the remaining rule basenames
# alphabetically. The expected sequence is derived at test time from the
# rules directory the generator itself resolved (printed on its stdout),
# so adding or removing a rule file stays green while any deterministic
# reordering inside the generator fails.
rules_dir="$(sed -n 's/^[[:space:]]*Rules source: //p' <<<"$overwrite_out")"
derived_order="core.md"
for rule_path in "$rules_dir"/*.md; do
	[[ -e "$rule_path" ]] || continue
	rule_name="${rule_path##*/}"
	[[ "$rule_name" == "core.md" ]] && continue
	derived_order+=$'\n'"$rule_name"
done
actual_order="$(sed -n 's/^## Rule File: //p' "$fresh")"
assert_eq "rule file sections follow core.md-first alphabetical order" \
	"$derived_order" "$actual_order"

if [[ ! -f "$HOST_FILE" ]]; then
	skip_test "no ~/.claude/CLAUDE.md on this host; host sync check skipped"
else
	echo "== sync: regenerated file matches the host copy =="
	assert_eq "host CLAUDE.md untouched by the scratch runs" \
		"$host_before" "$(cat "$HOST_FILE")"
	compare_fresh "regenerated CLAUDE.md is byte-identical to ~/.claude/CLAUDE.md" \
		"$fresh" "$HOST_FILE"

	echo "== comparator self-test (doctored scratch copy, host untouched) =="
	doctored="$ROOT/doctored-CLAUDE.md"
	tail -n +2 "$fresh" >"$doctored"
	# The command substitution is a subshell, so the probe's verdict lands in
	# selftest_rc instead of the suite counters.
	selftest_out="$(compare_fresh "comparator probe" "$fresh" "$doctored")"
	selftest_rc=$?
	assert_eq "comparator detects a deleted line as stale" "1" "$selftest_rc"
	assert_contains "stale report names the artifact and provenance phrase" \
		"$selftest_out" "Stale CLAUDE.md: $doctored does not match a fresh generation of the rules."
	assert_contains "stale report carries the remediation line" "$selftest_out" "$REMEDIATION"
	assert_contains "stale report summarizes the diff" "$selftest_out" "-# Claude Code Instructions"
fi

print_result
((fail == 0)) || exit 1
