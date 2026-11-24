# Shared test harness for the repo's Result-line suites:
# tests/tasks/test-tasks.sh, tests/tasks/test-tasks-hazard.sh,
# tests/task-metrics/test-task-metrics.sh, tests/oc-continue/test-oc-continue.sh,
# tests/pi-continue/test-pi-continue.sh, tests/agents-md/test-sync.sh,
# tests/pi-agents/test-sync.sh, and tests/pi/test-pi.sh.
# lint-corpus.sh runs a different contract
# (fail-fast lint, no counters) and is out of bounds here. Sourcing it
# defines the per-suite pass/fail/skip counters, the ok/bad/skip_test
# printers, the assert_eq/assert_contains/assert_not_contains family, and
# print_result, the summary line each suite prints before its own
# `((fail == 0)) || exit 1` exit contract. Suites source it through their
# own BASH_SOURCE-derived REPO_ROOT. Counters are in-process: a helper
# invoked inside $( ) or a pipeline reports into the subshell and the
# suite counters silently miss it; capture the verdict in the parent
# (test-sync.sh's selftest_rc comparator self-test is the pattern).
# Self-pin (opt in): a suite declares EXPECTED_ASSERTIONS=<total> and
# replaces its `echo "== name =="` headers with `section "name"`.
# print_result then checks at END, in both directions, that the
# sections declared in the suite's own source (the file is the
# manifest) and the sections that registered at runtime cover each
# other exactly: a manifest name that never registered and a
# registration the manifest cannot see both fail, naming the section.
# A derivation that cannot read the suite file, or that yields an
# empty manifest while the registry proves the suite adopted the
# mechanism, is itself a loud failure, never a vacuously-passing
# empty set. The pass total must also match the declaration. Each
# violation increments fail so the suite's exit gate fires; a green
# run therefore cannot hide a section that never started, a shrunk
# assertion count, or a manifest that stopped seeing real call
# sites. Suites that do neither are unaffected. section inherits the
# in-process counter constraint above.
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

SUITE_FILE="${BASH_SOURCE[1]:-}"
SECTION_REGISTRY=()
SECTION_STARTS=()
declare -A SECTION_SEEN

section() { # name: print the section header and register the start for print_result's END checks
	printf '== %s ==\n' "$1"
	SECTION_REGISTRY+=("$1")
	SECTION_STARTS+=("$pass")
	SECTION_SEEN["$1"]=$((${SECTION_SEEN["$1"]:-0} + 1))
}

print_result() {
	local -a expected_sections=() missing=() undeclared=() duplicated=()
	local s i start end manifest_text="" derive_rc=0
	if [[ -n "$SUITE_FILE" ]]; then
		manifest_text=$(sed -nE 's/^[[:space:]]*section "([^"]*)".*/\1/p' "$SUITE_FILE") || derive_rc=$?
	fi
	if ((derive_rc != 0)); then
		printf 'FAIL: self-pin: manifest derivation failed (sed exited %d reading %s): the coverage gate cannot run, fix SUITE_FILE to name the suite source file\n' "$derive_rc" "$SUITE_FILE"
		fail=$((fail + 1))
	elif [[ -z "$manifest_text" ]]; then
		if ((${#SECTION_REGISTRY[@]} > 0)); then
			printf 'FAIL: self-pin: derived section manifest is empty while %d section(s) registered: every call site is silently unpinned, fix the manifest sed so it matches every section "name" line in %s\n' "${#SECTION_REGISTRY[@]}" "${SUITE_FILE:-<SUITE_FILE unset>}"
			fail=$((fail + 1))
		fi
	else
		mapfile -t expected_sections <<<"${manifest_text%$'\n'}"
		local -A expected_set=()
		for s in "${expected_sections[@]}"; do expected_set["$s"]=1; done
		for s in "${expected_sections[@]}"; do
			[[ -n "${SECTION_SEEN[$s]:-}" ]] || missing+=("$s")
		done
		for s in "${!SECTION_SEEN[@]}"; do
			[[ -n "${expected_set[$s]:-}" ]] || undeclared+=("$s")
			if ((${SECTION_SEEN[$s]} > 1)); then duplicated+=("$s"); fi
		done
		if ((${#missing[@]} > 0)); then
			printf 'FAIL: self-pin: %d of %d declared sections never ran (dropped or lost to a subshell):\n' "${#missing[@]}" "${#expected_sections[@]}"
			for s in "${missing[@]}"; do printf '    == %s ==\n' "$s"; done
			fail=$((fail + 1))
		fi
		if ((${#undeclared[@]} > 0)); then
			printf 'FAIL: self-pin: %d registered section(s) absent from the static manifest (call sites the derivation cannot see, e.g. not a literal section "name" line):\n' "${#undeclared[@]}"
			for s in "${undeclared[@]}"; do printf '    section "%s"\n' "$s"; done
			fail=$((fail + 1))
		fi
		if ((${#duplicated[@]} > 0)); then
			printf 'FAIL: self-pin: sections registered more than once: %s\n' "${duplicated[*]}"
			fail=$((fail + 1))
		fi
	fi
	if [[ -n "${EXPECTED_ASSERTIONS:-}" ]] && ((pass != EXPECTED_ASSERTIONS)); then
		printf 'FAIL: self-pin: assertion total drift: %d passed, the suite declares %d (bump EXPECTED_ASSERTIONS in the suite only with the change that shifts it); per-section contributions:\n' "$pass" "$EXPECTED_ASSERTIONS"
		for ((i = 0; i < ${#SECTION_REGISTRY[@]}; i++)); do
			start="${SECTION_STARTS[i]}"
			end="${SECTION_STARTS[$((i + 1))]:-$pass}"
			printf '    %s: %d\n' "${SECTION_REGISTRY[i]}" "$((end - start))"
		done
		fail=$((fail + 1))
	fi
	printf '\nResult: \033[0;32m%d passed\033[0m, ' "$pass"
	if ((fail > 0)); then printf '\033[0;31m%d failed\033[0m' "$fail"; else printf '%d failed' "$fail"; fi
	if ((skip > 0)); then printf ', \033[0;33m%d skipped\033[0m' "$skip"; fi
	printf '\n'
}
