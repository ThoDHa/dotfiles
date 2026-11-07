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

echo "== oc extractor: hermetic fixture extraction =="
EXTRACTOR="$REPO_ROOT/shell/.local/bin/task-metrics"
FIXDB="$ROOT/oc-fixture.db"
FIXLOG="$ROOT/oc-engine.log"
EXTRACTED="$ROOT/oc-extracted.jsonl"

python3 - "$FIXDB" "$FIXLOG" <<'PYEOF'
import json, sqlite3, sys
from datetime import datetime

DB, LOG = sys.argv[1], sys.argv[2]

def ms(text):
	return int(datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp() * 1000)

con = sqlite3.connect(DB)
con.execute("CREATE TABLE session (id text PRIMARY KEY, project_id text NOT NULL, "
	"parent_id text, slug text NOT NULL, directory text NOT NULL, version text NOT NULL, "
	"agent text, time_created integer NOT NULL, time_updated integer NOT NULL)")
con.execute("CREATE TABLE session_v2 (id text PRIMARY KEY, project_id text NOT NULL, "
	"parent_id text, slug text NOT NULL, directory text NOT NULL, version text NOT NULL, "
	"agent text, time_created integer NOT NULL, time_updated integer NOT NULL)")
con.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, "
	"time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
con.execute("CREATE TABLE part (id text PRIMARY KEY, message_id text NOT NULL, "
	"session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, "
	"data text NOT NULL)")

def sess(sid, parent, agent, table="session_v2"):
	con.execute(f"INSERT INTO {table} VALUES (?,?,?,?,?,?,?,?,?)",
		(sid, "proj", parent, "slug-" + sid, "/tmp", "1.0", agent,
			ms("2026-11-06T10:00:00Z"), ms("2026-11-06T15:00:00Z")))

def msg(mid, sid, created, updated, data):
	con.execute("INSERT INTO message VALUES (?,?,?,?,?)",
		(mid, sid, ms(created), ms(updated), json.dumps(data)))

def part(pid, mid, sid, created, reason):
	moment = ms(created)
	con.execute("INSERT INTO part VALUES (?,?,?,?,?,?)", (pid, mid, sid, moment, moment + 100,
		json.dumps({"type": "step-finish", "reason": reason, "cost": 0,
			"tokens": {"total": 1, "input": 1, "output": 1, "reasoning": 1,
				"cache": {"write": 0, "read": 1}}})))

def tok(i, o, r, cr, cw):
	return {"total": i + o, "input": i, "output": o, "reasoning": r,
		"cache": {"write": cw, "read": cr}}

def assistant(mid, sid, created, updated, cwd, cost, tokens, model, provider, agent=None):
	data = {"role": "assistant", "path": {"cwd": cwd}, "cost": cost, "tokens": tokens,
		"modelID": model, "providerID": provider, "time": {"created": ms(created)}}
	if agent is not None:
		data["agent"] = agent
	msg(mid, sid, created, updated, data)

sess("sess-A", None, "build")
sess("sess-B", None, None)
sess("sess-CA", "sess-A", "explore")
sess("sess-CB", "sess-A", None)
sess("sess-GC", "sess-CA", None)
sess("sess-orphan", "sess-gone", "general")
sess("sess-L", None, "build", "session")
sess("sess-LC", "sess-L", None, "session")

assistant("msg-l1", "sess-L", "2026-11-06T10:00:30Z", "2026-11-06T10:00:51.250Z",
	"/repo", 0, tok(6400, 2100, 90, 40200, 0), "glm-5.3", "zai-coding-plan", "build")
assistant("msg-lc1", "sess-LC", "2026-11-06T10:00:50Z", "2026-11-06T10:00:58.900Z",
	"/repo", 0, tok(2200, 400, 25, 0, 0), "glm-5.3", "zai-coding-plan", "general")
assistant("msg-1", "sess-A", "2026-11-06T10:01:00Z", "2026-11-06T10:01:39.880Z",
	"/repo", 0, tok(28400, 7300, 2100, 130000, 0), "glm-5.3", "zai-coding-plan", "build")
assistant("msg-2", "sess-A", "2026-11-06T10:02:00Z", "2026-11-06T10:02:15.220Z",
	"/repo", 0, tok(2400, 0, None, 121000, 0), "glm-5.3", "zai-coding-plan", "build")
assistant("msg-3", "sess-A", "2026-11-06T10:03:00Z", "2026-11-06T10:03:08.010Z",
	"/repo", 0, tok(900, 100, 30, 0, 0), "glm-5.3", "zai-coding-plan")
assistant("msg-g1", "sess-GC", "2026-11-06T10:03:30Z", "2026-11-06T10:03:55.750Z",
	"/repo", 0, tok(500, 150, 10, 0, 0), "glm-5.3", "zai-coding-plan")
assistant("msg-4", "sess-A", "2026-11-06T10:04:00Z", "2026-11-06T10:04:19.305Z",
	"/repo", None, tok(3300, 1450, 520, 118000, 0), "glm-5.3", "zai-coding-plan")
assistant("msg-5", "sess-A", "2026-11-06T14:04:30Z", "2026-11-06T14:05:18.450Z",
	"/repo", 0, tok(0, 0, 0, 0, 0), "glm-5.3", "zai-coding-plan")
assistant("msg-b1", "sess-B", "2026-11-06T14:05:30Z", "2026-11-06T14:06:11.500Z",
	"/other", 0, tok(1900, 640, 0, 0, 0), "Qwen2.5-Coder-7B-Instruct", "thoai-local")
assistant("msg-b2", "sess-B", "2026-11-06T14:07:00Z", "2026-11-06T14:07:52.100Z",
	"/other", 0, tok(51000, 6900, 4800, 205000, 0), "glm-5.3", "zai-coding-plan")
assistant("msg-o1", "sess-orphan", "2026-11-06T14:08:00Z", "2026-11-06T14:08:44.000Z",
	"/elsewhere", 0, tok(700, 200, 15, 0, 0), "glm-5.3", "zai-coding-plan")
assistant("msg-ca1", "sess-CA", "2026-11-06T14:04:00Z", "2026-11-06T14:04:33.300Z",
	"/repo", 0, tok(8800, 1400, 250, 0, 0), "glm-5.3", "zai-coding-plan", "explore")

part("p-l1", "msg-l1", "sess-L", "2026-11-06T10:00:51.000Z", "stop")
part("p-lc1", "msg-lc1", "sess-LC", "2026-11-06T10:00:58.000Z", "stop")
part("p-1-early", "msg-1", "sess-A", "2026-11-06T10:01:20.000Z", "stop")
part("p-1", "msg-1", "sess-A", "2026-11-06T10:01:39.000Z", "tool-calls")
part("p-2", "msg-2", "sess-A", "2026-11-06T10:02:15.000Z", "stop")
part("p-4", "msg-4", "sess-A", "2026-11-06T10:04:19.000Z", "length")
part("p-5", "msg-5", "sess-A", "2026-11-06T14:05:18.000Z", "stop")
part("p-b1", "msg-b1", "sess-B", "2026-11-06T14:06:11.000Z", "stop")
part("p-ca1", "msg-ca1", "sess-CA", "2026-11-06T14:04:33.000Z", "stop")
con.commit()
con.close()

PARK_LINE = ("2026-11-06T10:05:00-04:00 session 1: productive quota hit 1; "
	"unbounded ride continues; parking 600s until session 2")
with open(LOG, "w", encoding="utf-8") as log:
	log.write("2026-11-06T10:04:30-04:00 run start (pid 4711): unbounded, "
		"until OC-CONTINUE: COMPLETE, oc=opencode --model zai-coding-plan/glm-5.3\n")
	log.write(PARK_LINE + "\n")
	log.write("2026-11-06T10:06:00-04:00 session 2: invoking opencode run\n")
	log.write("2026-11-06T10:09:00-04:00 session 2: productive quota hit 2; "
		"unbounded ride continues; parking 600s until session 3\n")
PYEOF

extract_rc=0
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" \
	--cwd /repo --unit ORCH-4-3-3 --batch ORCH-4-3 \
	--out "$EXTRACTED" 2>"$ROOT/oc-extract-stderr" || extract_rc=$?
assert_eq "oc extractor exits 0 on the fixture database" "0" "$extract_rc"
validate_ok "oc extractor output validates against the ledger contract" "$EXTRACTED" "invocation: 10"

extracted_version="$(python3 -c \
	'import json, sys; print(json.loads(open(sys.argv[1], encoding="utf-8").readline())["schema_version"])' \
	"$EXTRACTED")"
assert_eq "oc extractor emits the validator's schema version" "$validator_version" "$extracted_version"
assert_contains "oc extractor summarizes its counts" "$(cat "$ROOT/oc-extract-stderr")" \
	"10 invocation records, 3 nested children, 0 anomalies"

oc_problems="$(python3 - "$EXTRACTED" <<'PYEOF'
import json, sys

records = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by_id = {record["message_id"]: record for record in records}
problems = []

def pin(label, actual, expected):
	if actual != expected:
		problems.append(f"{label}: expected {expected!r}, got {actual!r}")

PARK_LINE = ("2026-11-06T10:05:00-04:00 session 1: productive quota hit 1; "
	"unbounded ride continues; parking 600s until session 2")

pin("emission order", [r["message_id"] for r in records],
	["msg-l1", "msg-1", "msg-2", "msg-3", "msg-g1", "msg-4", "msg-5", "msg-b1", "msg-b2", "msg-o1"])
for record in records:
	pin(f"{record['message_id']} harness", record["harness"], "opencode")
	pin(f"{record['message_id']} schema_version", record["schema_version"], "1.0")
	pin(f"{record['message_id']} record_type", record["record_type"], "invocation")

r = by_id["msg-1"]
pin("msg-1 timestamp", r["timestamp"], "2026-11-06T10:01:00Z")
pin("msg-1 session", r["session_id"], "sess-A")
pin("msg-1 agent_role", r["agent_role"], "build")
pin("msg-1 model", r["model"], "glm-5.3")
pin("msg-1 provider", r["provider"], "zai-coding-plan")
pin("msg-1 tokens", r["tokens"], {"input": 28400, "output": 7300,
	"cache_read": 130000, "cache_write": 0, "reasoning": 2100})
pin("msg-1 cost", r["cost"], {"amount": 0, "source": "none"})
pin("msg-1 duration_ms", r["duration_ms"], 39880)
pin("msg-1 stop_reason (last step-finish part wins)", r["stop_reason"], "tool-calls")
pin("msg-1 retry", r["retry"], {"count": 0, "evidence": None})
pin("msg-1 restart", r["restart"], {"of_session_id": None, "engine_log": None})
pin("msg-1 attribution", r["attribution"], {"method": "cwd-match",
	"confidence": "exact", "unit_id": "ORCH-4-3-3", "batch_id": "ORCH-4-3"})
pin("msg-1 child_count", r["nested"]["child_count"], 2)

ca = r["nested"]["children"][0]
pin("child CA agent (child session identity)", ca["agent"], "sess-CA")
pin("child CA agent_role (session agent column)", ca["agent_role"], "explore")
pin("child CA model", ca["model"], "glm-5.3")
pin("child CA exit_code", ca["exit_code"], None)
pin("child CA stop_reason", ca["stop_reason"], "stop")
pin("child CA tokens (sums)", ca["tokens"], {"input": 8800, "output": 1400,
	"cache_read": 0, "cache_write": 0})
pin("child CA cost", ca["cost"], {"amount": 0, "source": "none"})
pin("child CA turns", ca["turns"], None)
pin("child CA source", ca["source"], "oc-parent-id")

cb = r["nested"]["children"][1]
pin("child CB agent", cb["agent"], "sess-CB")
pin("child CB agent_role", cb["agent_role"], None)
pin("child CB model (no assistant messages)", cb["model"], None)
pin("child CB stop_reason (no step-finish)", cb["stop_reason"], None)
pin("child CB tokens (empty sums)", cb["tokens"], {"input": 0, "output": 0,
	"cache_read": 0, "cache_write": 0})
pin("child CB cost (no cost persisted)", cb["cost"], {"amount": None, "source": "none"})

pin("msg-2 output (zero-output message)", by_id["msg-2"]["tokens"]["output"], 0)
pin("msg-2 reasoning (absent stays null)", by_id["msg-2"]["tokens"]["reasoning"], None)
pin("msg-2 stop_reason", by_id["msg-2"]["stop_reason"], "stop")
pin("msg-3 stop_reason (no step-finish part)", by_id["msg-3"]["stop_reason"], "unknown")
pin("msg-3 retry (unknown end repeated)", by_id["msg-3"]["retry"],
	{"count": 1, "evidence": "invocation-repeat"})
pin("msg-4 cost (absent carried as null)", by_id["msg-4"]["cost"],
	{"amount": None, "source": "none"})
pin("msg-4 stop_reason", by_id["msg-4"]["stop_reason"], "length")
pin("msg-5 zero usage", (by_id["msg-5"]["tokens"]["input"],
	by_id["msg-5"]["tokens"]["output"]), (0, 0))
pin("msg-5 retry (last message is an end)", by_id["msg-5"]["retry"],
	{"count": 0, "evidence": None})
pin("msg-b1 restart (park window join)", by_id["msg-b1"]["restart"],
	{"of_session_id": "sess-A", "engine_log": PARK_LINE})
pin("msg-b1 provider", by_id["msg-b1"]["provider"], "thoai-local")
pin("msg-b1 agent_role (absent stays null)", by_id["msg-b1"]["agent_role"], None)
pin("msg-b1 attribution (non-matching cwd)", by_id["msg-b1"]["attribution"],
	{"method": "none", "confidence": "unattributed", "unit_id": None,
		"batch_id": "ORCH-4-3"})
pin("msg-b2 stop_reason", by_id["msg-b2"]["stop_reason"], "unknown")
pin("msg-b2 retry (unknown end without a repeat)", by_id["msg-b2"]["retry"],
	{"count": 0, "evidence": None})
pin("msg-o1 session (orphan child extracted standalone)", by_id["msg-o1"]["session_id"], "sess-orphan")
pin("msg-o1 attribution", by_id["msg-o1"]["attribution"],
	{"method": "none", "confidence": "unattributed", "unit_id": None,
		"batch_id": "ORCH-4-3"})
g1 = by_id["msg-g1"]
pin("msg-g1 session (grandchild flattens to its own records)", g1["session_id"], "sess-GC")
pin("msg-g1 stop_reason (no step-finish part)", g1["stop_reason"], "unknown")
pin("msg-g1 retry (only message in its session)", g1["retry"], {"count": 0, "evidence": None})
pin("msg-g1 attribution", g1["attribution"], {"method": "cwd-match",
	"confidence": "exact", "unit_id": "ORCH-4-3-3", "batch_id": "ORCH-4-3"})
pin("msg-g1 tokens", g1["tokens"], {"input": 500, "output": 150,
	"cache_read": 0, "cache_write": 0, "reasoning": 10})
pin("CA child entry excludes grandchild tokens (no double count)",
	(ca["tokens"]["input"], ca["tokens"]["output"]), (8800, 1400))

l1 = by_id["msg-l1"]
pin("msg-l1 session (legacy session table row)", l1["session_id"], "sess-L")
pin("msg-l1 stop_reason", l1["stop_reason"], "stop")
pin("msg-l1 attribution", l1["attribution"], {"method": "cwd-match",
	"confidence": "exact", "unit_id": "ORCH-4-3-3", "batch_id": "ORCH-4-3"})
pin("msg-l1 child_count (legacy child folded)", l1["nested"]["child_count"], 1)
lc = l1["nested"]["children"][0]
pin("child LC agent", lc["agent"], "sess-LC")
pin("child LC agent_role (falls back to the message agent)", lc["agent_role"], "general")
pin("child LC tokens", lc["tokens"], {"input": 2200, "output": 400,
	"cache_read": 0, "cache_write": 0})

print("\n".join(problems))
PYEOF
)"
assert_no_output "oc extractor records carry the pinned derivation values" "$oc_problems"

oc_readonly_before="$(md5sum "$FIXDB" | cut -d' ' -f1)"
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --out "$ROOT/oc-readonly.jsonl" >/dev/null 2>&1
oc_readonly_after="$(md5sum "$FIXDB" | cut -d' ' -f1)"
assert_eq "oc extraction leaves the database byte-identical" "$oc_readonly_before" "$oc_readonly_after"
validate_ok "default-attribution output validates" "$ROOT/oc-readonly.jsonl" "invocation: 10"
oc_unattributed="$(python3 - "$ROOT/oc-readonly.jsonl" <<'PYEOF'
import json, sys
records = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
wrong = [r["message_id"] for r in records
	if r["attribution"] != {"method": "none", "confidence": "unattributed",
		"unit_id": None, "batch_id": None}]
print("attributed without --cwd/--unit: " + ", ".join(wrong) if wrong else "")
PYEOF
)"
assert_no_output "records without --cwd stay unattributed" "$oc_unattributed"

python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --session sess-B \
	--out "$ROOT/oc-session-b.jsonl" >/dev/null 2>&1
validate_ok "session filter output validates" "$ROOT/oc-session-b.jsonl" "invocation: 2"
session_b_restart="$(python3 -c \
	'import json, sys; records = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]; \
	b1 = next(r for r in records if r["message_id"] == "msg-b1"); \
	print(b1["restart"]["of_session_id"], bool(b1["restart"]["engine_log"]))' \
	"$ROOT/oc-session-b.jsonl")"
assert_eq "restart engine_log stands alone outside the prior session's scope" \
	"None True" "$session_b_restart"

python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --session sess-L \
	--out "$ROOT/oc-session-l.jsonl" >/dev/null 2>&1
validate_ok "legacy-table session requested directly extracts its subtree" \
	"$ROOT/oc-session-l.jsonl" "invocation: 1"

python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --session sess-CA \
	--out "$ROOT/oc-session-ca.jsonl" >/dev/null 2>&1
validate_ok "child session requested directly extracts standalone" "$ROOT/oc-session-ca.jsonl" \
	"invocation: 1"

python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" \
	--since 2026-11-06T10:04:00Z --out "$ROOT/oc-since.jsonl" >/dev/null 2>&1
validate_ok "--since window output validates" "$ROOT/oc-since.jsonl" "invocation: 5"
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" \
	--until 2026-11-06T14:07:00Z --out "$ROOT/oc-until.jsonl" >/dev/null 2>&1
validate_ok "--until window output validates" "$ROOT/oc-until.jsonl" "invocation: 8"

# Regression: a message created before the --until boundary whose
# step-finish part lands past it must carry the part's real stop reason
# and derive no retry from the windowing gap.
STRADDLE_DB="$ROOT/oc-straddle.db"
python3 - "$STRADDLE_DB" <<'PYEOF'
import json, sqlite3, sys
from datetime import datetime

def ms(text):
	return int(datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp() * 1000)

con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE session_v2 (id text PRIMARY KEY, project_id text NOT NULL, "
	"parent_id text, slug text NOT NULL, directory text NOT NULL, version text NOT NULL, "
	"agent text, time_created integer NOT NULL, time_updated integer NOT NULL)")
con.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, "
	"time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
con.execute("CREATE TABLE part (id text PRIMARY KEY, message_id text NOT NULL, "
	"session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, "
	"data text NOT NULL)")
con.execute("INSERT INTO session_v2 VALUES ('sess-W', 'proj', NULL, 'slug-sess-W', '/repo', "
	"'1.0', 'build', ?, ?)", (ms("2026-11-06T14:06:00Z"), ms("2026-11-06T14:08:00Z")))
for mid, created, updated in (("msg-w1", "2026-11-06T14:06:30Z", "2026-11-06T14:07:25Z"),
		("msg-w2", "2026-11-06T14:06:55Z", "2026-11-06T14:07:40Z")):
	con.execute("INSERT INTO message VALUES (?,?,?,?,?)", (mid, "sess-W",
		ms(created), ms(updated), json.dumps({
			"role": "assistant", "path": {"cwd": "/repo"}, "cost": 0,
			"tokens": {"input": 1000, "output": 100, "reasoning": 10,
				"cache": {"write": 0, "read": 50}},
			"modelID": "glm-5.3", "providerID": "zai-coding-plan",
			"time": {"created": ms(created)}})))
for pid, mid, created, reason in (("p-w1", "msg-w1", "2026-11-06T14:07:05Z", "stop"),
		("p-w2", "msg-w2", "2026-11-06T14:06:56Z", "tool-calls")):
	con.execute("INSERT INTO part VALUES (?,?,?,?,?,?)", (pid, mid, "sess-W",
		ms(created), ms(created) + 100, json.dumps({"type": "step-finish",
			"reason": reason, "cost": 0, "tokens": {"total": 1, "input": 1,
				"output": 1, "reasoning": 1, "cache": {"write": 0, "read": 1}}})))
con.commit()
con.close()
PYEOF
straddle_rc=0
python3 "$EXTRACTOR" oc --db "$STRADDLE_DB" --engine-log "$FIXLOG" \
	--until 2026-11-06T14:07:00Z --out "$ROOT/oc-straddle.jsonl" \
	2>"$ROOT/oc-straddle-stderr" || straddle_rc=$?
assert_eq "a window whose boundary splits a message from its part exits 0" "0" "$straddle_rc"
validate_ok "boundary-straddle output validates" "$ROOT/oc-straddle.jsonl" "invocation: 2"
straddle_problems="$(python3 - "$ROOT/oc-straddle.jsonl" <<'PYEOF'
import json, sys

records = {r["message_id"]: r for r in
	(json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip())}
problems = []

def pin(label, actual, expected):
	if actual != expected:
		problems.append(f"{label}: expected {expected!r}, got {actual!r}")

pin("msg-w1 keeps the part carried past the boundary", records["msg-w1"]["stop_reason"], "stop")
pin("msg-w1 derives no retry from the straddle", records["msg-w1"]["retry"],
	{"count": 0, "evidence": None})
pin("msg-w2 keeps its in-window stop reason", records["msg-w2"]["stop_reason"], "tool-calls")
pin("msg-w2 as the last message derives no retry", records["msg-w2"]["retry"],
	{"count": 0, "evidence": None})
print("\n".join(problems))
PYEOF
)"
assert_no_output "boundary-straddle records carry real stop reasons and no fabricated retry" "$straddle_problems"

# Idempotent append: a re-run over an overlapping scope skips the
# invocations the target already holds instead of poisoning the ledger
# with duplicates the validator rejects.
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --session sess-B \
	--out "$ROOT/oc-append.jsonl" >/dev/null 2>&1
validate_ok "the first append writes the session to a fresh target" "$ROOT/oc-append.jsonl" "invocation: 2"
rerun_rc=0
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --session sess-B \
	--out "$ROOT/oc-append.jsonl" 2>"$ROOT/oc-append-stderr" || rerun_rc=$?
assert_eq "re-appending an overlapping scope exits 0" "0" "$rerun_rc"
validate_ok "a re-run over an appended scope leaves the ledger valid" "$ROOT/oc-append.jsonl" "invocation: 2"
assert_contains "the re-run names the skipped duplicates" "$(cat "$ROOT/oc-append-stderr")" \
	"2 invocation records already in"
assert_eq "the re-run appends no duplicate records" "2" "$(wc -l < "$ROOT/oc-append.jsonl")"
overlap_rc=0
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" \
	--out "$ROOT/oc-append.jsonl" 2>"$ROOT/oc-overlap-stderr" || overlap_rc=$?
assert_eq "appending the full scope over a partial ledger exits 0" "0" "$overlap_rc"
validate_ok "the partial-overlap append keeps the ledger valid" "$ROOT/oc-append.jsonl" "invocation: 10"
overlap_duplicates="$(python3 - "$ROOT/oc-append.jsonl" <<'PYEOF'
import json, sys

records = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
keys = [(r["harness"], r["session_id"], r["message_id"]) for r in records]
print(len(keys) - len(set(keys)))
PYEOF
)"
assert_eq "the overlapping append writes only the missing invocations" "0" "$overlap_duplicates"
cp "$ROOT/oc-append.jsonl" "$ROOT/oc-unreadable-line.jsonl"
printf 'not json {bad\n' >> "$ROOT/oc-unreadable-line.jsonl"
unreadable_rc=0
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --session sess-B \
	--out "$ROOT/oc-unreadable-line.jsonl" 2>"$ROOT/oc-unreadable-stderr" || unreadable_rc=$?
assert_eq "appending to a ledger with an unreadable line exits 0" "0" "$unreadable_rc"
assert_contains "an unreadable ledger line warns it cannot be checked" \
	"$(cat "$ROOT/oc-unreadable-stderr")" "line 11 is not valid JSON"

missing_log_rc=0
python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$ROOT/absent-engine.log" \
	--out "$ROOT/oc-missing-log.jsonl" 2>"$ROOT/oc-missing-log-stderr" || missing_log_rc=$?
assert_eq "a missing engine log degrades to null restarts, not an error" "0" "$missing_log_rc"
assert_contains "a missing engine log warns on stderr" "$(cat "$ROOT/oc-missing-log-stderr")" \
	"engine log unreadable"
validate_ok "missing-engine-log output validates" "$ROOT/oc-missing-log.jsonl" "invocation: 10"
oc_no_restart="$(python3 - "$ROOT/oc-missing-log.jsonl" <<'PYEOF'
import json, sys
records = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
wrong = [r["message_id"] for r in records
	if r["restart"] != {"of_session_id": None, "engine_log": None}]
print("restarts marked without an engine log: " + ", ".join(wrong) if wrong else "")
PYEOF
)"
assert_no_output "missing engine log leaves every restart null" "$oc_no_restart"

python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" \
	--since 2027-01-01T00:00:00Z >"$ROOT/oc-empty.jsonl" 2>/dev/null
empty_rc=$?
assert_eq "an empty extraction window exits 1 without writing a ledger" "1" "$empty_rc"
assert_eq "an empty extraction writes nothing" "" "$(cat "$ROOT/oc-empty.jsonl")"

python3 - "$ROOT/oc-corrupt.db" <<'PYEOF'
import json, sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE session_v2 (id text PRIMARY KEY, project_id text NOT NULL, "
	"parent_id text, slug text NOT NULL, directory text NOT NULL, version text NOT NULL, "
	"agent text, time_created integer NOT NULL, time_updated integer NOT NULL)")
con.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, "
	"time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
con.execute("CREATE TABLE part (id text PRIMARY KEY, message_id text NOT NULL, "
	"session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, "
	"data text NOT NULL)")
con.execute("INSERT INTO session_v2 VALUES ('sess-X', 'proj', NULL, 'slug', '/tmp', '1.0', NULL, 1, 2)")
con.execute("INSERT INTO message VALUES ('msg-good', 'sess-X', 1, 2, ?)", (json.dumps({
	"role": "assistant", "modelID": "glm-5.3", "providerID": "zai-coding-plan",
	"cost": 0, "tokens": {"input": 1, "output": 1, "reasoning": 0,
		"cache": {"read": 0, "write": 0}}}),))
con.execute("INSERT INTO message VALUES ('msg-corrupt', 'sess-X', 3, 4, 'not json {bad')")
con.execute("INSERT INTO message VALUES ('msg-lost', 'sess-nowhere', 5, 6, ?)", (json.dumps({
	"role": "assistant", "modelID": "glm-5.3", "providerID": "zai-coding-plan",
	"cost": 0, "tokens": {"input": 2, "output": 2, "reasoning": 0,
		"cache": {"read": 0, "write": 0}}}),))
con.commit()
PYEOF
corrupt_rc=0
python3 "$EXTRACTOR" oc --db "$ROOT/oc-corrupt.db" --engine-log "$ROOT/absent-engine.log" \
	--out "$ROOT/oc-corrupt.jsonl" 2>"$ROOT/oc-corrupt-stderr" || corrupt_rc=$?
assert_eq "a corrupt message row degrades to a warning, not a failure" "0" "$corrupt_rc"
validate_ok "corrupt-row output validates (good record plus the session-less record)" \
	"$ROOT/oc-corrupt.jsonl" "invocation: 2"
assert_contains "the corrupt row is counted in the summary" "$(cat "$ROOT/oc-corrupt-stderr")" "1 anomalies"
lost_session="$(python3 -c \
	'import json, sys; records = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]; \
	lost = next(r for r in records if r["message_id"] == "msg-lost"); \
	print(lost["session_id"], lost["nested"]["child_count"])' \
	"$ROOT/oc-corrupt.jsonl")"
assert_eq "a message with no session row in either table extracts standalone" \
	"sess-nowhere 0" "$lost_session"

python3 "$EXTRACTOR" oc --db "$FIXDB" --engine-log "$FIXLOG" --session sess-nope \
	>/dev/null 2>"$ROOT/oc-unknown-session-stderr"
unknown_session_rc=$?
assert_eq "an unknown --session exits 2" "2" "$unknown_session_rc"
assert_contains "an unknown --session names the session" "$(cat "$ROOT/oc-unknown-session-stderr")" "sess-nope"

python3 "$EXTRACTOR" oc --db "$ROOT/absent.db" >/dev/null 2>&1; missing_db_rc=$?
assert_eq "a missing database exits 2" "2" "$missing_db_rc"
python3 "$EXTRACTOR" oc --db "$FIXDB" --cwd /repo >/dev/null 2>&1; lone_cwd_rc=$?
assert_eq "--cwd without --unit exits 2" "2" "$lone_cwd_rc"
python3 "$EXTRACTOR" oc --db "$FIXDB" --since yesterday >/dev/null 2>&1; bad_moment_rc=$?
assert_eq "a non-moment --since exits 2" "2" "$bad_moment_rc"
python3 "$EXTRACTOR" oc --db "$FIXDB" --frobnicate >/dev/null 2>&1; bad_flag_rc=$?
assert_eq "an unknown option exits 2" "2" "$bad_flag_rc"
python3 "$EXTRACTOR" >/dev/null 2>&1; no_args_rc=$?
assert_eq "no arguments exits 2 with usage" "2" "$no_args_rc"
python3 "$EXTRACTOR" frobnicate >/dev/null 2>&1; bad_mode_rc=$?
assert_eq "an unknown mode exits 2" "2" "$bad_mode_rc"

python3 "$EXTRACTOR" pi --help >/dev/null 2>&1; pi_help_rc=$?
assert_eq "the pi mode answers --help after integration" "0" "$pi_help_rc"
python3 "$EXTRACTOR" rollup >/dev/null 2>"$ROOT/oc-rollup-stderr"; rollup_rc=$?
assert_eq "the rollup mode stays reserved" "2" "$rollup_rc"
assert_contains "the rollup mode names its delivery slice" "$(cat "$ROOT/oc-rollup-stderr")" "ORCH-4-3-4"

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
