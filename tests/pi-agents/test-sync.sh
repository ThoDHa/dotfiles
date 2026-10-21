#!/usr/bin/env bash
#
# Staleness check for the compiled pi agent files: regenerates the
# ~/.pi/agent/agents set into a temp scratch dir through the generator's
# output-dir argument and diffs every file against the live copy. The
# generator's output-dir contract runs on every host (scratch-only);
# only the host compare and the comparator self-test skip when
# ~/.pi/agent/agents is absent (CI and the verify container have no pi).
# The staleness check fails with a summarized diff and the sync
# remediation when stale. The comparator is self-tested against a
# doctored scratch copy so a comparator that can no longer detect drift
# fails loudly instead of passing vacuously. Host state is never
# written.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATOR="$REPO_ROOT/opencode/.config/opencode/agents/generate-pi-agents.sh"
HOST_DIR="$HOME/.pi/agent/agents"
REMEDIATION="run make sync-pi-agents"
DIFF_SUMMARY_LINES=12

source "$REPO_ROOT/tests/lib/harness.sh"

report_stale() { # fresh actual; prints the diff summary and the remediation
	echo "  Stale pi agents: $2 does not match a fresh compilation of the fleet."
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
# on hosts without the directory, which skip the host section that uses it.
if [[ -d "$HOST_DIR" ]]; then
	host_snapshot="$ROOT/host-before"
	mkdir -p "$host_snapshot"
	cp "$HOST_DIR"/*.md "$host_snapshot/" 2>/dev/null || true
fi

echo "== generator: output-dir contract (scratch only) =="
# Both runs land in the scratch dir, so this section is host-independent
# and guards the generator on CI too. Nested output paths prove the
# generator creates missing parents; the first run doubles as the fresh
# reference for the staleness check.
fresh="$ROOT/fresh/agents"
fresh_again="$ROOT/again/deeper/agents"
if "$GENERATOR" "$fresh" >/dev/null 2>&1; then
	ok "generator accepts an output-dir argument"
else
	bad "generator accepts an output-dir argument"
fi
# The anchor is intentionally loose (^# pi: without the trailing space):
# a near-miss directive is counted here but skipped by the generator's
# strict '^# pi: ' matcher, so the typo fails these assertions loudly
# instead of dropping the file from the pi fleet with a green suite.
expected_count="$(grep -lE '^# pi:' "$REPO_ROOT"/opencode/.config/opencode/agents/*.md | wc -l)"
actual_count="$(find "$fresh" -maxdepth 1 -name '*.md' | wc -l)"
[[ "$actual_count" -gt 0 ]] && ok "scratch run generates agent files ($actual_count)" \
	|| bad "scratch run generates agent files ($actual_count)"
[[ "$actual_count" -eq "$expected_count" ]] \
	&& ok "one generated file per pi-targeted fleet source ($actual_count)" \
	|| bad "one generated file per pi-targeted fleet source (expected $expected_count, got $actual_count)"
expected_names="$(grep -lE '^# pi:' "$REPO_ROOT"/opencode/.config/opencode/agents/*.md | xargs -n1 basename | sort)"
actual_names="$(find "$fresh" -maxdepth 1 -name '*.md' -exec basename {} \; | sort)"
[[ "$actual_names" == "$expected_names" ]] \
	&& ok "generated basename set matches the directive-bearing source set" \
	|| bad "generated basename set matches the directive-bearing source set"
if "$GENERATOR" "$fresh_again" >/dev/null 2>&1; then
	ok "repeat generation to another dir succeeds"
else
	bad "repeat generation to another dir succeeds"
fi
diff -r "$fresh" "$fresh_again" >/dev/null 2>&1 \
	&& ok "repeat generation to another dir is byte-identical (deterministic)" \
	|| bad "repeat generation to another dir is byte-identical (deterministic)"

# Overwrite idempotence: a third run against the SAME scratch dir as the
# first run. Every dir above was fresh, so a generator regression that
# appends instead of replacing still passes the determinism check;
# against an already-populated dir it doubles content and fails.
first_pass="$ROOT/first-pass"
cp -r "$fresh" "$first_pass"
if overwrite_out="$("$GENERATOR" "$fresh" 2>/dev/null)"; then
	ok "repeat generation to the same dir succeeds"
else
	bad "repeat generation to the same dir succeeds"
fi
diff -r "$first_pass" "$fresh" >/dev/null 2>&1 \
	&& ok "repeat generation to the same dir is byte-identical (idempotent overwrite)" \
	|| bad "repeat generation to the same dir is byte-identical (idempotent overwrite)"

# pi frontmatter shape: every generated file must open with exactly the
# four keys pi's loader consumes (name, description, model, tools), a
# bare model id (no provider prefix), and the shared body's first
# paragraph intact (the dual-harness preamble where the source has one).
for f in "$fresh"/*.md; do
	name="$(basename "$f" .md)"
	head -n 6 "$f" | grep -qE '^---$' \
		&& head -n 6 "$f" | grep -qE '^name: [a-z-]+$' \
		&& head -n 6 "$f" | grep -qE '^description: .+$' \
		&& head -n 6 "$f" | grep -qE '^model: [a-z0-9.-]+$' \
		&& head -n 6 "$f" | grep -qE '^tools: [a-z, ]+$' \
		&& ok "$name.md carries the four pi frontmatter keys with a bare model id" \
		|| bad "$name.md carries the four pi frontmatter keys with a bare model id"
	if grep -qE '^model: .+/.+' "$f"; then
		bad "$name.md model id is bare (no provider prefix)"
	else
		ok "$name.md model id is bare (no provider prefix)"
	fi
done

if [[ ! -d "$HOST_DIR" ]]; then
	skip_test "no ~/.pi/agent/agents on this host; host sync check skipped"
else
	echo "== sync: regenerated files match the host copies =="
	diff -r "$host_snapshot" "$HOST_DIR" >/dev/null 2>&1 \
		&& ok "host pi agents untouched by the scratch runs" \
		|| bad "host pi agents untouched by the scratch runs"
	stale=0
	for f in "$fresh"/*.md; do
		name="$(basename "$f")"
		[[ -f "$HOST_DIR/$name" ]] || { bad "host is missing $name (present in fleet)"; stale=1; continue; }
		compare_fresh "regenerated $name is byte-identical to ~/.pi/agent/agents/$name" \
			"$f" "$HOST_DIR/$name" || stale=1
	done
	for f in "$HOST_DIR"/*.md; do
		name="$(basename "$f")"
		[[ -f "$fresh/$name" ]] || { bad "host has $name with no fleet source (stale leftover)"; stale=1; }
	done

	echo "== comparator self-test (doctored scratch copy, host untouched) =="
	doctored="$ROOT/doctored-agents"
	mkdir -p "$doctored"
	grep -v '^model: ' "$fresh/worker.md" >"$doctored/worker.md"
	# The command substitution is a subshell, so the probe's verdict lands
	# in selftest_rc instead of the suite counters.
	selftest_out="$(compare_fresh "comparator probe" "$fresh/worker.md" "$doctored/worker.md")"
	selftest_rc=$?
	assert_eq "comparator detects a deleted line as stale" "1" "$selftest_rc"
	assert_contains "stale report carries the remediation line" "$selftest_out" "$REMEDIATION"
	assert_contains "stale report summarizes the diff" "$selftest_out" "-model:"
fi

print_result
((fail == 0)) || exit 1
