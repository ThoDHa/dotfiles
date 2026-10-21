# Shared test harness for the repo's Result-line suites:
# tests/tasks/test-tasks.sh, tests/oc-continue/test-oc-continue.sh,
# tests/claudecode/test-sync.sh, and tests/agents-md/test-sync.sh. lint-corpus.sh runs a different contract
# (fail-fast lint, no counters) and is out of bounds here. Sourcing it
# defines the per-suite pass/fail/skip counters, the ok/bad/skip_test
# printers, the assert_eq/assert_contains/assert_not_contains family, and
# print_result, the summary line each suite prints before its own
# `((fail == 0)) || exit 1` exit contract. Suites source it through their
# own BASH_SOURCE-derived REPO_ROOT. Counters are in-process: a helper
# invoked inside $( ) or a pipeline reports into the subshell and the
# suite counters silently miss it; capture the verdict in the parent
# (test-sync.sh's selftest_rc comparator self-test is the pattern).
# Requires bash 4.4+: suites expand possibly-empty arrays ("${arr[@]}") under set -u, which errors on bash < 4.4.

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

print_result() {
	printf '\nResult: \033[0;32m%d passed\033[0m, ' "$pass"
	if ((fail > 0)); then printf '\033[0;31m%d failed\033[0m' "$fail"; else printf '%d failed' "$fail"; fi
	if ((skip > 0)); then printf ', \033[0;33m%d skipped\033[0m' "$skip"; fi
	printf '\n'
}
