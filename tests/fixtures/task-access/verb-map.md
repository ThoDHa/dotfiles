# Task-Access Verb Map

The durable contract migrating the seven fleet roles from direct `.tasks/` access to
CLI-only access. Authored by ORCH-4-9-1, reconciled against the landed tasks CLI at base
`1cd4fad` (the ORCH-4-4 surface is fully landed and the binary in
`opencode/.local/bin/tasks` is the ground truth). ORCH-4-9-2 (skill homes) and ORCH-4-9-3
(charters, staged) implement the deltas recorded here; ORCH-4-9-4 runs the representative
executions. The executable form of the per-role command sets is `role-verbs.sh` beside
this file: the replay suite expands exactly those commands against a seeded fixture board
and proves them sufficient, and the Tier-B configs in `tier-b/` realize the target maps.

## Landed CLI Ground Truth

Twenty-three verbs exist in the landed binary. Read verbs inspect the board and mutate
nothing: `show`, `list`, `reports`, `export`, `lint`, `doctor`, `frontier`, `claims`,
`events`, plus `help` for usage text. Write verbs mutate the board: `init`, `render`,
`new`, `set`, `report`, `log`, `edit`, `claim`, `release`, `reclaim`, `archive`, `close`,
`stamp`. Task files resolve by path; archived tasks resolve by full path under `archive/`, and a
bare basename resolves current/-first with an `archive/` fallback (the landed resolver's
order, probed at ORCH-4-9-3's re-verification gate; the gate reconciled this paragraph,
whose conservative form named `current/` only). The task-files skill's raw escape hatch
(`tasks show <taskfile> --raw`) rides the authorized `show` verb's flag space: it is
admissible wherever a role's set admits `tasks show`, and the per-role sets carry
replay-proven `--raw` forms proven by ORCH-4-9-3's replay.

### Deviations From the Plan's Cited Contract (Reconciliation Record)

The parent ORCH-4-9 plan cites ORCH-4-4's pre-landing contract. The parent Decision Log
makes landed-surface divergence a re-planning trigger reconciled here first. Each
deviation below names the trigger it fires and the reconciliation this map applies.

| Plan cited | Landed reality | Trigger | Reconciliation |
|-----------|----------------|---------|----------------|
| `context --role` bounded role projections | No `context` verb exists | (a), (c) | Dropped as a dependency. Role-scoped reads are the per-role command sets in this map, built from the landed read verbs; no `--role` projection is awaited. |
| `history` verb (complete history) | No `history` verb exists | (a) | Complete history is `show --json` (every header field, complete section bodies, structured Work Log) plus the `events` ledger for claim and attempt provenance. |
| `show --full --json` | `show --json` carries the full snapshot; no `--full` flag | (a) | The map and all migrated text cite `show --json`. |
| Question/evidence records | No dedicated reader verb; evidence landed as the `close` gate's `(evidence: ../reports/...)` pointer check plus the typed `events` ledger | (a) | Evidence reads go through `reports --include-body --json` (bodies) and `events --json` (provenance); closure enforcement is `close`'s own gate, not a reader. |
| Lossless export | `export --format jsonl --include-reports` landed as contracted | none | Cited as landed; rollback-proof input for ORCH-4-9-4. |
| Write parity (planner nested edits, question updates, criteria changes) | `tasks edit --section <heading> [--append]` covers section bodies; `tasks set` covers header fields; both landed | none | The planner write replacement is `tasks edit`; criteria changes are `tasks edit --section "Success Criteria"`. |
| CLI path for task-file-less research deposits | `tasks report` requires a resolvable task file; no research-target form exists | (b) | Fired: the research-deposit exception is RETAINED for the planner (see the planner entry). Text retaining it carries the `task-access-sanctioned` marker so the drift check tolerates it visibly until the CLI path lands and the exception is removed. |

## Role Contracts

Each entry records the role's authorized read commands, write channels, permission-map
deltas against the charter's current frontmatter, the direct-access patterns being
replaced, and the parity proof. Command spellings are the landed CLI's, byte-faithful to
`role-verbs.sh`, which the replay suite executes.

### Planner

| Aspect | Contract |
|--------|----------|
| Authorized reads | `tasks list --json`; `tasks show <taskfile>`; `tasks show <taskfile> --json`; `tasks show <taskfile> --raw`; `tasks show <taskfile> --section <heading>`; `tasks reports <taskfile> --json`; `tasks reports <taskfile> --include-body --json` |
| Write channels | `tasks log <taskfile> --from planner "<msg>"`; `tasks report <taskfile> --slug <slug> --from planner --digest "<line>"`; `tasks edit <taskfile> --section <heading> [--append]` (the widened planner write channel: planning sections via the CLI edit write model) |
| Map deltas | Remove `{ action: edit, resource: ".tasks/**", effect: allow }`, replaced by the explicit `{ action: edit, resource: ".tasks/**", effect: deny }`. Add after the shell catch-all deny: `tasks show *`, `tasks list *`, `tasks reports *`, `tasks edit *` allows. Keep the existing `tasks log *` and `tasks report *` allows. `ls`/`cat`/`grep`/`wc` allows remain for territory (repo) reads only; no allow is added that reaches `.tasks` arguments. While the retained exception below stands, the map carries `{ action: edit, resource: ".tasks/reports/research/**", effect: allow }` immediately after that `.tasks` deny: last-match-wins keeps it narrow to the research subtree, `tier-b/planner.yaml` mirrors the pair above its fixture-denial-tail marker, and the allow goes away with the exception when a CLI research-deposit path lands (the explicit deny stays). |
| Replaced direct access | Rule-1 direct read of the named task file (reads go through `show`); planning-section fills via the task-files skill's planning-mode exception direct edit writes (go through `tasks edit`); `cat`/`grep` reads of `.tasks` paths (go through the read verbs). |
| Retained exception | The research-deposit exception stays (deviation table, trigger b): planner research reports still land by direct write at `.tasks/reports/research/`, carried in mechanism by the interim map allow recorded in the deltas above and mirrored in `tier-b/planner.yaml`, and the retaining text carries the `task-access-sanctioned` marker. The exception's removal is ORCH-4-9-2's, gated on a CLI research-deposit path existing and passing the fixture; the allow goes with it. The Tier-B suite pins realizability: the exception must yield ALLOW under its fixture config, or the contract is lying. |
| Parity proof | Replay suite planner scenario: reads the parent's planning sections and the seeded recon report, round-trips a `tasks edit` section write, logs, and deposits a report, all under the PATH shims. |

### Reviewer

| Aspect | Contract |
|--------|----------|
| Authorized reads | `tasks show <taskfile> --json` (structured Work Log); `tasks show <taskfile> --raw`; `tasks show <taskfile> --section <heading>`; `tasks reports <taskfile> --json`; `tasks reports <taskfile> --include-body --json` (worker report bodies); `tasks list --json` |
| Write channels | `tasks report <taskfile> --slug review --from reviewer --digest "<line>"` (unchanged; already CLI-only) |
| Map deltas | Add after the shell catch-all deny: `tasks show *`, `tasks list *`, `tasks reports *` allows. No removals: the reviewer never held an edit or `.tasks` write allow. |
| Replaced direct access | Worker report files read directly under `.tasks/reports/` (go through `reports --include-body`); Work Log entries read directly inside child task files (go through `show --json` and `show --section "Work Log"`); plan-draft planning sections read directly (go through `show --section`). |
| Parity proof | Replay suite reviewer scenario: reads the worker report body and Work Log provenance, reads a planning section, deposits the review, all under the shims. |

### Worker

| Aspect | Contract |
|--------|----------|
| Authorized reads | `tasks show <taskfile>`; `tasks show <taskfile> --json` (the dispatched child task file: dispatch entries, Success Criteria, state); `tasks show <taskfile> --raw` |
| Write channels | `tasks log <taskfile> --from <agent-id> "<msg>"`; `tasks report <taskfile> --slug <slug> --from <agent-id> --digest "<line>"` (already CLI-only; unchanged). The worker runs under the dispatch's exported `TASKS_SESSION`, the claiming session's, so its `tasks log` and `tasks report` checkpoints refresh the claim's expiry heartbeat (the manager-claims/worker-deposits handshake below); a foreign session's checkpoint does not refresh a claim and says so on stderr. |
| Map deltas | None: the worker's allow-first map already permits the CLI verbs. The contract text change is wording only (the dual-harness note's "writes under `.tasks/` are plain file writes in both harnesses" framing becomes CLI-channel framing). |
| Replaced direct access | Direct read of the dispatched task file (goes through `tasks show`); the plain-file-write framing in the dual-harness note (reworded to the two CLI channels). |
| Parity proof | Replay suite worker scenario: reads its task's JSON snapshot, logs an interim checkpoint, deposits the final report, all under the shims; the handshake scenario proves the worker's checkpoints advance a manager-held claim's heartbeat and that a foreign session's does not. |

### Advisor

| Aspect | Contract |
|--------|----------|
| Authorized reads | `tasks show <taskfile> --json`; `tasks show <taskfile> --raw`; `tasks show <taskfile> --section <heading>` (evidence anchors); `tasks reports <taskfile> --json`; `tasks reports <taskfile> --include-body --json` (report bodies); `tasks list --json` |
| Write channels | `tasks log <taskfile> --from advisor "<msg>"`; `tasks report <taskfile> --slug <slug> --from advisor --digest "<line>"` (unchanged) |
| Map deltas | Add after the existing `tasks log *` and `tasks report *` allows the planner's four-allow read-and-write block byte-identically (the planner row carries the spellings; lint-corpus check 7 pins the two shell-rule blocks together, so the addition lands in both files in the same order). The gate reconciled this row, which first named only the three read verbs, to the four-allow block the identity pin and `tier-b/advisor.yaml` carry; the advisor's contract bars any edit write, so the shared write allow stays map-real and contract-unused on the advisor. |
| Replaced direct access | Evidence anchors read directly from task-file sections via `cat` or the read tool (go through `show --section`); report indexes scanned by directory listing (go through `reports --json`). |
| Parity proof | Replay suite advisor scenario: reads the seeded Decision Log anchor and report index, logs, deposits, all under the shims. |

### Manager

| Aspect | Contract |
|--------|----------|
| Authorized reads | All read verbs in their proven replay forms: `tasks show <taskfile> --json`; `tasks show <taskfile> --raw`; `tasks show <taskfile> --section <heading>`; `tasks list --json` (with `--lane <lane>` as needed); `tasks reports <taskfile> --include-body --json`; `tasks export --format jsonl --include-reports`; `tasks lint`; `tasks doctor --json`; `tasks frontier --json`; `tasks claims --json`; `tasks events --json` |
| Write channels | All write verbs: `tasks new`; `tasks claim`; `tasks edit --section <heading> [--append]`; `tasks set`; `tasks log`; `tasks report`; `tasks release --generation <token>`; `tasks close`; `tasks stamp`; `tasks archive`; `tasks reclaim`; `tasks render`; `tasks init` (the scaffold-time channel, proven on an initialized board by the replay). Instructions Given dispatch entries are appended through `tasks edit --section "Work Log" --append` (indented `#` lines inside the quoted instructions, per the heading-delimiter hazard). The manager-claims/worker-deposits handshake binds claims to dispatches: a dispatch runs with the claiming session's `TASKS_SESSION` (or the claim carries the worker's `--owner` id), so the dispatched worker's `tasks log` and `tasks report` checkpoints refresh the claim's expiry heartbeat; a long-running worker must not be dispatched under a foreign session, or its checkpoints leave the heartbeat silent and the claim expires under active work. A foreign session's checkpoint never refreshes a foreign claim and says so on stderr. Pinned by the replay suite's handshake scenario. |
| Map deltas | None in this migration: the `edit .tasks/**` allow is RETAINED as the interim recovery channel (parent Decision Log) while the contract text migrates to CLI-only normal operation. The allow's removal is ORCH-4-10's, once the enforced boundary and the controlled-exception mechanism exist. The Tier-B fixture config denies this allow for the representative executions, proving the CLI suffices without it. |
| Replaced direct access | Instructions Given entries written directly into the Work Log (go through `tasks edit --append`); task-file status writes performed by direct header edits (go through `tasks set`); direct reads of filled-out task files, work logs, and claims (go through the read verbs); direct planning-prose edits (go through `tasks edit`). |
| Parity proof | Replay suite manager scenario: full lifecycle (init scaffold re-run, new, claim, edit, set, log, report, read verbs, close, stamp, archive, archived read, export, render, reclaim no-op), board left lint-clean. |

### Scout

| Aspect | Contract |
|--------|----------|
| Authorized reads | None: the scout names no task-file access today and gains none. |
| Write channels | None. |
| Map deltas | None: expected zero-diff role. The Tier-B scout fixture config carries the denial posture and the transcript audit covers the read-tool gap. |
| Replaced direct access | Nothing to replace; the fixture confirms the absence stays absent. |
| Parity proof | Replay suite scout scenario asserts the authorized set is empty by contract; the Tier-B config validation proves direct-access probes deny. |

### Verifier

| Aspect | Contract |
|--------|----------|
| Authorized reads | None added: the verifier names no task reads today. |
| Write channels | `tasks render` (the existing allow; a CLI write operation, unchanged). |
| Map deltas | None: expected zero-diff role. |
| Replaced direct access | Nothing to replace. |
| Parity proof | Replay suite verifier scenario: `tasks render` succeeds and the derived dashboard is byte-identical before and after. |

## Constraints the Migration Stages Must Honor

- Planner and advisor shell-rule blocks must stay byte-identical (lint-corpus check 7): the read-verb allows land in both files, in the same order, in one change each.
- Deny-first maps (planner, reviewer, advisor) admit no command without an explicit allow: the read-verb allows are load-bearing, and opencode's ordered rules mean position matters (the last matching rule wins, so exception allows sit after the catch-all deny and fixture denies sit after everything).
- Line budgets bind the charter edits (manager 390 hard cap at current count, planner 125, reviewer 150, advisor 95); the manager's migrated wording must be net-zero or the budget decision is surfaced, never silently taken.
- The manager body's digest pin (`tests/pi-agents/manager-body.sha256`) and the vendored copy regenerate through the make targets inside the manager stage commit.
- The drift check's migrated-surfaces list (`migrated-surfaces.txt`) starts EMPTY at this landing; each stage appends its migrated surfaces and the check must be green at every stage commit.
- A permission-map-bearing surface (a charter or agent file whose frontmatter carries the permission stanza) is listed as `<path> @<role>`: its frontmatter is machine data, map-diffed against `tier-b/<role>.yaml` above that config's fixture-denial-tail marker, not text-scanned; body prose outside the frontmatter still follows the text patterns. The manager's retained interim allow is green under the map-diff because the target map retains it until ORCH-4-10.

## Fixture Boundary

The harness proves contract sufficiency and role discipline, not enforcement. Tier A runs each role's authorized commands against a seeded `TASKS_DIR` fixture board under PATH shims that refuse direct `.tasks` arguments for the shell file tools, so a passing replay proves the authorized set returns everything the role needs without touching a task file, and the shim refusals prove the direct routes fail. Tier B pairs per-role fixture permission configs (edit and shell denies, mechanically evaluated as ordered last-match-wins rules) with a transcript audit. Two coverage gaps are named rather than papered over. First, opencode maps have no read action, so the native read tool cannot be denied mechanically today: the audit covers that gap by detection, not denial. Second, interpreter and write-tool routes are closed only by enumeration: deny-first roles catch them in the catch-all deny, while the allow-first roles (worker, manager) deny them stem by stem in their fixture denial tails and the audit's V1 class detects the same routes; the audit header records the path-token model as the future alternative to the stem list. Hard enforcement with bypass tests is ORCH-4-10's feasibility-gated work; nothing here claims a filesystem boundary. The fixture suites never write the live board: every suite pins `TASKS_DIR` to a temp root.
