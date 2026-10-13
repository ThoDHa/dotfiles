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

report_stale() { # fresh actual; prints the diff summary and the remediation
	echo "  Stale CLAUDE.md: $2 does not match a fresh generation of the rules."
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

print_result() {
	printf '\nResult: \033[0;32m%d passed\033[0m, ' "$pass"
	if ((fail > 0)); then printf '\033[0;31m%d failed\033[0m' "$fail"; else printf '%d failed' "$fail"; fi
	if ((skip > 0)); then printf ', \033[0;33m%d skipped\033[0m' "$skip"; fi
	printf '\n'
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
	assert_contains "stale report carries the remediation line" "$selftest_out" "$REMEDIATION"
	assert_contains "stale report summarizes the diff" "$selftest_out" "-# Claude Code Instructions"
fi

print_result
((fail == 0)) || exit 1
