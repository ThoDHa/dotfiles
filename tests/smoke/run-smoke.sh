#!/usr/bin/env bash
#
# Agent-contract smoke harness for the manager routing surface: the
# ORCH-4-6 blocking entry-criterion instrument (consolidation-5 Criterion
# 1, DC2) and the equivalence-check instrument for every prompt-soft
# Flash-era candidate the slimming wave touches (FL-01/02/04/06 directly,
# FL-05 until the doctor owns it).
#
# Three modes:
#
#   run-smoke.sh --validate
#       Hermetic instrument check: every scenario file parses against the
#       registry (id, RO key, FL key), every declared fixture exists, the
#       S6 prompt carries the seven routing class names verbatim (the
#       names are the pin; file line ranges never are), and the grader
#       self-test passes over synthetic transcripts. No model calls; this
#       is the mode chained into make test / make verify-inner as
#       test-smoke.
#
#   run-smoke.sh [--scenario S1] [--model provider/id] [--thinking LEVEL]
#                [--run-dir DIR]
#       Live mode, explicit invocation only (never chained): per scenario,
#       dispatch the manager body under test headless through pi inside a
#       fixture-bounded scratch working directory and grade the JSON
#       transcript mechanically against the scenario rubric. Development
#       mode: one body, absolute verdicts, any FAIL/ERROR/timeout exits
#       nonzero.
#
#   run-smoke.sh --paired [--scenario S1] [--model provider/id]
#                [--thinking LEVEL] [--run-dir DIR] [--baseline-ref REF]
#       Paired delta mode, explicit invocation only (never chained): per
#       scenario, dispatch baseline and tip bodies back to back in the
#       same time window (baseline body from --baseline-ref, default main;
#       tip body from the worktree) and grade both, then emit a
#       per-scenario delta table. Gate semantics are delta-based over the
#       gating registry S1-S7 (S8-S10 are advisory): RED only on tip FAIL
#       where baseline PASS (a regression the corpus edit caused);
#       both-FAIL is instrument-inconclusive drift, recorded but not red;
#       otherwise green. Exit 0 green-by-delta, 1 regression, 2 when no
#       gating scenario produced any green/regression evidence (an
#       entirely broken instrument must not exit 0).
#
# Live composition contract (held constant across baseline and post-edit
# runs so a delta is attributable to the corpus edit alone): the session is
# pi preamble plus the fleet manager body extracted from the worktree
# source, injected via --append-system-prompt with Manager Mode's deployed
# body suppressed (PI_MANAGER_MODE=off, so exactly one charter, the file
# under test); the rules chain, skills, prompt templates, and MCP are off;
# extensions stay on so the subagent tool exists and fleet dispatches run
# for real. The graded behaviors (triage, stamp, relay, seven-class
# routing, escalation lanes, watchdog) are charter mechanics; the harness
# binds to the corpus under test by injection, never by host deployment,
# which points at the main tree and not this worktree.
#
# Live runs land under /tmp/llm/smoke/<run-id>/ (transcript.jsonl,
# reply.txt, verdict per scenario, plus a manifest line each), the battery
# links them from its deposit, and the mode's exit status is the gate:
# any FAIL, ERROR, or timeout exits nonzero. Nothing here ever skips a
# scenario silently.

set -uo pipefail

# Keep bytecode caches out of the worktree: the library is imported on
# every invocation and its __pycache__ artifact must never reach git.
export PYTHONDONTWRITEBYTECODE=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/tests/smoke/smoke_lib.py"
SCENARIO_DIR="$REPO_ROOT/tests/smoke/scenarios"
MANAGER_REL="opencode/.config/opencode/agents/manager.md"
FLEET_MANAGER_MD="$REPO_ROOT/$MANAGER_REL"

# Gating registry fixed by the calibration ruling (ORCH-4-6-2 task file,
# Work Log 2026-11-09 23:10): S1-S7 gate the paired delta; S8-S10 are
# advisory until they carry their own baseline plus stability.
GATING_IDS="S1 S2 S3 S4 S5 S6 S7"

usage() {
	echo "usage: run-smoke.sh --validate"
	echo "       run-smoke.sh [--scenario S1] [--model provider/id] [--thinking LEVEL] [--run-dir DIR]"
	echo "       run-smoke.sh --paired [--scenario S1] [--model provider/id] [--thinking LEVEL]"
	echo "                     [--run-dir DIR] [--baseline-ref REF]"
}

die() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$LIB" ]] || die "smoke library missing at $LIB"
[[ -f "$FLEET_MANAGER_MD" ]] || die "fleet manager source missing at $FLEET_MANAGER_MD"
command -v python3 >/dev/null 2>&1 || die "python3 not available"

# Mode split: the first argument decides the mode; every mode then parses
# its own argument tail.
MODE="${1:-}"
case "$MODE" in
	--validate | --paired) shift ;;
	"" | --scenario | --model | --thinking | --run-dir) ;;
	*) usage >&2; exit 2 ;;
esac

is_gating() {
	local up="$1"
	up="${up^^}"
	[[ " $GATING_IDS " == *" $up "* ]]
}

# Extract the manager body (everything below the frontmatter closing ---)
# from an arbitrary manager.md copy, the same extraction
# tests/lib/body-digest.sh pins; kept in step by the pin check, which
# fails if the two ever diverge.
manager_body_from() {
	awk '/^---$/{c++; if (c == 2) { in_body = 1; next } } in_body { print }' "$1"
}

manager_body() { manager_body_from "$FLEET_MANAGER_MD"; }

scenario_path() { # ID -> file path
	local id="$1" file
	file="$(find "$SCENARIO_DIR" -maxdepth 1 -name "${id,,}-*.md" | head -1)"
	[[ -n "$file" ]] || die "no scenario file for $id in $SCENARIO_DIR"
	printf '%s' "$file"
}

all_scenario_ids() {
	local file base id
	for file in "$SCENARIO_DIR"/*.md; do
		base="$(basename "$file" .md)"
		id="${base%%-*}"
		printf '%s\n' "$id"
	done | sort -u
}

run_validate() {
	local rc=0 file id
	echo "Validating the smoke instrument at $SCENARIO_DIR"
	# Shape and registry checks: one python pass over every scenario file,
	# then the S6 class-name pin, then the grader self-test.
	local check_out
	check_out="$(python3 - "$SCENARIO_DIR" "$LIB" <<'PYEOF'
import glob, os, sys
sys.path.insert(0, sys.argv[2].rsplit("/", 1)[0])
import smoke_lib

scenario_dir = sys.argv[1]
failures = 0

def fail(msg):
    global failures
    failures += 1
    print(f"VALIDATE FAIL {msg}")

files = sorted(glob.glob(os.path.join(scenario_dir, "*.md")))
if not files:
    fail("no scenario files found")
seen = {}
s6 = None
for path in files:
    try:
        scenario = smoke_lib.parse_scenario(path)
    except smoke_lib.ScenarioError as exc:
        fail(str(exc))
        continue
    sid = scenario["id"]
    if sid in seen:
        fail(f"duplicate scenario id {sid}: {path} and {seen[sid]}")
    seen[sid] = path
    for name in scenario["fixtures"]:
        fixture = os.path.join(scenario_dir, "..", "fixtures", name)
        if not os.path.isfile(fixture):
            fail(f"{sid}: declared fixture missing: {fixture}")
    if sid == "S6":
        s6 = scenario
missing_ids = sorted(set(smoke_lib.REGISTRY) - set(seen))
if missing_ids:
    fail(f"registry scenarios missing from {scenario_dir}: {missing_ids}")
if s6 is not None:
    corpus = s6["prompt"] + "\n"
    for name in s6["fixtures"]:
        fixture = os.path.join(scenario_dir, "..", "fixtures", name)
        with open(fixture, encoding="utf-8") as fh:
            corpus += fh.read()
    folded = " ".join(corpus.lower().split())
    for class_name in smoke_lib.SEVEN_CLASS_NAMES:
        if " ".join(class_name.lower().split()) not in folded:
            fail(f"S6 lost the seven-class name pin: {class_name!r} not in prompt+fixtures")
print(f"VALIDATE CHECK scenarios: {len(seen)} parsed, registry complete: {failures == 0}")
sys.exit(1 if failures else 0)
PYEOF
)" || rc=1
	echo "$check_out"
	echo "$check_out" | grep -q "VALIDATE FAIL" && rc=1
	local selftest_out
	selftest_out="$(python3 "$LIB" --selftest)" || rc=1
	echo "$selftest_out"
	echo "$selftest_out" | grep -q "SELFTEST FAIL" && rc=1
	if ((rc == 0)); then
		echo "Smoke instrument validate: PASS"
	else
		echo "Smoke instrument validate: FAIL"
	fi
	return "$rc"
}

# Dispatch one scenario and grade it: the atomic unit every live mode
# shares. sid selects the scenario file, body_file is the manager body
# injected as the session charter, sdir receives the transcript, reply,
# checks, and verdict files. Prints the progress, check, and verdict
# lines; the verdict string also lands in "$sdir/verdict.txt" so callers
# can read it back (the paired mode does). Returns 0 iff the verdict is
# PASS.
run_one() {
	local sid="$1" body_file="$2" sdir="$3"
	[[ -s "$body_file" ]] || die "manager body extraction produced nothing (frontmatter unclosed?)"
	local sfile verdict grade_out
	sfile="$(scenario_path "$sid")"
	mkdir -p "$sdir"
	local transcript="$sdir/transcript.jsonl"
	local reply_out="$sdir/reply.txt"
	echo "  [$sid] dispatching ($(basename "$sfile"))..."
	# Parse once per scenario; any grammar violation dies loudly here.
	local fixtures_list prompt timeout_s rc fixture_name fixture_src
	fixtures_list="$(python3 - "$sfile" "$LIB" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[2].rsplit("/", 1)[0])
import smoke_lib
try:
    scenario = smoke_lib.parse_scenario(sys.argv[1])
except smoke_lib.ScenarioError as exc:
    print(f"FAIL: {exc}", file=sys.stderr)
    sys.exit(1)
for name in scenario["fixtures"]:
    print(name)
PYEOF
)" || die "scenario $sid failed to parse"
	# Fixture-bounded workspace: the fixtures the scenario declares are
	# the only files the dispatched session sees in its cwd.
	for fixture_name in $fixtures_list; do
		fixture_src="$REPO_ROOT/tests/smoke/fixtures/$fixture_name"
		[[ -f "$fixture_src" ]] || die "fixture missing: $fixture_src"
		cp "$fixture_src" "$sdir/$fixture_name"
	done
	prompt="$(python3 - "$sfile" "$LIB" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[2].rsplit("/", 1)[0])
import smoke_lib
print(smoke_lib.parse_scenario(sys.argv[1])["prompt"], end="")
PYEOF
)" || die "scenario $sid prompt extraction failed"
	timeout_s="$(awk '/^timeout:/{print $2; exit}' "$sfile")"
	local -a pi_args=(pi -p --mode json --no-session --no-skills --no-mcp
		--no-prompt-templates --no-context-files
		--append-system-prompt "$(cat "$body_file")")
	[[ -n "${model:-}" ]] && pi_args+=(--model "$model")
	[[ -n "${thinking:-}" ]] && pi_args+=(--thinking "$thinking")
	(
		cd "$sdir" || exit 1
		PI_MANAGER_MODE=off timeout "${timeout_s:-900}" \
			"${pi_args[@]}" "$prompt" > "$transcript" 2> "$sdir/dispatch.err"
	)
	rc=$?
	verdict=""
	if ((rc == 124)); then
		verdict="ERROR (timeout after ${timeout_s:-900}s)"
	elif ((rc != 0)); then
		verdict="ERROR (pi exit $rc; see dispatch.err)"
	else
		grade_out="$(python3 - "$transcript" "$sfile" "$LIB" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[3].rsplit("/", 1)[0])
import smoke_lib
scenario = smoke_lib.parse_scenario(sys.argv[2])
verdict, checks = smoke_lib.grade_scenario(scenario, sys.argv[1])
for label, ok, detail in checks:
    print(f"    {'ok' if ok else 'FAIL'}  {label}  [{detail}]")
print(verdict)
PYEOF
)" || verdict="ERROR (grader crashed)"
		if [[ -z "$verdict" ]]; then
			verdict="$(printf '%s\n' "$grade_out" | tail -1)"
			printf '%s\n' "$grade_out" | sed '$d'
			printf '%s\n' "$grade_out" | sed '$d' > "$sdir/checks.txt"
		fi
	fi
	if [[ -s "$transcript" ]]; then
		python3 - "$transcript" "$reply_out" "$LIB" <<'PYEOF' >/dev/null 2>&1 || true
import sys
sys.path.insert(0, sys.argv[3].rsplit("/", 1)[0])
import smoke_lib
_, reply, _, _, _ = smoke_lib.extract_transcript(sys.argv[1])
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write(reply)
PYEOF
	fi
	echo "  [$sid] verdict: $verdict"
	printf '%s\n' "$verdict" > "$sdir/verdict.txt"
	[[ "$verdict" == "PASS" ]]
}

run_live() {
	local scenarios=() model="" thinking="" run_dir=""
	while (($#)); do
		case "$1" in
			--scenario)
				[[ -n "${2:-}" ]] || die "--scenario needs an id"
				scenarios+=("$2"); shift 2 ;;
			--model) model="${2:-}"; [[ -n "$model" ]] || die "--model needs a value"; shift 2 ;;
			--thinking) thinking="${2:-}"; shift 2 ;;
			--run-dir) run_dir="${2:-}"; shift 2 ;;
			*) usage >&2; exit 2 ;;
		esac
	done
	command -v pi >/dev/null 2>&1 || die "pi not on PATH; the live mode dispatches through pi"
	(( ${#scenarios[@]} )) || mapfile -t scenarios < <(all_scenario_ids)

	if [[ -z "$run_dir" ]]; then
		run_dir="/tmp/llm/smoke/$(date -u +%Y%m%dT%H%M%SZ)-$$"
	fi
	mkdir -p "$run_dir" || die "cannot create run dir $run_dir"
	local body_file="$run_dir/manager-body.md"
	manager_body > "$body_file"

	echo "Live smoke run: ${scenarios[*]}"
	echo "  run dir: $run_dir"
	echo "  model: ${model:-host pi default}"
	[[ -n "$thinking" ]] && echo "  thinking: $thinking"

	local overall=0 sid sdir
	for sid in "${scenarios[@]}"; do
		sdir="$run_dir/$sid"
		run_one "$sid" "$body_file" "$sdir" || overall=1
		printf '%s\t%s\t%s\n' "$sid" "$(cat "$sdir/verdict.txt")" "$sdir" >> "$run_dir/manifest.txt"
	done

	if ((overall == 0)); then
		echo "Live smoke run: PASS (${scenarios[*]})"
	else
		echo "Live smoke run: FAIL (${scenarios[*]}; transcripts under $run_dir)"
	fi
	return "$overall"
}

# Delta class for one paired row: the gate semantics are tip-anchored.
# RED requires a graded tip FAIL over a baseline PASS; both-FAIL is
# instrument-inconclusive drift (the model behavior moved under both
# bodies, so the corpus cannot be blamed); a tip PASS is green whatever
# the baseline did; instrument errors are never graded verdicts, so they
# stay inconclusive instead of masquerading as FAILs.
paired_class() {
	local vb="$1" vt="$2"
	case "$vt" in
		PASS)
			case "$vb" in
				PASS) printf 'GREEN' ;;
				FAIL) printf 'GREEN (improved: baseline FAIL)' ;;
				*) printf 'GREEN (baseline instrument error)' ;;
			esac ;;
		FAIL)
			case "$vb" in
				PASS) printf 'REGRESSION' ;;
				FAIL) printf 'DRIFT (both-FAIL: instrument-inconclusive)' ;;
				*) printf 'INCONCLUSIVE (baseline instrument error)' ;;
			esac ;;
		*)
			printf 'INCONCLUSIVE (tip instrument error; baseline %s)' "$vb" ;;
	esac
}

run_paired() {
	local scenarios=() model="" thinking="" run_dir="" baseline_ref="main"
	while (($#)); do
		case "$1" in
			--scenario)
				[[ -n "${2:-}" ]] || die "--scenario needs an id"
				scenarios+=("$2"); shift 2 ;;
			--model) model="${2:-}"; [[ -n "$model" ]] || die "--model needs a value"; shift 2 ;;
			--thinking) thinking="${2:-}"; shift 2 ;;
			--run-dir) run_dir="${2:-}"; shift 2 ;;
			--baseline-ref) baseline_ref="${2:-}"; [[ -n "$baseline_ref" ]] || die "--baseline-ref needs a ref"; shift 2 ;;
			*) usage >&2; exit 2 ;;
		esac
	done
	command -v pi >/dev/null 2>&1 || die "pi not on PATH; the paired mode dispatches through pi"
	command -v git >/dev/null 2>&1 || die "git not available; the paired mode reads the baseline body from a git ref"
	(( ${#scenarios[@]} )) || mapfile -t scenarios < <(all_scenario_ids)

	if [[ -z "$run_dir" ]]; then
		run_dir="/tmp/llm/smoke/paired-$(date -u +%Y%m%dT%H%M%SZ)-$$"
	fi
	mkdir -p "$run_dir" || die "cannot create run dir $run_dir"

	# Baseline body from $baseline_ref (the pre-edit corpus), tip body from
	# the worktree source: same extraction, same composition contract, the
	# body content is the only difference.
	local baseline_sha tip_sha
	baseline_sha="$(git -C "$REPO_ROOT" rev-parse --short "$baseline_ref")" \
		|| die "baseline ref not resolvable: $baseline_ref"
	tip_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
	git -C "$REPO_ROOT" show "$baseline_ref:$MANAGER_REL" > "$run_dir/baseline-manager.md" \
		|| die "cannot read $MANAGER_REL from $baseline_ref"
	local baseline_body="$run_dir/baseline-body.md"
	manager_body_from "$run_dir/baseline-manager.md" > "$baseline_body"
	[[ -s "$baseline_body" ]] || die "baseline body extraction produced nothing (frontmatter unclosed?)"
	local tip_body="$run_dir/tip-body.md"
	manager_body > "$tip_body"
	[[ -s "$tip_body" ]] || die "tip body extraction produced nothing (frontmatter unclosed?)"
	cmp -s "$baseline_body" "$tip_body" \
		&& echo "NOTE: baseline and tip bodies are byte-identical; the delta table measures stability, not a corpus delta."

	echo "Paired delta run: ${scenarios[*]}"
	echo "  run dir: $run_dir"
	echo "  baseline: $baseline_ref @$baseline_sha | tip: worktree @$tip_sha"
	echo "  gating registry: $GATING_IDS (everything else advisory)"
	echo "  model: ${model:-host pi default}"
	[[ -n "$thinking" ]] && echo "  thinking: $thinking"

	local red=0 gating_green=0 drift=0 inconclusive=0 advisory_green=0 advisory_other=0
	local sid vb vt cls gate row
	local -a table_rows=()
	: > "$run_dir/manifest.txt"
	# Interleave per scenario (baseline then tip back to back) so each
	# pair sits in the tightest possible time window: the pairing, not the
	# overall wall clock, is what controls model-behavior drift.
	for sid in "${scenarios[@]}"; do
		if is_gating "$sid"; then gate="gating"; else gate="advisory"; fi
		run_one "$sid" "$baseline_body" "$run_dir/$sid/baseline" || true
		vb="$(cat "$run_dir/$sid/baseline/verdict.txt")"
		run_one "$sid" "$tip_body" "$run_dir/$sid/tip" || true
		vt="$(cat "$run_dir/$sid/tip/verdict.txt")"
		cls="$(paired_class "$vb" "$vt")"
		row="$(printf '%-4s baseline=%-33s tip=%-33s %s [%s]' "$sid" "$vb" "$vt" "$cls" "$gate")"
		table_rows+=("$row")
		echo "  [$sid] delta: baseline=$vb tip=$vt -> $cls [$gate]"
		printf '%s\t%s\t%s\t%s\t%s\n' "$sid" "$vb" "$vt" "$cls" "$gate" >> "$run_dir/manifest.txt"
		case "$gate" in
			gating)
				case "$cls" in
					REGRESSION*) red=$((red + 1)) ;;
					GREEN*) gating_green=$((gating_green + 1)) ;;
					DRIFT*) drift=$((drift + 1)) ;;
					*) inconclusive=$((inconclusive + 1)) ;;
				esac ;;
			*)
				case "$cls" in
					GREEN*) advisory_green=$((advisory_green + 1)) ;;
					*) advisory_other=$((advisory_other + 1)) ;;
				esac ;;
		esac
	done

	for row in "${table_rows[@]}"; do echo "  $row"; done
	echo "Gating counts: $gating_green green, $drift drift, $inconclusive inconclusive, $red regressions; advisory: $advisory_green green, $advisory_other other"
	{
		echo "Delta table (gating: $GATING_IDS; baseline $baseline_ref @$baseline_sha vs tip @$tip_sha)"
		for row in "${table_rows[@]}"; do echo "  $row"; done
		echo "Gating counts: $gating_green green, $drift drift, $inconclusive inconclusive, $red regressions; advisory: $advisory_green green, $advisory_other other"
	} > "$run_dir/delta.txt"

	if ((red > 0)); then
		echo "Paired gate: RED ($red regression(s) on the gating set: tip FAIL where baseline PASS; transcripts under $run_dir)"
		return 1
	fi
	if ((gating_green == 0)); then
		echo "Paired gate: INCONCLUSIVE (no gating scenario produced a green or regression delta; the instrument carried no evidence)"
		return 2
	fi
	echo "Paired gate: GREEN-BY-DELTA (no tip FAIL where baseline PASS on the gating set; drift rows recorded as instrument-inconclusive)"
	return 0
}

case "$MODE" in
	--validate) run_validate "$@" ;;
	--paired) run_paired "$@" ;;
	*) run_live "$@" ;;
esac
