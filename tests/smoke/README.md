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
| S14 | Batch closure: one combined seam review plus the proportional watchdog, teardown scoped to the batch's own deposits | RO-265 | FL-05 |
| S15 | Unit tiers assigned and presented, floors never drop, design-bearing adds the second memo, no dispatch before sign-off | RO-257 | FL-03 |
| S16 | Delegation as default: bounded lookup direct, delegable item dispatched, uncertainty defaults to delegation | RO-253 | - |
| S17 | The sanctioned ordered pair lands fix-first pushed together; red-first never amended; pushed tips never rewritten | RO-064 | - |
| S18 | Board changes route through the tasks CLI, hand-editing the dashboard is refused, an existing deposit target is never overwritten | RO-197 | - |
| S19 | Ambiguous cleanup never triggers deletion and placeholder labels never substitute for real hierarchical IDs | RO-205 | - |
| S20 | The report body lives verbatim in the deposited report file and the Work Log carries only the link and the digest | RO-236 | - |
| S21 | The premature completion is refused until the criteria are met, the loop has converged, and the testing record holds | RO-094 | - |

S8-S10 are ORCH-4-6-2's per-touched-row scenarios (compression and
pointer-collapse surfaces the initial registry did not carry); S11-S13
are ORCH-4-6-3's, one per touched rules-corpus row, run under the rules
body composition (below); S14-S16 are ORCH-4-6-4's per-touched-row
scenarios for the delegation skill and S17 its git-protocol row, run
under skill-body compositions (below); S18-S21 are ORCH-4-6-4's
task-files pass scenarios for the compression families and inbound
collapses (S18 aggregates RO-197 with its RO-186 facet, S19 RO-205 with
its RO-221 facet, S20 grades RO-236, S21 aggregates RO-094's trigger
token with the RO-215/216/217 family), run under the skill-task-files
body. A "-" flash key marks a row with no Flash-era candidate.

## Modes

`run-smoke.sh --validate` is the hermetic instrument check chained into `make test` and `make verify-inner` as `test-smoke`: every scenario file parses against the registry (id, RO key, FL key), declared fixtures exist, the S6 prompt carries the seven routing class names verbatim, the rules-body join is pinned byte-equal between the worktree-dir join and the HEAD ref join (both share the AGENTS.md generator's join implementation in `lib/rules-generator-common.sh`, so a join desync cannot land silently), and the grader self-test passes over synthetic transcripts. No model calls.

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

`--side-order fixed|alternate|random` (paired mode only, default
`fixed`) controls which side of each pair dispatches first, breaking the
confound of side with dispatch position: under the default the tip
always runs second in its time window, so a deterministic
second-dispatch position effect reproduces consecutively on the same
check exactly as a corpus delta would. `alternate` swaps every second
pair; `random` draws per pair from a seedable LCG and requires
`--seed N`. `fixed` preserves the historic behavior byte-for-byte
(manifest and delta formats included); under `alternate`/`random` the
mode and seed head `manifest.txt`, every row carries a sixth `order`
column naming the realized dispatch order, and the delta rows and table
header record the same, so a positional signature (an
about-half-of-reproductions flip of the red side under random) is
auditable from the artifacts alone. Artifact dirs stay keyed by side in
every mode; only the dispatch order moves, and per-side grading is
unchanged so deltas stay comparable.

Manifest discipline for recovered runs: `manifest.txt` in a run dir carries the union of every completed row. When a run is interrupted and its remaining rows are re-run into the same dir (a session-cap kill mid-queue, for example), the partial manifest is preserved alongside as `manifest-<stamp>-partial-<rows>.txt` and its rows are unioned into `manifest.txt` (or a pointer line inside `manifest.txt` names the partial file), so the run dir stays self-evidencing for audit without cross-referencing files.

## Two-tier rubric gate and rules-body composition

A scenario rubric may split its checks with `tier:` directives (`semantics`, the default, and `literal`): semantics checks are the routing/verdict/dispatch assertions the gate exists for; literal checks are vocabulary pins. A literal-only miss grades VOCAB, recorded as a non-gating vocabulary-drift signal (the paired table carries it as a VOCAB row); any semantics miss FAILs and gates at full force, in any single window, per the two-tier rule from the ORCH-4-6-2 review's second memo. Scenario header `body: rules` swaps the injected corpus: instead of the manager charter the session receives the four rules files in the AGENTS.md generator order, joined exactly as that generator joins them (one blank line between files, none after the last), so the injected corpus is the always-on chain body byte-for-byte; `body: manager` (default) keeps the charter; `body: skill-<name>` injects the named on-demand skill's SKILL.md verbatim, frontmatter included; a real summon sits that skill on top of the always-on rules chain, which the skill-only session omits. Paired mode builds a baseline and tip body per kind from the same ref/worktree split.

Rubric authoring rule for skill-body scenarios (ORCH-4-6-4 review DC2): a content-tier pin may only cover text the skill retains after a collapse. The skill-only composition omits the rules chain, so a pin on text a collapse moved into the rules false-reds under the skill-only body while the real composed session behaves fine; pin retained skill text or the reply-stated decision instead. A composed rules+skill body kind for content-tier checks is declined (ORCH-4-6-4 review, same disposition): it adds harness surface and lets rules edits perturb skill rows.

Standing vocabulary disposition for S21 (ORCH-4-6-4 tf-fix round): the completion-gate scenario's literal-tier `simplif` pin checks the reply for the simplify-review vocabulary, and the pin missed on 2 of 4 observed tip runs of the task-files battery while every semantics check passed; that is a stable vocabulary-drift signal, a literal-only miss grades VOCAB under the rule above, and future batteries record the VOCAB row without re-classifying it manually.

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

Addendum figures quoted in run reports are the runner's wrapper measurement and sit a constant +22 chars over the injected body file's own `wc -m` count (the ORCH-4-6-4 verifier reconciled 70846 wrapper against 70824 body on the same injection); reconcile deltas, not absolutes, against census figures.

## Scenario file grammar

Header lines (`id`, `title`, `ro-key`, `flash`, `timeout`, repeatable `fixture:`, `body:`), then `--- prompt ---` with the verbatim dispatch, then `--- rubric ---` with the mechanical checks: `require:`, `forbid:`, `require-if: A=>B`, `require-any: A|B`, `tool-require: AGENT`, `tool-forbid: AGENT`, `tool-max: AGENT N` (where `AGENT` may be the reserved word `total`, bounding the sum of all named dispatch slots), `tool-min: AGENT N`, `tools-max: NAME N` (any toolCall block, subagent included, N >= 0), `reply-max-lines: N`, and `tier: semantics|literal` directives. Matching is literal and case-insensitive with whitespace-run tolerance; rubrics grade the routing decision the reply states, never clause quoting, so a pass says the behavior survived and a fail says it did not. The prompt's output-contract lines (labeled decision lines) are what make the grading deterministic.

## Extending

One scenario per touched prompt-soft row per slimming subset; the registry
above is the initial set. A new scenario adds a file under `scenarios/`
with an id outside S1-S7 or replaces a registry row only through the
contract's erratum discipline; `--validate` refuses registry mismatches,
duplicate ids, and lost class-name pins.
