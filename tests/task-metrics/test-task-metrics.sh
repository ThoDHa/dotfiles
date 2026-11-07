#!/usr/bin/env bash
#
# Tests for the versioned metrics ledger contract (ORCH-4-3-1): the
# executable validator (tests/task-metrics/validate-ledger.py) against
# the fixture ledgers for both harnesses, the rejection matrix (missing
# fields, wrong types, unknown enum members, unknown schema versions,
# broken cross-field invariants, duplicate invocations, corrupt JSONL),
# the additive-only evolution guard (unknown extra fields validate),
# fixture field coverage (positive and degenerate forms per harness),
# the per-harness stop-reason vocabulary (fixtures carry only spellings
# observed in the live harness stores), fixture cost source/amount
# coherence, non-finite number rejection, the UTF-8 exit ladder,
# loud-failure propagation of the tamper and embedded-python helpers,
# the populated unattributed batch form, unit-rollup arithmetic
# consistency with the pi fixture,
# schema-document consistency (doc version, record types, enum members,
# observed stop-reason spellings, budget semantics, yield-tally fields,
# AC-12 probe families), and the make wiring pin (chained into test and
# verify-inner).
#
# Hermetic: the fixtures are synthetic records under
# tests/task-metrics/fixtures/ (no live session data, no database, no
# network); tampered variants are generated into a temp dir and every
# temp artifact is removed on exit.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_DIR="$REPO_ROOT/tests/task-metrics"
VALIDATOR="$SUITE_DIR/validate-ledger.py"
SCHEMA_DOC="$SUITE_DIR/ledger-schema.md"
PROBE_DOC="$SUITE_DIR/ac12-probe-spec.md"
FIXTURES="$SUITE_DIR/fixtures"
MAKEFILE="$REPO_ROOT/Makefile"

source "$REPO_ROOT/tests/lib/harness.sh"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

validator_version="$(sed -n 's/^CURRENT_SCHEMA_VERSION = "\(.*\)"$/\1/p' "$VALIDATOR")"

validate_err() { # label fixture needle; a rejection must exit 1 and name the site
	local label="$1" fixture="$2" needle="$3" rc=0 out
	out="$(python3 "$VALIDATOR" "$fixture" 2>&1 >/dev/null)" || rc=$?
	assert_eq "$label (exit 1)" "1" "$rc"
	assert_contains "$label (names the site)" "$out" "$needle"
}

validate_ok() { # label fixture needle; a valid ledger exits 0 and summarizes counts
	local label="$1" fixture="$2" needle="$3" rc=0 out
	out="$(python3 "$VALIDATOR" "$fixture" 2>/dev/null)" || rc=$?
	assert_eq "$label (exit 0)" "0" "$rc"
	assert_contains "$label (summary)" "$out" "$needle"
}

assert_valid() { # label fixture; the validator must accept this ledger outright
	local label="$1" fixture="$2" rc=0
	python3 "$VALIDATOR" "$fixture" >/dev/null 2>&1 || rc=$?
	assert_eq "$label" "0" "$rc"
}

tamper() { # out_file src_file record_type python_expr; rewrites the first record of that type in a temp copy
	local out="$1" src="$2" record_type="$3" expr="$4" rc=0
	python3 - "$out" "$src" "$record_type" "$expr" <<'PYEOF'
import json, sys
out, src, record_type, expr = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().splitlines()
index = next(i for i, l in enumerate(lines)
	if json.loads(l)["record_type"] == record_type)
rec = json.loads(lines[index])
exec(expr)
lines[index] = json.dumps(rec)
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PYEOF
	rc=$?
	if ((rc != 0)); then
		bad "tamper helper failed rewriting $record_type (rc $rc); the next check would read a stale file"
		return 1
	fi
}

coverage() { # fixture pins_file; prints missing pins, one per line, or a failure sentinel
	local out rc=0
	out="$(python3 - "$1" "$2" <<'PYEOF'
import json, sys

def dig(rec, path):
	cur = rec
	for part in path.split("."):
		if not isinstance(cur, dict) or part not in cur:
			return None, False
		cur = cur[part]
	return cur, True

fixture, pins_path = sys.argv[1], sys.argv[2]
records = [json.loads(l) for l in open(fixture, encoding="utf-8") if l.strip()]
missing = []
for line in open(pins_path, encoding="utf-8"):
	line = line.strip()
	if not line or line.startswith("#"):
		continue
	path, mode = line.split()
	hits = [dig(r, path) for r in records]
	found = False
	for (val, present) in hits:
		if not present:
			continue
		if mode == "positive" and (
			(isinstance(val, (int, float)) and not isinstance(val, bool) and val > 0)
			or (isinstance(val, str) and val)
			or (isinstance(val, list) and val)
		):
			found = True
		elif mode == "null" and val is None:
			found = True
		elif mode == "zero" and val == 0 and not isinstance(val, bool):
			found = True
		elif mode == "empty" and isinstance(val, list) and not val:
			found = True
		elif mode == "value" and val is not None:
			found = True
	if not found:
		missing.append(f"{path} {mode}")
if missing:
	print("\n".join(missing))
PYEOF
)" || rc=$?
	if ((rc != 0)); then printf 'COVERAGE CHECK CRASHED (rc %d)\n' "$rc"; fi
	printf '%s' "$out"
}

assert_no_output() { # label output; empty output means every pinned form was found
	local label="$1" out="$2"
	if [[ -z "$out" ]]; then ok "$label"; else bad "$label (gaps: $(echo "$out" | tr '\n' ' '))"; fi
}

crash_sentinel() { # rc output; a crashed embedded-python run becomes a loud gap, never a false-pass empty string
	if (($1 != 0)); then printf 'EMBEDDED PYTHON CRASHED (rc %d)' "$1"; else printf '%s' "$2"; fi
}

echo "== helper failure propagation self-test =="
rc=0
(
	fail=0
	bad() { fail=$((fail + 1)); }
	tamper "$ROOT/selftest.jsonl" "$FIXTURES/pi-ledger.jsonl" nosuchrecordtype "pass"
	((fail == 1)) || exit 1
) || rc=$?
assert_eq "tamper helper fails loudly on an absent record type" "0" "$rc"
rc=0
(
	[[ "$(crash_sentinel 3 "partial")" == "EMBEDDED PYTHON CRASHED (rc 3)" ]] || exit 1
	[[ "$(crash_sentinel 0 "gaps")" == "gaps" ]] || exit 1
) || rc=$?
assert_eq "crash sentinel turns a nonzero embedded-python rc into a loud gap" "0" "$rc"

echo "== validator CLI contract =="
python3 "$VALIDATOR" >/dev/null 2>&1; no_args_rc=$?
python3 "$VALIDATOR" "$ROOT/does-not-exist.jsonl" >/dev/null 2>&1; missing_rc=$?
assert_eq "no arguments exits 2" "2" "$no_args_rc"
assert_eq "unreadable ledger exits 2" "2" "$missing_rc"
printf '\xff\xfe not a ledger\n' > "$ROOT/invalid-utf8.jsonl"
python3 "$VALIDATOR" "$ROOT/invalid-utf8.jsonl" >/dev/null 2>&1; utf8_rc=$?
assert_eq "invalid UTF-8 ledger exits 2" "2" "$utf8_rc"

echo "== fixture validation: pi =="
validate_ok "pi fixture validates" "$FIXTURES/pi-ledger.jsonl" "invocation: 6"
validate_ok "pi fixture summary carries the schema version" "$FIXTURES/pi-ledger.jsonl" \
	"against schema $validator_version"

echo "== fixture validation: opencode =="
validate_ok "opencode fixture validates" "$FIXTURES/oc-ledger.jsonl" "invocation: 5"

echo "== fixture validation: rollups =="
validate_ok "rollup fixture validates" "$FIXTURES/rollups-ledger.jsonl" "batch_rollup: 1"
validate_ok "rollup fixture summary names every record type" "$FIXTURES/rollups-ledger.jsonl" \
	"unit_rollup: 1"
validate_ok "rollup fixture summary names the ac12 snapshot" "$FIXTURES/rollups-ledger.jsonl" \
	"ac12_snapshot: 1"

echo "== rejection matrix =="
t="$ROOT/tampered.jsonl"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'del rec["schema_version"]'
validate_err "missing schema_version" "$t" "schema_version"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["schema_version"] = "9.0"'
validate_err "unknown schema version" "$t" "9.0"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["schema_version"] = "one"'
validate_err "malformed schema version" "$t" "schema_version"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'del rec["timestamp"]'
validate_err "missing timestamp" "$t" "timestamp"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["timestamp"] = "2026-11-06 09:14:03"'
validate_err "non-RFC3339 timestamp" "$t" "timestamp"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["timestamp"] = "2026-13-40T09:14:03Z"'
validate_err "impossible calendar date" "$t" "calendar"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["harness"] = "cursor"'
validate_err "unknown harness" "$t" "harness"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'del rec["session_id"]'
validate_err "missing session_id" "$t" "session_id"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["tokens"]["input"] = "many"'
validate_err "token count as string" "$t" "tokens.input"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["tokens"]["output"] = -1'
validate_err "negative token count" "$t" "tokens.output"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["cost"]["source"] = "fabricated"'
validate_err "unknown cost source" "$t" "cost.source"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["cost"]["amount"] = None'
validate_err "reported cost without an amount" "$t" "cost.amount"

tamper "$t" "$FIXTURES/oc-ledger.jsonl" invocation 'rec["cost"]["amount"] = 5.0'
validate_err "positive amount under source none" "$t" "cost.amount"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["cost"]["amount"] = float("nan")'
validate_err "NaN amount under reported cost" "$t" "finite"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["cost"]["amount"] = float("inf")'
validate_err "infinite amount under reported cost" "$t" "finite"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["duration_ms"] = -5'
validate_err "negative duration" "$t" "duration_ms"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'del rec["stop_reason"]'
validate_err "missing stop reason" "$t" "stop_reason"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["stop_reason"] = ""'
validate_err "empty stop reason" "$t" "stop_reason"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["retry"]["count"] = 2; rec["retry"]["evidence"] = None'
validate_err "retries without evidence" "$t" "retry.evidence"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["nested"]["child_count"] = 3'
validate_err "child count contradicting children" "$t" "child_count"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["attribution"]["confidence"] = "guessed"'
validate_err "unknown attribution confidence" "$t" "attribution.confidence"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation \
	'rec["attribution"]["confidence"] = "exact"; rec["attribution"]["method"] = "none"'
validate_err "attributed record with method none" "$t" "attribution.method"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation \
	'rec["attribution"]["confidence"] = "unattributed"; rec["attribution"]["method"] = "cwd-match"'
validate_err "unattributed record with an attribution method" "$t" "attribution.method"

tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["record_type"] = "span"'
validate_err "unknown record type" "$t" "record_type"

tamper "$t" "$FIXTURES/rollups-ledger.jsonl" batch_rollup \
	'rec["budget"]["over_budget"] = ["tokens", "vibes"]'
validate_err "unknown over-budget dimension" "$t" "over_budget"

tamper "$t" "$FIXTURES/rollups-ledger.jsonl" unit_rollup \
	'rec["stop_reason_histogram"] = {"stop": 4, "error": -1}'
validate_err "negative histogram count" "$t" "stop_reason_histogram"

tamper "$t" "$FIXTURES/rollups-ledger.jsonl" batch_rollup \
	'rec["yield_tally"]["source_links"] = []'
validate_err "yield tally without source links" "$t" "yield_tally"

tamper "$t" "$FIXTURES/rollups-ledger.jsonl" ac12_snapshot 'rec["phase"] = "during"'
validate_err "unknown snapshot phase" "$t" "phase"

printf '{"schema_version": "1.0", "record_type": "invocation"\n' > "$t"
validate_err "truncated JSON line" "$t" "line 1"

printf '[1, 2, 3]\n' > "$t"
validate_err "non-object line" "$t" "line 1"

printf '' > "$t"
validate_err "empty ledger" "$t" "no records"

cp "$FIXTURES/pi-ledger.jsonl" "$t"
head -1 "$FIXTURES/pi-ledger.jsonl" >> "$t"
validate_err "duplicate invocation record" "$t" "duplicate"

echo "== additive-only evolution guard =="
tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["future_field"] = {"anything": True}'
assert_valid "unknown top-level field still validates" "$t"
tamper "$t" "$FIXTURES/pi-ledger.jsonl" invocation 'rec["tokens"]["future_token"] = 7'
assert_valid "unknown token field still validates" "$t"

echo "== fixture field coverage: pi =="
cat > "$ROOT/pi-pins" <<'PINS'
timestamp positive
harness positive
session_id positive
message_id positive
agent_role positive
model positive
provider positive
tokens.input positive
tokens.output positive
tokens.cache_read positive
tokens.cache_write zero
tokens.reasoning positive
tokens.reasoning null
cost.amount positive
cost.source value
duration_ms positive
stop_reason positive
retry.count positive
retry.evidence null
restart.of_session_id null
restart.engine_log positive
nested.children empty
nested.children positive
attribution.method positive
attribution.confidence value
attribution.unit_id positive
attribution.batch_id positive
PINS
pi_gaps="$(coverage "$FIXTURES/pi-ledger.jsonl" "$ROOT/pi-pins")"
assert_no_output "pi fixtures cover every pinned field form" "$pi_gaps"

pi_degenerate_rc=0
pi_degenerate="$(python3 - "$FIXTURES/pi-ledger.jsonl" <<'PYEOF'
import json, sys
records = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
def has(pred):
	return any(pred(r) for r in records)
checks = {
	"cost.source reported": has(lambda r: r["cost"]["source"] == "reported"),
	"cost.source none": has(lambda r: r["cost"]["source"] == "none"),
	"cost.amount null under none": has(
		lambda r: r["cost"]["source"] == "none" and r["cost"]["amount"] is None),
	"zero-output streaming record": has(lambda r: r["tokens"]["output"] == 0),
	"duration_ms null": has(lambda r: r["duration_ms"] is None),
	"nested child with unreported cost": any(
		c["cost"]["source"] == "none" and c["cost"]["amount"] is None
		for r in records for c in r["nested"]["children"]),
	"retry.count above zero": has(lambda r: r["retry"]["count"] > 0),
	"attribution window confidence": any(r["attribution"]["confidence"] == "window" for r in records),
	"restart linkage present": any(r["restart"]["of_session_id"] is not None for r in records),
	"nested child with null exit_code": any(
		c["exit_code"] is None for r in records for c in r["nested"]["children"]),
	"unattributed record carries the populated batch": any(
		r["attribution"]["confidence"] == "unattributed"
		and r["attribution"]["batch_id"] is not None
		and r["attribution"]["unit_id"] is None
		for r in records),
}
print("\n".join(name for name, hit in checks.items() if not hit))
PYEOF
)" || pi_degenerate_rc=$?
pi_degenerate="$(crash_sentinel "$pi_degenerate_rc" "$pi_degenerate")"
assert_no_output "pi fixtures carry the pinned degenerate forms" "$pi_degenerate"

echo "== fixture field coverage: opencode =="
cat > "$ROOT/oc-pins" <<'PINS'
timestamp positive
harness positive
session_id positive
message_id positive
model positive
provider positive
tokens.input positive
tokens.output positive
tokens.reasoning positive
tokens.cache_read positive
tokens.cache_write zero
cost.source value
duration_ms positive
stop_reason positive
nested.children empty
nested.children positive
attribution.method positive
attribution.confidence value
PINS
oc_gaps="$(coverage "$FIXTURES/oc-ledger.jsonl" "$ROOT/oc-pins")"
assert_no_output "opencode fixtures cover every pinned field form" "$oc_gaps"

oc_degenerate_rc=0
oc_degenerate="$(python3 - "$FIXTURES/oc-ledger.jsonl" <<'PYEOF'
import json, sys
records = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
def has(pred):
	return any(pred(r) for r in records)
checks = {
	"carried cost zero with source none": has(
		lambda r: r["cost"]["source"] == "none" and r["cost"]["amount"] == 0),
	"attribution unattributed": has(lambda r: r["attribution"]["confidence"] == "unattributed"),
	"attribution method none": has(lambda r: r["attribution"]["method"] == "none"),
	"nested child from oc-parent-id": any(
		c["source"] == "oc-parent-id" for r in records for c in r["nested"]["children"]),
	"nested child with unreported cost": any(
		c["cost"]["source"] == "none" for r in records for c in r["nested"]["children"]),
	"leaf record with no children": has(lambda r: r["nested"]["child_count"] == 0),
}
print("\n".join(name for name, hit in checks.items() if not hit))
PYEOF
)" || oc_degenerate_rc=$?
oc_degenerate="$(crash_sentinel "$oc_degenerate_rc" "$oc_degenerate")"
assert_no_output "opencode fixtures carry the pinned degenerate forms" "$oc_degenerate"

echo "== per-harness stop-reason vocabulary =="
vocab_gaps_rc=0
vocab_gaps="$(python3 - "$FIXTURES/pi-ledger.jsonl" "$FIXTURES/oc-ledger.jsonl" <<'PYEOF'
import json, sys

PI_OBSERVED = {"stop", "toolUse", "error", "aborted"}
OC_OBSERVED = {"tool-calls", "stop", "length", "unknown"}
problems = []
for path, observed, label in ((sys.argv[1], PI_OBSERVED, "pi"),
	(sys.argv[2], OC_OBSERVED, "opencode")):
	seen = set()
	for line in open(path, encoding="utf-8"):
		rec = json.loads(line)
		if rec.get("record_type") != "invocation":
			continue
		seen.add(rec["stop_reason"])
		seen.update(c["stop_reason"] for c in rec["nested"]["children"]
			if c["stop_reason"] is not None)
	foreign = seen - observed
	if foreign:
		problems.append(f"{label} fixture carries stop reasons never observed "
			f"on the live harness: {sorted(foreign)} (observed vocabulary: {sorted(observed)})")
print("\n".join(problems))
PYEOF
)" || vocab_gaps_rc=$?
vocab_gaps="$(crash_sentinel "$vocab_gaps_rc" "$vocab_gaps")"
assert_no_output "fixtures carry only their harness's observed stop reasons" "$vocab_gaps"

echo "== unit rollup arithmetic consistency =="
rollup_gaps_rc=0
rollup_gaps="$(python3 - "$FIXTURES/pi-ledger.jsonl" "$FIXTURES/rollups-ledger.jsonl" <<'PYEOF'
import json, math, sys

invocations = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
rollups = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
unit = next(r for r in rollups if r["record_type"] == "unit_rollup")
problems = []
for field in ("input", "output", "cache_read", "cache_write", "reasoning"):
	total = sum(r["tokens"][field] for r in invocations if r["tokens"][field] is not None)
	if unit["tokens"][field] != total:
		problems.append(f"tokens.{field}: rollup {unit['tokens'][field]} != fixture sum {total}")
for field in ("input", "output", "cache_read", "cache_write"):
	total = sum(c["tokens"][field] for r in invocations for c in r["nested"]["children"])
	if unit["nested_tokens"][field] != total:
		problems.append(f"nested_tokens.{field}: rollup {unit['nested_tokens'][field]} != fixture sum {total}")
amounts = [r["cost"]["amount"] for r in invocations if r["cost"]["source"] == "reported"]
if not math.isclose(unit["cost"]["amount_sum"], sum(amounts), rel_tol=0, abs_tol=1e-9):
	problems.append(f"cost.amount_sum: rollup {unit['cost']['amount_sum']} != fixture sum {sum(amounts)}")
if unit["cost"]["reported_count"] != len(amounts):
	problems.append(f"cost.reported_count: rollup {unit['cost']['reported_count']} != {len(amounts)} reported fixture records")
if unit["cost"]["unreported_count"] != len(invocations) - len(amounts):
	problems.append(f"cost.unreported_count: rollup {unit['cost']['unreported_count']} != "
		f"{len(invocations) - len(amounts)} unreported fixture records")
histogram = {}
for r in invocations:
	histogram[r["stop_reason"]] = histogram.get(r["stop_reason"], 0) + 1
if unit["stop_reason_histogram"] != histogram:
	problems.append(f"stop_reason_histogram: rollup {unit['stop_reason_histogram']} != fixture counts {histogram}")
if unit["invocation_count"] != len(invocations):
	problems.append(f"invocation_count: rollup {unit['invocation_count']} != {len(invocations)} fixture records")
if unit["retry_count"] != sum(r["retry"]["count"] for r in invocations):
	problems.append("retry_count: rollup does not match fixture retry sum")
restarts = sum(1 for r in invocations if r["restart"]["of_session_id"] is not None)
if unit["restart_count"] != restarts:
	problems.append(f"restart_count: rollup {unit['restart_count']} != {restarts} restart-linked fixture records")
duration = sum(r["duration_ms"] for r in invocations if r["duration_ms"] is not None)
if unit["duration_ms_total"] != duration:
	problems.append(f"duration_ms_total: rollup {unit['duration_ms_total']} != fixture sum {duration}")
confidence = {}
for r in invocations:
	value = r["attribution"]["confidence"]
	confidence[value] = confidence.get(value, 0) + 1
if unit["attribution_confidence_histogram"] != confidence:
	problems.append(f"attribution_confidence_histogram: rollup "
		f"{unit['attribution_confidence_histogram']} != fixture counts {confidence}")
print("\n".join(problems))
PYEOF
)" || rollup_gaps_rc=$?
rollup_gaps="$(crash_sentinel "$rollup_gaps_rc" "$rollup_gaps")"
assert_no_output "unit rollup arithmetic matches the pi fixture" "$rollup_gaps"

echo "== schema document consistency =="
doc="$(cat "$SCHEMA_DOC")"
[[ -n "$validator_version" ]] && ok "validator pins a current schema version" \
	|| bad "validator pins a current schema version"
assert_contains "schema doc carries the validator's version" "$doc" "Current version: $validator_version"
for record_type in invocation unit_rollup batch_rollup ac12_snapshot; do
	assert_contains "schema doc names record type $record_type" "$doc" "$record_type"
done
for member in reported none exact window unattributed cwd-match task-file-reference \
	dispatch-window pi-subagent-details oc-parent-id before after; do
	assert_contains "schema doc names enum member $member" "$doc" "\`$member\`"
done
for dimension in tokens cost wall_clock requests; do
	assert_contains "schema doc names budget dimension $dimension" "$doc" "\`$dimension\`"
done
assert_contains "schema doc pins the over-budget flag form" "$doc" 'over-budget('
assert_contains "schema doc pins the populated unattributed batch form" "$doc" "populated-batch reading"
assert_contains "schema doc names opencode's explicit agent field" "$doc" "\`message.data.agent\`"
for spelling in stop toolUse error aborted tool-calls length unknown; do
	assert_contains "schema doc names observed stop reason $spelling" "$doc" "\`$spelling\`"
done
assert_contains "schema doc names pi's reasoning source field" "$doc" "\`usage.reasoning\`"
for tally_field in verifier_findings_by_severity verifier_caught_defects reviewer_blocker \
	reviewer_major reviewer_minor escaped_defects false_positives time_to_close_ms \
	batch_cost_total source_links; do
	assert_contains "schema doc names yield-tally field $tally_field" "$doc" "\`$tally_field\`"
done

echo "== AC-12 probe spec consistency =="
probe="$(cat "$PROBE_DOC")"
for family in read_latency context_token_cost command_failures retrieval_completeness \
	permission_denials; do
	assert_contains "probe spec names family $family" "$probe" "\`$family\`"
done
assert_contains "probe spec pins the fixed question list" "$probe" "q1"
assert_contains "probe spec pins the fixed question list through q5" "$probe" "q5"
assert_contains "probe spec carries comparability rules" "$probe" "Comparability"
assert_contains "probe spec names the snapshot record carrier" "$probe" "ac12_snapshot"
assert_contains "probe spec names the ORCH-4-9 ordering rule" "$probe" "ORCH-4-9"

echo "== make wiring =="
grep -Eq '^test:.*(^| )test-task-metrics( |$)' "$MAKEFILE" \
	&& ok "make test chains test-task-metrics" \
	|| bad "make test chains test-task-metrics"
grep -Eq '^verify-inner:.*(^| )test-task-metrics( |$)' "$MAKEFILE" \
	&& ok "make verify-inner chains test-task-metrics" \
	|| bad "make verify-inner chains test-task-metrics"
grep -Eq '^\.PHONY:.*(^| )test-task-metrics( |$)' "$MAKEFILE" \
	&& ok "test-task-metrics declared .PHONY" \
	|| bad "test-task-metrics declared .PHONY"

print_result
((fail == 0)) || exit 1
