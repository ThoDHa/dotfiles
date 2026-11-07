#!/usr/bin/env bash
#
# Tests for the pi extractor (shell/.local/bin/task-metrics pi,
# ORCH-4-3-2): ledger-valid extraction from the hermetic synthetic pi
# session store, per-record field fidelity against expected values,
# degenerate forms (zero-output row, absent durationMs, zeroed
# error/aborted usage, zero-priced and unpriced rows, subagent children
# with null exit_code, null model, unpriced cost, absent turns), nested
# pairing via the toolResult toolCallId join with a parentId fallback
# (the live parallel fan-out chains toolResults; both the chained
# shape and the no-toolCallId fallback are pinned), retry evidence
# classes (stop-reason, invocation-repeat), the pi-continue engine.log
# park/restart join and the interrupted-park stale-state regression,
# attribution (cwd-match worktree normalization, task-file-reference,
# unattributed with the populated and absent batch forms), read-only
# store handling, determinism, append semantics, corrupt-line
# resilience, the exit ladder, and the make wiring pin.
#
# Hermetic: the fixture store is synthetic under
# tests/task-metrics/fixtures/pi-store/ (no live session data, no
# network); run outputs land in a temp dir removed on exit.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_DIR="$REPO_ROOT/tests/task-metrics"
EXTRACTOR="$REPO_ROOT/shell/.local/bin/task-metrics"
VALIDATOR="$SUITE_DIR/validate-ledger.py"
FIXTURES="$SUITE_DIR/fixtures/pi-store"
SESSIONS="$FIXTURES/sessions"
ENGINE_LOG="$FIXTURES/engine.log"

source "$REPO_ROOT/tests/lib/harness.sh"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

run_extractor() { # outfile rcvar [args...]; runs the extractor, capturing ledger and exit
	local out="$1" rcvar="$2"
	shift 2
	local rc=0
	"$EXTRACTOR" pi "$@" > "$out" 2> "$out.err" || rc=$?
	printf '%s' "$rc" > "$rcvar"
}

store_fingerprint() { # dir; md5 of every file, sorted, for the read-only check
	find "$1" -type f -print0 | sort -z | xargs -0 md5sum | md5sum
}

assert_no_output() { # label output; empty output means every expected form was found
	local label="$1" out="$2"
	if [[ -z "$out" ]]; then ok "$label"; else bad "$label (gaps: $(echo "$out" | tr '\n' ' '))"; fi
}

echo "== CLI contract =="
"$EXTRACTOR" > "$ROOT/cli.jsonl" 2> "$ROOT/cli.jsonl.err"; cli_rc=$?
assert_eq "no mode exits 2" "2" "$cli_rc"
if [[ -s "$ROOT/cli.jsonl" ]]; then bad "no mode prints a ledger"; else ok "no mode prints no ledger"; fi
assert_contains "no mode names the usage on stderr" "$(cat "$ROOT/cli.jsonl.err")" "usage: task-metrics"
run_extractor "$ROOT/unknown.jsonl" "$ROOT/unknown.rc" --session-dir "$SESSIONS" bogus-mode
assert_eq "unknown mode exits 2" "2" "$(cat "$ROOT/unknown.rc")"
run_extractor "$ROOT/missing-dir.jsonl" "$ROOT/missing-dir.rc" --session-dir "$ROOT/no-such-dir"
assert_eq "missing session dir exits 2" "2" "$(cat "$ROOT/missing-dir.rc")"
run_extractor "$ROOT/missing-log.jsonl" "$ROOT/missing-log.rc" --session-dir "$SESSIONS" --engine-log "$ROOT/absent.log"
assert_eq "explicit missing engine log exits 2" "2" "$(cat "$ROOT/missing-log.rc")"
mkdir -p "$ROOT/empty-store/sessions"
run_extractor "$ROOT/empty.jsonl" "$ROOT/empty.rc" --session-dir "$ROOT/empty-store/sessions"
assert_eq "empty store exits 0 with zero records" "0" "$(cat "$ROOT/empty.rc")"
assert_eq "empty store emits an empty ledger" "0" "$(wc -l < "$ROOT/empty.jsonl" | tr -d ' ')"

echo "== extraction validates against the ledger contract =="
run_extractor "$ROOT/main.jsonl" "$ROOT/main.rc" --session-dir "$SESSIONS" --engine-log "$ENGINE_LOG"
assert_eq "extraction exits 0" "0" "$(cat "$ROOT/main.rc")"
assert_eq "extraction emits 7 records" "7" "$(wc -l < "$ROOT/main.jsonl" | tr -d ' ')"
python3 "$VALIDATOR" "$ROOT/main.jsonl" > "$ROOT/validate.out" 2>&1
assert_eq "extracted ledger validates" "0" "$?"
assert_contains "validation summary counts the invocations" "$(cat "$ROOT/validate.out")" "invocation: 7"
assert_contains "extraction summary names the restart join" "$(cat "$ROOT/main.jsonl.err")" \
	"1 restart cycle(s) joined"

echo "== per-record field fidelity =="
fidelity_gaps="$(python3 - "$ROOT/main.jsonl" <<'PYEOF'
import json, sys

PARK_LINE = ("2026-11-06T09:04:30-05:00 session 1: quota-hit 1 of budget 3; "
	"parking 600s until session 2")
A = "aaa00001-0000-0000-0000-000000000001"
B = "bbb00002-0000-0000-0000-000000000002"
CWD_ATTR = {"method": "cwd-match", "confidence": "exact",
	"unit_id": "ORCH-4-3-1", "batch_id": None}
REF_ATTR = {"method": "task-file-reference", "confidence": "exact",
	"unit_id": "ORCH-4-9-1", "batch_id": None}
NO_RESTART = {"of_session_id": None, "engine_log": None}
NO_RETRY = {"count": 0, "evidence": None}


def child(agent, model, exit_code, stop, tokens, cost, turns):
	return {"agent": agent, "agent_role": agent, "model": model,
		"exit_code": exit_code, "stop_reason": stop, "tokens": tokens,
		"cost": cost, "turns": turns, "source": "pi-subagent-details"}


def invocation(session, message, timestamp, tokens, cost, duration, stop,
		retry=NO_RETRY, restart=NO_RESTART, children=None, attr=CWD_ATTR):
	kids = children or []
	return {"schema_version": "1.0", "record_type": "invocation",
		"timestamp": timestamp, "harness": "pi", "session_id": session,
		"message_id": message, "agent_role": None, "model": "glm-5.3",
		"provider": "zai", "tokens": tokens, "cost": cost,
		"duration_ms": duration, "stop_reason": stop, "retry": retry,
		"restart": restart, "nested": {"child_count": len(kids), "children": kids},
		"attribution": attr}


expected = [
	invocation(A, "m-a-0001", "2026-11-06T14:00:10.000Z",
		{"input": 1000, "output": 200, "cache_read": 5000, "cache_write": 100,
			"reasoning": 50}, {"amount": 0.0123, "source": "reported"}, 41000,
		"toolUse",
		children=[
			child("worker", "glm-5.3", 0, "stop",
				{"input": 500, "output": 300, "cache_read": 2000, "cache_write": 0},
				{"amount": 0.004, "source": "reported"}, 3),
			child("scout", None, None, "timeout",
				{"input": 100, "output": 0, "cache_read": 500, "cache_write": 0},
				{"amount": None, "source": "none"}, None),
			child("analyst", "glm-5.3", 0, "stop",
				{"input": 200, "output": 50, "cache_read": 300, "cache_write": 0},
				{"amount": 0.0005, "source": "reported"}, None)]),
	invocation(A, "m-a-0002", "2026-11-06T14:01:00.000Z",
		{"input": 800, "output": 0, "cache_read": 900, "cache_write": 0,
			"reasoning": 0}, {"amount": 0.0, "source": "reported"}, None, "stop",
		children=[child("fallback", "glm-5.3", 0, "stop",
			{"input": 10, "output": 20, "cache_read": 30, "cache_write": 0},
			{"amount": 0.0001, "source": "reported"}, 1)]),
	invocation(A, "m-a-0003", "2026-11-06T14:02:00.000Z",
		{"input": 0, "output": 0, "cache_read": 0, "cache_write": 0,
			"reasoning": None}, {"amount": None, "source": "none"}, 1500, "aborted"),
	invocation(A, "m-a-0004", "2026-11-06T14:03:00.000Z",
		{"input": 0, "output": 0, "cache_read": 0, "cache_write": 0,
			"reasoning": None}, {"amount": None, "source": "none"}, 8000, "error",
		retry={"count": 1, "evidence": "stop-reason"}),
	invocation(A, "m-a-0005", "2026-11-06T14:04:00.000Z",
		{"input": 600, "output": 120, "cache_read": 700, "cache_write": 0,
			"reasoning": 10}, {"amount": 0.002, "source": "reported"}, 30000,
		"stop", retry={"count": 1, "evidence": "invocation-repeat"}),
	invocation(B, "m-b-0001", "2026-11-06T15:00:30.000Z",
		{"input": 700, "output": 150, "cache_read": 1100, "cache_write": 0,
			"reasoning": 20}, {"amount": 0.0008, "source": "reported"}, 25000,
		"toolUse", attr=REF_ATTR,
		restart={"of_session_id": A, "engine_log": PARK_LINE},
		children=[child("reviewer", "glm-5.3", 0, "stop",
			{"input": 300, "output": 100, "cache_read": 800, "cache_write": 0},
			{"amount": 0.001, "source": "reported"}, 2)]),
	invocation(B, "m-b-0002", "2026-11-06T15:01:30.000Z",
		{"input": 400, "output": 80, "cache_read": 600, "cache_write": 0,
			"reasoning": 5}, {"amount": 0.0004, "source": "reported"}, 35000,
		"stop", attr=REF_ATTR),
]

actual = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
problems = []
if len(actual) != len(expected):
	problems.append(f"record count: actual {len(actual)} != expected {len(expected)}")
for i, (got, want) in enumerate(zip(actual, expected)):
	for key in sorted(set(got) | set(want)):
		if got.get(key) != want.get(key):
			problems.append(f"record {i} ({want['message_id']}) field {key}: "
				f"actual {got.get(key)!r} != expected {want.get(key)!r}")
print("\n".join(problems))
PYEOF
)"
assert_no_output "extracted records match the expected ledger field by field" "$fidelity_gaps"

echo "== nested join shapes (toolCallId-first, parentId fallback) =="
join_gaps="$(python3 - "$ROOT/main.jsonl" <<'PYEOF'
import json, sys
records = {json.loads(line)["message_id"]: json.loads(line)
	for line in open(sys.argv[1], encoding="utf-8") if line.strip()}
problems = []
first = records["m-a-0001"]["nested"]
agents = [child["agent"] for child in first["children"]]
if first["child_count"] != 3 or agents != ["worker", "scout", "analyst"]:
	problems.append(f"chained fan-out join: m-a-0001 children {agents!r} "
		"(t-a-0002's parent is a toolResult, so its analyst leg must join "
		"via its toolCallId tc-1b)")
second = records["m-a-0002"]["nested"]
agents = [child["agent"] for child in second["children"]]
if second["child_count"] != 1 or agents != ["fallback"]:
	problems.append(f"parentId fallback join: m-a-0002 children {agents!r} "
		"(t-a-0003 carries no toolCallId, so its leg must join via its parentId)")
print("\n".join(problems))
PYEOF
)"
assert_no_output "chained fan-out joins via toolCallId and the no-toolCallId row falls back to parentId" "$join_gaps"

echo "== read-only, determinism, append, env honoring =="
before="$(store_fingerprint "$FIXTURES")"
run_extractor "$ROOT/det1.jsonl" "$ROOT/det1.rc" --session-dir "$SESSIONS" --engine-log "$ENGINE_LOG"
run_extractor "$ROOT/det2.jsonl" "$ROOT/det2.rc" --session-dir "$SESSIONS" --engine-log "$ENGINE_LOG"
after="$(store_fingerprint "$FIXTURES")"
assert_eq "fixture store untouched (read-only)" "$before" "$after"
if cmp -s "$ROOT/det1.jsonl" "$ROOT/det2.jsonl"; then
	ok "extraction is deterministic (byte-identical reruns)"
else
	bad "extraction is deterministic (byte-identical reruns)"
fi
PI_CODING_AGENT_SESSION_DIR="$SESSIONS" "$EXTRACTOR" pi \
	--engine-log "$ENGINE_LOG" > "$ROOT/env.jsonl" 2> "$ROOT/env.jsonl.err"
assert_eq "PI_CODING_AGENT_SESSION_DIR honors the store" "0" "$?"
if cmp -s "$ROOT/det1.jsonl" "$ROOT/env.jsonl"; then
	ok "env-selected store extracts identically to --session-dir"
else
	bad "env-selected store extracts identically to --session-dir"
fi
run_extractor "$ROOT/append.jsonl" "$ROOT/append.rc" --session-dir "$SESSIONS" --engine-log "$ENGINE_LOG" --output "$ROOT/append.jsonl"
run_extractor "$ROOT/append2.jsonl" "$ROOT/append.rc" --session-dir "$SESSIONS" --engine-log "$ENGINE_LOG" --output "$ROOT/append.jsonl"
assert_eq "second --output run appends rather than rewrites" "14" "$(wc -l < "$ROOT/append.jsonl" | tr -d ' ')"
validate_rc=0
python3 "$VALIDATOR" "$ROOT/append.jsonl" > "$ROOT/append-validate.out" 2>&1 || validate_rc=$?
assert_eq "doubled ledger fails validation (append is visible to consumers)" "1" "$validate_rc"
assert_contains "doubled ledger names the duplicate" "$(cat "$ROOT/append-validate.out")" "duplicate"

echo "== corrupt-line resilience =="
rm -rf "$ROOT/corrupt-store"
cp -r "$FIXTURES" "$ROOT/corrupt-store"
first_session="$(find "$ROOT/corrupt-store/sessions" -name "2026-11-06T14*" | head -1)"
sed -i '3a not json at all' "$first_session"
run_extractor "$ROOT/corrupt.jsonl" "$ROOT/corrupt.rc" --session-dir "$ROOT/corrupt-store/sessions" --engine-log "$ROOT/corrupt-store/engine.log"
assert_eq "corrupt line does not fail extraction" "0" "$(cat "$ROOT/corrupt.rc")"
assert_eq "records after the corrupt line still extract" "7" "$(wc -l < "$ROOT/corrupt.jsonl" | tr -d ' ')"
assert_contains "corrupt line warns on stderr naming the file" "$(cat "$ROOT/corrupt.jsonl.err")" "warning"
assert_contains "corrupt line warns naming the count" "$(cat "$ROOT/corrupt.jsonl.err")" "1 malformed line(s) skipped"

echo "== attribution forms and the batch stamp =="
rm -rf "$ROOT/plain-store"
mkdir -p "$ROOT/plain-store/sessions"
printf '%s\n' \
	'{"type":"session","version":3,"id":"ccc00003-0000-0000-0000-000000000003","timestamp":"2026-11-06T16:00:00.000Z","cwd":"/tmp/plain"}' \
	'{"type":"message","id":"u-c-0001","parentId":null,"timestamp":"2026-11-06T16:00:05.000Z","message":{"role":"user","content":[{"type":"text","text":"Hello."}]}}' \
	'{"type":"message","id":"m-c-0001","parentId":"u-c-0001","timestamp":"2026-11-06T16:00:30.000Z","message":{"role":"assistant","provider":"zai","model":"glm-5.3","stopReason":"stop","durationMs":12000,"usage":{"input":10,"output":5,"cacheRead":20,"cacheWrite":0,"reasoning":1,"cost":{"total":0.0001}},"content":[]}}' \
	> "$ROOT/plain-store/sessions/2026-11-06T16-00-00-000Z_ccc00003-0000-0000-0000-000000000003.jsonl"
run_extractor "$ROOT/plain.jsonl" "$ROOT/plain.rc" --session-dir "$ROOT/plain-store/sessions" --batch-id ORCH-4-9
assert_eq "batch-stamped extraction exits 0" "0" "$(cat "$ROOT/plain.rc")"
plain_gaps="$(python3 - "$ROOT/plain.jsonl" <<'PYEOF'
import json, sys
record = json.loads(open(sys.argv[1], encoding="utf-8").readline())
attr = record["attribution"]
problems = []
if attr != {"method": "none", "confidence": "unattributed",
		"unit_id": None, "batch_id": "ORCH-4-9"}:
	problems.append(f"unattributed attribution with batch: {attr!r}")
print("\n".join(problems))
PYEOF
)"
assert_no_output "unattributed record carries the populated batch and null unit" "$plain_gaps"
run_extractor "$ROOT/plain-nobatch.jsonl" "$ROOT/plain-nobatch.rc" --session-dir "$ROOT/plain-store/sessions"
nobatch_gaps="$(python3 - "$ROOT/plain-nobatch.jsonl" <<'PYEOF'
import json, sys
record = json.loads(open(sys.argv[1], encoding="utf-8").readline())
attr = record["attribution"]
problems = []
if attr["batch_id"] is not None or attr["unit_id"] is not None \
		or attr["method"] != "none" or attr["confidence"] != "unattributed":
	problems.append(f"unattributed attribution without batch: {attr!r}")
print("\n".join(problems))
PYEOF
)"
assert_no_output "batch-less extraction leaves batch_id null" "$nobatch_gaps"
python3 "$VALIDATOR" "$ROOT/plain.jsonl" >/dev/null 2>&1
assert_eq "batch-stamped single record validates" "0" "$?"

echo "== engine.log absence leaves restarts null =="
default_rc=0
PI_CONTINUE_STATE_DIR="$ROOT/quiet-state" "$EXTRACTOR" pi --session-dir "$SESSIONS" \
	> "$ROOT/default-log.jsonl" 2> "$ROOT/default-log.jsonl.err" || default_rc=$?
assert_eq "default engine.log absent from an empty state dir extracts" "0" "$default_rc"
assert_contains "default engine.log absence warns on stderr" "$(cat "$ROOT/default-log.jsonl.err")" \
	"default engine log"
assert_contains "default engine.log absence names the resolved path" "$(cat "$ROOT/default-log.jsonl.err")" \
	"$ROOT/quiet-state"
restart_gaps="$(python3 - "$ROOT/default-log.jsonl" <<'INNEREOF'
import json, sys
problems = []
for line in open(sys.argv[1], encoding="utf-8"):
	record = json.loads(line)
	if record["restart"] != {"of_session_id": None, "engine_log": None}:
		problems.append(f"{record['message_id']}: restart not null without engine.log")
print("\n".join(problems))
INNEREOF
)"
assert_no_output "records carry null restarts without an engine log" "$restart_gaps"
default_rc=0
PI_CONTINUE_STATE_DIR="$FIXTURES" "$EXTRACTOR" pi --session-dir "$SESSIONS" \
	> "$ROOT/default-log.jsonl" 2> "$ROOT/default-log.jsonl.err" || default_rc=$?
assert_eq "default engine.log present in the state dir extracts" "0" "$default_rc"
if cmp -s "$ROOT/main.jsonl" "$ROOT/default-log.jsonl"; then
	ok "default engine.log resolution extracts identically to --engine-log"
else
	bad "default engine.log resolution extracts identically to --engine-log"
fi

echo "== interrupted park clears stale restart state =="
INTERRUPTED_LOG="$FIXTURES/engine-interrupted.log"
run_extractor "$ROOT/interrupted.jsonl" "$ROOT/interrupted.rc" --session-dir "$SESSIONS" --engine-log "$INTERRUPTED_LOG"
assert_eq "interrupted-park store extracts" "0" "$(cat "$ROOT/interrupted.rc")"
assert_contains "stale interrupted park does not complete a cycle" "$(cat "$ROOT/interrupted.jsonl.err")" \
	"1 restart cycle(s) joined"
interrupted_gaps="$(python3 - "$ROOT/interrupted.jsonl" <<'PYEOF'
import json, sys
CLEAN_PARK = ("2026-11-06T09:14:31-05:00 session 1: quota-hit 1 of budget 3; "
	"parking 600s until session 2")
A = "aaa00001-0000-0000-0000-000000000001"
problems = []
for line in open(sys.argv[1], encoding="utf-8"):
	record = json.loads(line)
	restart = record["restart"]
	if record["session_id"] == A and restart != {"of_session_id": None, "engine_log": None}:
		problems.append(f"{record['message_id']}: interrupted park leaked a restart {restart!r}")
	if record["message_id"] == "m-b-0001" and restart != {"of_session_id": A, "engine_log": CLEAN_PARK}:
		problems.append(f"m-b-0001: expected the clean park cycle, got {restart!r}")
	if record["message_id"] == "m-b-0002" and restart != {"of_session_id": None, "engine_log": None}:
		problems.append(f"m-b-0002: unexpected restart {restart!r}")
print("\n".join(problems))
PYEOF
)"
assert_no_output "only the clean post-restart cycle joins, on the run-2 record" "$interrupted_gaps"
head -5 "$INTERRUPTED_LOG" > "$ROOT/log-ends-at-stop.log"
run_extractor "$ROOT/truncated.jsonl" "$ROOT/truncated.rc" --session-dir "$SESSIONS" --engine-log "$ROOT/log-ends-at-stop.log"
assert_eq "log ending at stopped-by-user extracts" "0" "$(cat "$ROOT/truncated.rc")"
assert_contains "park followed by stopped-by-user yields no cycle" "$(cat "$ROOT/truncated.jsonl.err")" \
	"0 restart cycle(s) joined"
truncated_gaps="$(python3 - "$ROOT/truncated.jsonl" <<'PYEOF'
import json, sys
problems = []
for line in open(sys.argv[1], encoding="utf-8"):
	record = json.loads(line)
	if record["restart"] != {"of_session_id": None, "engine_log": None}:
		problems.append(f"{record['message_id']}: restart joined without a completed cycle")
print("\n".join(problems))
PYEOF
)"
assert_no_output "records carry null restarts when the log ends at an interrupted park" "$truncated_gaps"

echo "== make wiring =="
grep -Eq '^test:.*(^| )test-pi-extractor( |$)' "$REPO_ROOT/Makefile" \
	&& ok "make test chains test-pi-extractor" \
	|| bad "make test chains test-pi-extractor"
grep -Eq '^verify-inner:.*(^| )test-pi-extractor( |$)' "$REPO_ROOT/Makefile" \
	&& ok "make verify-inner chains test-pi-extractor" \
	|| bad "make verify-inner chains test-pi-extractor"
grep -Eq '^\.PHONY:.*(^| )test-pi-extractor( |$)' "$REPO_ROOT/Makefile" \
	&& ok "test-pi-extractor declared .PHONY" \
	|| bad "test-pi-extractor declared .PHONY"

print_result
((fail == 0)) || exit 1
