# Metrics Ledger Schema

The versioned contract for the runtime telemetry ledger (ORCH-4-3-1): every record shape that the pi and opencode extractors (ORCH-4-3-2, ORCH-4-3-3) write, that the rollup (ORCH-4-3-4) derives, and that the budget and comparison consumers (ORCH-4-6, ORCH-4-7) read. Executable validation lives in `tests/task-metrics/validate-ledger.py`; fixture ledgers for both harnesses live in `tests/task-metrics/fixtures/` and are validated by `tests/task-metrics/test-task-metrics.sh`. Every field below is traced to the durable source surface verified in the ORCH-4-3 `01-recon` deposit, cited as (pi N) or (oc N) for that report's numbered findings.

## Versioning

Current version: 1.0

The schema evolves additively only: a writer may add new optional fields at any level, and validators of an older registry accept them (the evolution guard in the suite proves this). Changing a field's type or domain, removing or renaming a field, or tightening a domain is a breaking change and requires a major version bump plus a registry update in the validator and a matching update of this document. A writer that emits a `schema_version` the validator does not know fails validation with remediation naming the registry extension, so churn cannot pass silently. The suite pins this document's version line to the validator's `CURRENT_SCHEMA_VERSION`.

## Ledger File Format

A ledger is an append-only JSONL file: UTF-8, exactly one JSON object per line, records in emission order. Blank interior lines are corruption and fail validation; the empty ledger fails validation because a ledger with no records cannot serve any consumer. Extractors append; nothing in the contract requires or permits rewriting earlier lines.

## Record Envelope

Every record carries `schema_version` (MAJOR.MINOR string, known to the validator) and `record_type` (one of `invocation`, `unit_rollup`, `batch_rollup`, `ac12_snapshot`). Unknown extra fields are permitted at every level for additive evolution; every known field is checked for type, domain, and range. The validator exits 0 on a valid ledger, 1 on any validation failure (each failure on stderr as `FAIL: line N: <path>: <message>`), and 2 on usage or IO errors.

## Invocation Record

One record per model invocation (pi assistant message, opencode assistant message joined with its step-finish parts).

| Field | Type | Pi source (recon) | Opencode source (recon) |
|---|---|---|---|
| `timestamp` | RFC3339 UTC string, required | assistant message timestamps in session JSONL (pi 1) | `message.time_created` / `time_updated`, part timestamps (oc 1) |
| `harness` | `pi` or `opencode`, required | derived by the extracting mode | derived by the extracting mode |
| `session_id` | non-empty string, required | session file identity | `message.session_id` (oc 1) |
| `message_id` | non-empty string, required | session entry id | `message.id` (oc 1) |
| `agent_role` | string or null | subagent toolResult `details.results[].agent` where derivable (pi 2) | `message.data.agent`, an explicit field where present; null otherwise (oc 1) |
| `model` | non-empty string, required | assistant `model` (pi 1) | `message.modelID` (oc 1) |
| `provider` | non-empty string, required | assistant `provider` (pi 1) | `message.providerID` (oc 1) |
| `tokens` | object, required (see below) | `usage` {input, output, cacheRead, cacheWrite, reasoning} (pi 1) | `message.tokens` {input, output, cache{read, write}, reasoning} (oc 1) |
| `cost` | object, required (see below) | `usage.cost.total`, real values confirmed (pi 1) | adapter-reported `cost` carried verbatim, zeros marked (oc 3) |
| `duration_ms` | integer >= 0 or null | per-message timestamp delta (pi 4) | `time_created` to `time_updated` delta (oc 1) |
| `stop_reason` | non-empty string, required | assistant `stopReason` (pi 1) | `step-finish` part `reason` (oc 1) |
| `retry` | object, required (see below) | derived: error-class stop reasons, repeat invocations, engine.log joins (pi 3) | derived: step-finish reasons, oc-continue engine.log joins (oc 4) |
| `restart` | object, required (see below) | pi-continue engine.log park/restart cycles (pi 3) | oc-continue engine.log session/park/complete lines (oc 4) |
| `nested` | object, required (see below) | subagent toolResult `details.results[]` (pi 2) | `session_v2.parent_id` chains (oc 2) |
| `attribution` | object, required (see below) | derived: cwd, task-file references, dispatch windows | derived: same sources |

The tokens object carries `input`, `output`, `cache_read`, `cache_write` as integers >= 0 and `reasoning` as an integer >= 0 or null. Both harnesses persist a reasoning token count: pi assistant `usage.reasoning` (pi 1) and opencode `message.tokens.reasoning` (oc 1), so extractors populate it for every invocation that completed a usage block. Null is written only when the harness persisted no reasoning value: pi's `error` and `aborted` rows carry an all-zero usage block with no reasoning field (verified against the live session store 2026-11-06: 3936 of 4209 assistant rows carry a reasoning count, and the 273 without one are exactly the `error` and `aborted` rows). Source field names map camelCase to snake_case (`cacheRead` to `cache_read`, `cacheWrite` to `cache_write`, `usage.reasoning` to `tokens.reasoning`).

The cost object carries `amount` (number or null) and `source` (`reported` when the harness persisted a real cost value, `none` when it did not). Reported records must carry a numeric `amount`; `none` records carry null when no cost was persisted at all, or the harness's reported zero carried verbatim: opencode's zai-coding-plan adapter reports 0 on every message (oc 3), and that zero is never dropped, replaced, or fabricated into a price. The validator enforces both directions: a reported record without an amount, and a `none` record with an amount other than null or zero, both fail. No pricing table exists in this contract; cross-harness cost comparisons run on token denominators.

The retry object carries `count` (integer >= 0) and `evidence` (`stop-reason`, `invocation-repeat`, `engine-log`, or null). A nonzero count requires an evidence class and a zero count forbids one; retries are derived signals, never invented from silence.

The restart object carries `of_session_id` (string or null) and `engine_log` (string or null), referencing the prior session and the engine.log line that evidences the park/restart cycle. Either may stand alone.

The nested object carries `child_count` (integer >= 0, equal to the children array length) and `children` (array of child records, possibly empty).

The attribution object carries `method` (`cwd-match`, `task-file-reference`, `dispatch-window`, or `none`), `confidence` (`exact`, `window`, `unattributed`), `unit_id` (string or null), and `batch_id` (string or null). An unattributed record must use method `none`, and only an unattributed record may use it; attributed records carry the unit or batch they attach to. The canonical batch_id form is the populated-batch reading: `batch_id` names the batch whose extraction pass produced the record and is populated even on unattributed records, whose `unit_id` stays null; it is null only when the extraction ran outside any batch (decided at the ORCH-4-3-2 opening round per the reviewer's leaning). The validator accepts both forms so a tightening stays a major-bump decision, not a silent one. Unattributed invocations stay visible in batch totals rather than being dropped (the attribution-accuracy risk's mitigation in the parent plan).

### Stop-Reason Vocabulary

`stop_reason` is carried verbatim; extractors never translate or normalize. The spellings observed in the live harness stores as of the 2026-11-06 scan are pinned here so consumers group them instead of trusting string equality across harnesses: pi persists `stop`, `toolUse`, `error`, and `aborted` on assistant rows; opencode's `step-finish` part persists `tool-calls`, `stop`, `length`, and `unknown`. The same semantic event carries different spellings per harness: pi `toolUse` and opencode `tool-calls` are both a turn that ended to run tools, so cross-harness stop-reason histograms (ORCH-4-7) must group by semantic class, never by raw spelling. pi's `error` and `aborted` rows are the all-zero usage rows described above; opencode shows no error spelling in the live store, and this contract's fixtures model an abnormal opencode step end with `unknown`.

## Nested Child Record

One entry per nested subagent leg.

| Field | Type | Pi source | Opencode source |
|---|---|---|---|
| `agent` | non-empty string, required | `details.results[].agent` (pi 2) | child session identity via `parent_id` (oc 2) |
| `agent_role` | string or null | `agentSource` mapping where derivable | child session context |
| `model` | string or null | `details.results[].model` (pi 2) | child session's messages |
| `exit_code` | integer or null | `details.results[].exitCode` (pi 2) | child session completion; null when unknown |
| `stop_reason` | string or null | `details.results[].stopReason` (pi 2) | child session's final step-finish reason |
| `tokens` | object {input, output, cache_read, cache_write} >= 0, required | per-child `usage` (pi 2) | child session token sums |
| `cost` | same shape as invocation cost, required | per-child `usage.cost` (pi 2) | child cost carried with source marking |
| `turns` | integer >= 0 or null | `details.results[].turns` (pi 2) | not derivable; null |
| `source` | `pi-subagent-details` or `oc-parent-id`, required | provenance marker | provenance marker |

## Unit Rollup Record (`unit_rollup`)

Always derived by the rollup, never hand-written. Fields: `unit_id` (non-empty string), `batch_id` (string or null), `generated_at` (RFC3339 UTC), `invocation_count`, `retry_count`, `restart_count` (integers >= 0), `stop_reason_histogram` (object mapping stop reason to integer >= 0), `tokens` (sums of the five token fields), `nested_tokens` (sums of the four child token fields), `cost` (`amount_sum` number or null, `reported_count`, `unreported_count`), `duration_ms_total` (integer >= 0), `attribution_confidence_histogram` (`exact`, `window`, `unattributed` counts). Invariant: `reported_count + unreported_count` equals `invocation_count`.

## Batch Rollup Record (`batch_rollup`)

Aggregates units for one batch. Fields: `batch_id` (non-empty string), `generated_at`, `unit_count`, `invocation_count`, `stop_reason_histogram`, `tokens`, `nested_tokens`, `cost`, `duration_ms_total`, all with the same shapes as the unit rollup, plus `budget` and the optional `yield_tally`.

The budget object records the batch's declared soft budgets and the flags raised against them: `declared` carries `tokens`, `cost`, `wall_clock_ms`, and `requests`, each a number or null (a dimension with no declared budget stays null), and `over_budget` lists the flagged dimensions. Dimension comparisons are pinned so ORCH-4-6 consumes them without reinterpretation: `tokens` compares `tokens.input + tokens.output` (cache traffic excluded, the billed-adjacent denominator), `cost` compares `cost.amount_sum`, `wall_clock` compares `duration_ms_total`, and `requests` compares `invocation_count`.

A dimension may appear in `over_budget` only when its declared value is non-null and its actual exceeds it; the validator enforces this flag-side consistency. Flagging every exceeded dimension is the rollup tool's duty and is tested at ORCH-4-3-4. Overages are routed, never enforced: each flag is emitted as `over-budget(<dimension>)` in the digest and the batch task's Work Log, and routes to manager investigation or user escalation. No code path in the measurement tool terminates processes, edits task state, or gates closure; the runner usage-limit park and restart remains the only hard tripwire (parent Decision Log, "Soft budgets investigate or escalate, never terminate").

The yield-tally object is optional (absent until a batch's tally is compiled) and fully typed when present, per artifact 20 DC1 refined by artifact 27 Q11. Every count names its source report link in `source_links`, which must carry at least one entry.

| Field | Meaning |
|---|---|
| `verifier_findings_by_severity` | map of severity name to count of verifier findings at that severity |
| `verifier_caught_defects` | defects the verifier caught before review |
| `reviewer_blocker`, `reviewer_major`, `reviewer_minor` | reviewer findings by severity |
| `escaped_defects` | defects found after review passed (the falsifiability side of the adopt-selectively verdict) |
| `false_positives` | findings dispositioned as rejected |
| `time_to_close_ms` | elapsed time from batch start to close, or null when not yet closed |
| `batch_cost_total` | the batch's cost total, or null when no reported cost exists |
| `source_links` | at least one report link backing the counts above |

## AC-12 Snapshot Record (`ac12_snapshot`)

One record per access-metrics probe run, before or after. Fields: `generated_at`, `phase` (`before` or `after`), `harness` (`pi` or `opencode`), and `families`, an object with exactly the five family keys `read_latency`, `context_token_cost`, `command_failures`, `retrieval_completeness`, `permission_denials`. Each family carries `method`, `source`, `values` (a map of metric name to number or null), and `notes` (string or null). The measurement protocol, the fixed question list, and the before/after comparability rules live in `ac12-probe-spec.md` alongside this document.

## Consumers

ORCH-4-3-2 (pi extractor) and ORCH-4-3-3 (opencode extractor) write invocation records against this schema; ORCH-4-3-4 derives rollup records, emits budget flags, compiles the first yield tally, and captures the before snapshot; ORCH-4-6 reads declared budgets and token denominators for slimming targets; ORCH-4-7 reads per-invocation tokens, cost with source marking, and stop reasons for the cross-provider comparison. Schema changes that any consumer cannot absorb require a version bump, not a silent reinterpretation.
