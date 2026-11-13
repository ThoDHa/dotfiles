# Smoke Harness

The agent-contract smoke harness for the manager routing surface: the
ORCH-4-6 blocking entry-criterion instrument and the equivalence-check
instrument for every prompt-soft Flash-era candidate the slimming wave
touches. Runner: `tests/smoke/run-smoke.sh`; scenarios: `tests/smoke/scenarios/`;
fixtures: `tests/smoke/fixtures/`; parser, registry, and grader:
`tests/smoke/smoke_lib.py`.

## Scenario registry

Seven pinned scenario classes (locked contract section 4; the four
dispatch-named ones, S1/S4/S5/S6, are the blocking core). Names are the
pins; file line ranges never are.

| ID | Class | Matrix row | Flash candidate |
|----|-------|------------|-----------------|
| S1 | Wrong-agent reply routes to triage, not pipeline advance; verdict vocabulary and escalation lanes exercised | RO-170 | FL-01 |
| S2 | Artifact-less, verdict-less reply caught by the artifact pass | RO-170 | FL-01 |
| S3 | Cross-claim contradiction across report claims vs available evidence | RO-170 | FL-01 |
| S4 | False falsifiable claim in an advisor memo surfaced by the checked-decision stamp; unstamped approval drift detected | RO-171 | FL-02 |
| S5 | Verdict-relay fidelity: consequential text reaches the user verbatim under a one-line digest | RO-173 | FL-04 |
| S6 | Seven-class routing by class names, direct lane and prior-memo bar as negative cases | RO-168 | FL-06 |
| S7 | Batch record-drift watchdog on a drifted batch | RO-267 | FL-05 |
| S8 | Consequential design-challenge ruling obtains the second adversarial advisor pass | RO-172 | FL-03 |
| S9 | Dispatch discipline: delegation default, never-implement routes, resume versus fresh, worktree regimes | RO-115 | FL-07 |
| S10 | Git integration plan preserves the ordered pair, pushed tips, staging scope, and teardown | RO-063 | - |
| S11 | Memory-store check on a tool-less session reports failure and never fabricates recall results | RO-021 | - |
| S12 | A five-component task pauses with the execution-approach options instead of starting work | RO-101 | - |
| S13 | The execution-approach pause bars any execution until the user directs the approach | RO-105 | - |

S8-S10 are ORCH-4-6-2's per-touched-row scenarios (compression and
pointer-collapse surfaces the initial registry did not carry); S11-S13
are ORCH-4-6-3's, one per touched rules-corpus row, run under the rules
body composition (below). A "-" flash key marks a row with no Flash-era
candidate.

## Modes

`run-smoke.sh --validate` is the hermetic instrument check chained into
`make test` and `make verify-inner` as `test-smoke`: every scenario file
parses against the registry (id, RO key, FL key), declared fixtures exist,
the S6 prompt carries the seven routing class names verbatim, and the
grader self-test passes over synthetic transcripts. No model calls.

`run-smoke.sh` (optionally `--scenario S1`, `--model provider/id`,
`--thinking LEVEL`, `--run-dir DIR`) is the live mode, explicit invocation
only and never chained: each scenario dispatches the manager body under
test headless through pi and grades the JSON transcript mechanically
against the scenario rubric. Live runs land under
`/tmp/llm/smoke/<run-id>/` (transcript, reply, checks, verdict per
scenario, plus `manifest.txt`). Exit status gates the battery: any FAIL,
ERROR, or timeout exits nonzero; nothing skips silently. Development
mode: one body, absolute verdicts.

`run-smoke.sh --paired` (same options plus `--baseline-ref REF`, default
`main`) is the paired delta mode, explicit invocation only: per scenario
it dispatches the baseline body (the manager body at `--baseline-ref`)
and the tip body (the worktree source) back to back, so each pair sits
in the tightest possible time window and model-behavior drift hits both
sides alike, then grades both and emits a per-scenario delta table
(persisted as `delta.txt` next to the paired `manifest.txt`). Gate
semantics are delta-based over the gating registry S1-S7 (S8-S10 are
advisory rows until they carry their own baseline plus stability): RED
only on a graded tip FAIL where the baseline PASSed (a regression the
corpus edit caused); both-FAIL is instrument-inconclusive drift,
recorded but not red; a tip PASS is green whatever the baseline did;
instrument errors (timeout, pi exit, grader crash) are never graded
verdicts and stay inconclusive. Exit 0 = green-by-delta, 1 = regression
on the gating set (stop: rollback is the manager's decision), 2 = no
gating scenario produced green, vocab, or regression evidence (an
entirely broken instrument must not exit 0).

## Two-tier rubric gate and rules-body composition

A scenario rubric may split its checks with `tier:` directives
(`semantics`, the default, and `literal`): semantics checks are the
routing/verdict/dispatch assertions the gate exists for; literal checks
are vocabulary pins. A literal-only miss grades VOCAB, recorded as a
non-gating vocabulary-drift signal (the paired table carries it as a
VOCAB row); any semantics miss FAILs and gates at full force, in any
single window, per the two-tier rule from the ORCH-4-6-2 review's second
memo. Scenario header `body: rules` swaps the injected corpus: instead
of the manager charter the session receives the four rules files
concatenated in the AGENTS.md generator order, so always-on chain
behavior grades under the same composition contract; `body: manager`
(default) keeps the charter. Paired mode builds a baseline and tip body
per kind from the same ref/worktree split.

## Live composition contract

The live session is pi preamble plus the fleet manager body extracted from
the worktree source (`opencode/.config/opencode/agents/manager.md`),
injected via `--append-system-prompt` with Manager Mode's deployed body
suppressed (`PI_MANAGER_MODE=off`), so exactly one charter runs and it is
the file under test; host deployment points at the main tree, never this
worktree, so the harness binds to the corpus under test by injection. The
rules chain, skills, prompt templates, and MCP are off; extensions stay on
so the subagent tool exists and fleet dispatches run for real. The graded
behaviors (triage checklist, verdict vocabulary, checked-decision stamp,
escalation lanes, verbatim-first relaying, seven-class routing, watchdog)
are charter mechanics, and the composition stays constant across baseline
and post-edit runs so a delta is attributable to the corpus edit alone.
The runner asserts the injection mechanically (system-addendum size), so a
stale or missing injection fails as an instrument error instead of grading
the wrong charter.

## Scenario file grammar

Header lines (`id`, `title`, `ro-key`, `flash`, `timeout`, repeatable
`fixture:`, `body:`), then `--- prompt ---` with the verbatim dispatch,
then `--- rubric ---` with the mechanical checks: `require:`, `forbid:`,
`require-if: A=>B`, `require-any: A|B`, `tool-require: AGENT`,
`tool-forbid: AGENT`, `tool-max: AGENT N`, `tool-min: AGENT N`,
`tools-max: NAME N` (any toolCall block, subagent included, N >= 0),
`reply-max-lines: N`, and `tier: semantics|literal` directives. Matching
is literal and case-insensitive with whitespace-run tolerance; rubrics
grade the routing decision the reply states, never clause quoting, so a
pass says the behavior survived and a fail says it did not. The prompt's
output-contract lines (labeled decision lines) are what make the grading
deterministic.

## Extending

One scenario per touched prompt-soft row per slimming subset; the registry
above is the initial set. A new scenario adds a file under `scenarios/`
with an id outside S1-S7 or replaces a registry row only through the
contract's erratum discipline; `--validate` refuses registry mismatches,
duplicate ids, and lost class-name pins.
