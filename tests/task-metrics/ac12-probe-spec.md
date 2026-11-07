# AC-12 Probe Spec

The fixed measurement protocol for the CLI-parity access metrics (AC-12, artifact 38 addendum): task-read latency, context and token cost, command failures, retrieval completeness, and permission denials, captured once before the CLI-only migration (ORCH-4-9) begins and once again at its closure, so the migration's benefit claim stays falsifiable. Each probe run lands as an `ac12_snapshot` ledger record (phase `before` or `after`) shaped by `ledger-schema.md`; ORCH-4-3-4 captures the before snapshot at first-baseline time, and the after capture belongs to ORCH-4-9 and ORCH-4-10 closure.

## Metric Families

| Family key | Measurement method | Derivation source | Values recorded |
|---|---|---|---|
| `read_latency` | median and p95 over 10 timed `tasks show <taskfile>` invocations against a representative task file | probe wall-clock stopwatch | `p50_ms`, `p95_ms`, `samples` |
| `context_token_cost` | tokens consumed by the probe session while performing the full question list below | ledger extraction once the extractors exist; before that, a hand spot check of the probe session's own logs, noted in `notes` | `input`, `output` |
| `command_failures` | count of nonzero task CLI exit codes during the probe run, over the total commands run | probe exit codes | `commands`, `failures` |
| `retrieval_completeness` | fraction of the fixed question list answered correctly against the live board, scored per question (1 correct, 0 wrong, null not attempted) | manual scoring against the board | one value per question id (`q1` through `q5`) |
| `permission_denials` | denial-shaped error tool results in the probe session's persisted session content | session JSONL derivation (pi 3, oc 4 class evidence; recon gap 1: neither harness logs a denial event) | `denials` |

Permission denials are derived rather than logged in both phases. The harness-adjacent fallback named in the parent plan (a logging line in the pi permission-gate extension and the opencode plugin event hook) stays gated on the first baseline run proving the derived signal insufficient; if it lands mid-protocol, the Comparability Rules require a re-baseline.

## Fixed Question List

The five canonical retrieval questions below are pinned verbatim for both phases; scoring treats a question as correct only when every part of its expected answer is present.

| Id | Question | Expected answer source |
|---|---|---|
| `q1` | List every task currently in the In Progress lane of the board, by ID and name. | dashboard In Progress table |
| `q2` | State the status, owner, and progress percentage of task ORCH-4-3-1. | that task file's header fields |
| `q3` | Name the latest report deposited under the ORCH-4-3 parent task and give its digest line. | that task's reports directory and Work Log |
| `q4` | List every task that declares a dependency on ORCH-4-3-1. | the declared dependency surfaces of the sibling task files |
| `q5` | Name the most recently updated task on the board and give its Updated timestamp. | the dashboard's Updated ordering |

## Comparability Rules

The two snapshots are comparable only under the rules below; a snapshot taken outside them cannot back a before/after claim.

The question list is identical verbatim in both phases. Changing a question, adding one, or changing its expected answer source is a protocol change: it voids the pairing and requires both a fresh before snapshot and a fresh after snapshot under the new list.

Each family keeps the same measurement method and derivation source across phases. A method that must change between phases (for example context_token_cost switching from hand spot check to ledger extraction once the extractors exist) is recorded in the changed family's `notes`, and the affected family is measured once more under the old method and once under the new in the same session, so the bridge between the two methods is itself measured rather than assumed.

Both snapshots are `ac12_snapshot` records with `generated_at`, `phase`, and `harness` pinned, on the same machine class where practical. The before snapshot is dated before any ORCH-4-9 work begins; the after snapshot belongs to ORCH-4-9 and ORCH-4-10 closure. Family deltas are reported per family (for example p95 read latency, tokens per question set, failure rate, fraction correct, denials per probe); the five families are never collapsed into one score.

The probe run itself is read-only against the board and the task files: it runs `tasks show`, `tasks render`-equivalent reads, and report listings, and writes nothing under `.tasks/` beyond what the harness itself records. Probes never claim, edit, close, or re-render tasks.
