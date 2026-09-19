# OpenCode Orchestration Design

This note documents the manager, worker, verifier, reviewer, and
planner agent pipeline, the git authority model, and the task-file
integration. The
agent files under the opencode config carry the normative requirements
in RFC 2119 form; this note explains the architecture and the
reasoning behind them.

## Roles

| Agent | Mode | Model | Duties |
|-------|------|-------|--------|
| manager | primary | session | Decomposition, dispatch, unit worktrees and branches, planning approval, architecture duties at coordination scale (exploration, builds, verification runs, CI/CD operation), integration and history shaping, pushes, reconciliation |
| worker | subagent | glm-5.3-flash | Implementation inside an assigned territory, checkpoint commits on the unit branch, real-time work logs, reports |
| verifier | subagent | glm-5.3-flash | Runs tests, linter, and typechecker once each, reports raw results without interpretation |
| reviewer | subagent | session | simplify-review in analysis-only mode, advisory plan critiques between drafting and approval, expectation checks, no command execution beyond read-only git |
| planner | subagent | session | Planning labor: reconnaissance, drafting the Triage task file's planning sections ahead of the manager's Triage → Ready approval, shared recon deposits, no implementation |

The manager is a coordinator, not an implementer: it holds no
implementation duty (it never authors implementation content), and its
file edits are limited to `.tasks/**`. Integration commits and pushing
are coordination duties, not implementation work; unit workers commit
their own checkpoint work on the branches the manager assigned them.
The architect grant follows the same line: the manager delegates as
much work as the fleet can take, and the command freedom exists to
unblock and steer the fleet (scouting a dispatch, unblocking a worker,
checking a unit's result); any duty that grows into sustained work of
its own is dispatched to a fleet agent rather than absorbed, since
capability never reduces the delegation duty.

The verifier and reviewer split verification along the judgment line:
transcription of command results is mechanical and runs on the flash
model, while code review and result interpretation need the full model.
The verifier reports exit statuses, the runner's own counts, and
verbatim failure output; interpretation happens in the manager's
reconciliation, never inside the verifier.

## Git authority

Workers never push, in any form: the `git push*` permission is denied and
the prompt prohibition covers force variants, aliases, and `sh -c` routes.
Under the worker-commit model recorded here, the manager creates a
worktree under `.worktrees/` and a unit branch for every unit dispatched
alongside a running sibling before the dispatch goes out (a lone unit may
use the main tree), and the worker commits territory-scoped work at each
meaningful checkpoint on that branch, every commit a complete logical
change leaving the suite green (normative in the worker agent file). The
branch and its commit range give per-unit attribution, and in-flight
work survives a lost session: crash resilience and attribution are the
model's payoffs, alongside per-unit verification against the branch.

The manager owns integration and history (normative in the manager agent
file). It verifies against the unit branch, and on a pass shapes the
branch judgment-based: squash or merge the checkpoints into one commit
when they form one logical change, preserve separable commits when they
stand alone, then integrate the result into the main line. Full git
control (rebase, amend, reset, revert; fetch and pull denied per known
limits) is granted in the manager's
permission map; force-push variants stay ask-gated, and pushed history
is reshaped only on explicit user request. Staging is reserved for a
main-tree unit's output: only the files that worker changed, never
pre-existing changes. Before the first dispatch the manager confirms a
clean tree with `git status` and records the base commit with
`git rev-parse HEAD`.

The manager pushes on its own judgment once a unit is integrated and
verified, the verifier's results are clean, and the review passed,
without waiting to be asked, and pushes whenever the user asked; it
never pushes half-finished or unverified work and never when the user
forbade it. Pushed history is immutable: the manager never reshapes,
amends, or rewrites anything already on the remote; it does so only
when the user explicitly requests it, never on its own initiative, and
then via force-with-lease per the
`git-protocol` skill. A unit working in a worktree reaches the `.tasks`
board by directory walk-up (see known limits), so unit branches need no
board mirroring.

## Task-file integration

When the task-files protocol is active, each unit is a child task file,
and every `.tasks/` write has exactly one owner. The manager owns the
task files themselves: header fields, acceptance-criteria checkboxes,
status transitions, body prose through `tasks edit`, and the dashboard,
rendered through the `tasks` CLI. Dispatched agents own exactly two
channels, both inside that CLI and both attributed to them via
`--from`, per the task-files skill's Agent Write Path: interim progress
as appended Work Log entries, and the final report as a verbatim
deposit under `.tasks/reports/` whose Work Log entry carries the
agent-supplied digest and a relative link. The manager never restates
report bodies: its dispatch entry records the instructions given,
written before the call, and its analysis is an independent check on
the digest, not a retelling. A worker that finds the plan wrong flags
that in its report instead of editing the file. The single carve-out is
the planning-mode exception: the planner agent dispatched to plan a
Triage task may edit exactly the planning sections of that named file,
the list the task-files skill's Agent Write Path defines, while header
fields, checkboxes, Progress, status, and the dashboard stay
manager-owned, and no status transition, Triage → Ready included,
belongs to the planner.

The reports mechanism keeps bulky output out of the task files, per the
task-files skill's Reports Namespace: one directory per task file under
`.tasks/reports/`, keyed by the file's full basename including `.md`,
holding deposits named `NN-<slug>.md`. `NN` is a zero-padded sequence
number assigned in deposit order, one past the highest already on disk,
so numbers are never reused even when gaps appear. Because `current/`,
`archive/`, and `reports/` are siblings, the `../reports/...` relative
link in a task file resolves identically from both directories, so
archiving moves the task file alone and reports never move. `tasks log`,
`tasks edit`, `tasks report`, and the dashboard render they trigger
each hold the exclusive `flock` on `.tasks/.lock` for their
read-modify-write span, a process-held lock released on exit, so
concurrent sessions serialize instead of racing.
`tasks show <taskfile> --tail N` prints the header fields, the Latest
Update pointer, and the last N Work Log entries without taking the
lock: the delta read for catching up on a task. Until the subcommands
exist in an environment, the manual fallback preserves the same
contract by hand: the worker writes the next report file at the
canonical path without overwriting and returns path and digest to the
manager, who makes the entry and header writes (the task-files skill's
Manual Fallback). Without task files at all, worker reports go to
`/tmp/opencode/reports/<unit-name>.md` as artifacts.

Every completed task's Final Summary opens with a closure digest, at
most five lines naming the outcome, the key decisions, and links into
the details (report deposit paths, the Decision Log), sized
proportionally to the task; the normative text is the task-files
skill's Closure Digest section. When planning fans the work out into
parallel children with overlapping territory, a shared reconnaissance
artifact is the default: the planner deposits a `01-recon` report via
`tasks report --slug recon`, and each child references it from its
Files to Review, so exploration happens once instead of once per
child; skipping it requires a Decision Log exception naming the reason
(a single child, territory already mapped, or the unknown-contract
case where a walking skeleton precedes fan-out). The normative text is
the task-files skill's Triage to Ready Planning Phase, tied to the
manager's approval review by the delegation skill's Planning Approval
Authority. Between the planner's draft and the manager's decision sits
an advisory plan-review gate for high-cost plans: when the breakdown
fans out into multiple parallel children, when checkpoint slicing
creates a shared contract seam between children, or when the user flags
high stakes, the manager dispatches the reviewer in analysis-only mode
to critique the planning sections before deciding. The critique is
input the manager weighs, addressed through planner corrections or
dismissed with a Decision Log reason; the verdict never binds, approval
and the Triage → Ready transition stay the manager's alone, and
low-cost plans skip the gate. The normative text is rule 2 of the manager
agent file and the plan-review dispatch type in the reviewer agent file.
Small tasks use the lite profile defined in the task-files skill.

## Dispatch economy

The dispatch economy requirements are normative in the
execution-standards global rule and bind every dispatcher, including
standard parallel spawns outside Manager Mode: dispatch prompts carry
pointers, not prose, with the objective and its success criteria as
the only narrative; global standards are never restated, since every
agent already receives them through the global instructions config;
verification commands are referenced via the project's AGENTS.md when
it documents them. Session resume for dependent units is the
delegation skill's context continuity rule: the manager resumes the
earlier unit's worker instead of dispatching fresh, so context stays
in the worker and reports are not retold through the manager. The
standing-session policy extends that per-unit rule to the batch
(normative in rule 5 of the manager agent file): when the next unit
is sequential over territory an in-flight or recently finished worker
whose session is still available already holds (the same files or
module, a fix/refine chain, or follow-up corrections), the manager
resumes that worker's session by task id instead of dispatching fresh.
The motivation is cost: every fresh dispatch re-pays the exploration,
file reads, and skill loads the prior session already made, and the
user's plan-level usage caps make that re-payment the dominant
avoidable cost in a sequential chain. Fresh dispatches with the report
as background remain required when the dependency crosses agents, when
the prior session's context is poisoned (unrelated failures, dead ends
that would mislead the next unit), or when the unit must run in
parallel with work already occupying that session. Two exclusions
stand regardless: the reviewer is never resumed across units, because
accumulated verdicts would erode its independence, the reason each
unit's review and the plan-review gate alike dispatch a fresh
reviewer; and the verifier stays stateless by design, its
transcription of command results carrying nothing worth resuming.

When work is tracked in task files, the dispatch prompt itself may be
a pointer instead of a duplicated payload, per the execution-standards
rule's Dispatch Economy and the delegation skill's Dispatch by
Reference: the manager writes the complete instructions verbatim into
the task file's Work Log (the Instructions Given entry) before making
the Task call, and that entry is the authoritative instruction record.
The call carries only a minimal bootstrap frame: the agent's role, the
task file to read, and the report-back expectation. Instructions are
written once, never restated in the call, and steering issued while
the agent runs goes through the dispatch channel, never only in the
file, since the agent cannot be assumed to re-read it mid-flight.

Dispatched agents also carry three conduct rules of their own,
normative in the same rule. Territory: stay inside the assigned files,
modules, and concerns, and flag a needed change outside them rather
than making it. Clarification routing: questions return to the
dispatcher in the reply, never to the user directly. Permission-denial
relay: a denial carrying a user message is a user question, so the
agent stops dependent work and returns the message verbatim to the
dispatcher; a bare denial is a hard no, not retried, with the blockage
routed to the dispatcher instead; the session-fatal case is covered
under known limits.

## Verification chain

Verification runs as a per-unit pipeline, not in batch (normative in
the manager agent file): when a unit's worker returns, that unit's
verifier and reviewer are dispatched in parallel. The reviewer is
path-scoped to the unit's diff against the base commit (the unit
branch's committed range, or a main-tree unit's uncommitted
working-tree changes); the verifier runs against the unit branch,
inside the unit worktree (isolated by construction), in the main tree
for a lone unit when the territories in flight are test-disjoint, or
pinned to a throwaway worktree at the unit's state (unit work
committed to a temporary branch, or the working tree copied in)
otherwise; when the shared state is verdict-relevant fixed state that
pinning cannot isolate, verification runs at the integration commit
instead. Neither edits files, and only the verifier runs non-git
commands, so the two cannot contend. Four independent sources are
reconciled per unit: the worker's claims from its report, the
verifier's raw command results, the reviewer's findings, and git
ground truth (`git diff --stat` and `git log` against the base
commit). The verifier always runs; the reviewer is skipped only when
the unit was mechanical (dependency bump, rename, formatting,
documentation-only). The reviewer does not re-report simplifications
the worker's own simplify-review run already records as addressed,
only findings that remain. The verifier runs the test suite, linter,
and typechecker once each and reports exit statuses, the runners' own
counts, and verbatim failure output, gating on exit status rather than
text matches. The reviewer verifies logged work against the unit's
objective, territory, and the actual changes, and runs the
simplify-review loop (simplify pass first, then review pass) without
fixing anything; it executes nothing beyond read-only git. The plan-review
dispatch that gates high-cost plans during planning is the one reviewer
dispatch without a diff: it assesses the task file's planning sections
against the codebase instead (see task-file integration), and its verdict
is advisory, never binding the manager's approval.

On a pass the manager integrates the unit and backfills the freed slot
immediately with the next Ready task whose dependencies are Completed
and whose territory is disjoint from the running set, so the pipeline
keeps its slots full instead of serializing on verification.
Discrepancies and findings get one fix-and-re-review round per unit; a
discrepancy that resurfaces after that round is deferred to a new task
rather than being hidden or looped. Reviewer suggestions each get one
disposition: small ones (mechanical, contained in the unit's changed
files) are done now by a worker and re-verified once, big ones and any
scope creep are deferred to their own new task as maybe-later work and
proposed as the next one, and only suggestions that do not serve the
user's intent may be declined, with a recorded reason. Every
disposition is recorded (Decision Log under task files, the completion
report otherwise), and undecided or unactioned suggestions are
restated verbatim to the user when work stops; without task files the
report is the only durable record. After the queue drains, one
combined seam review covers the seams between units before the batch
closes; the per-unit reviews see each unit in isolation, so only this
pass can catch cross-unit regressions.

Failure handling parks instead of blocking (normative in the manager
agent file, with the standing-restart grant for pure coordinators in
the delegation skill's Failure Semantics): on the failure of its
single mandated retry, the task is parked with a Blocked status
whose reason carries the failure summary and the attempt count,
reported to the user without blocking the queue. At every backfill or
checkpoint event, the oldest parked task whose blocking condition may
have cleared is restarted before fresh Ready work is pulled, never
into an unchanged condition. The retry count and the escalation
bounds (the total attempt bound, the identical-recurrence bound, and
the doubling restart-backoff schedule) are normative in manager.md and
not restated here; the backoff is measured on wall-clock time taken
from the board's own timestamps, since the tasks CLI stamps task file
headers (Updated) and Work Log entries with real times and the manager
reads the current time by refreshing a header through the CLI and
reading it back. This design
is the recording the delegation skill requires: the user's
standing-restart grant is recorded here and takes effect on this
task's sign-off, putting parking and checkpoint-rule restarts in force
for this orchestration from that point.

## Worktree isolation

Under the worker-commit model recorded here, a worktree under
`.worktrees/` on a unit branch is the default dispatch vehicle for a
unit dispatched alongside a running sibling, created before dispatch
and torn down after integration; a lone unit with no sibling in
flight may work in the main tree instead, and a parked unit's
worktree stays the one teardown exception, persisting while the unit
awaits its restart. Setups without the model reserve worktrees for same-file
contention that would otherwise serialize independent work. In both
regimes worktrees live inside the repo (disk-backed, no RAM cost),
verified gitignored via `git check-ignore`
before first creation, pruned (`git worktree prune`) before creation, and
torn down completely after integration or reconciliation: worktree removed,
metadata pruned, throwaway branch deleted (normative in the delegation
skill's Worktree Isolation and Worktree Teardown sections).

## Permissions posture

The global config allows `/tmp/**` for external-directory access and
auto-approves `doom_loop` so unattended runs cannot halt on repeated
identical tool calls. Agent permission tiers mirror their prompts: the
manager runs an allow-all bash map whose only carve-outs are the four
force-push ask entries (pushed history is reshaped only on the user's
explicit request per the git authority section) and the `git fetch*` /
`git pull*` denies behind the known limit that the manager has no
fetch or pull; gh carries no manager entries at all, so it holds full
gh access, writes and gh api included, for CI/CD coordination (the
read-only gh set, gh api excluded because patterns cannot gate its
HTTP method, now applies below the manager only: the worker's map;
the reviewer holds no gh at all); its edit denial is the single
architectural line, confining file edits to `.tasks/**` while bash
stays open; the worker holds everything except push, history
reshaping (commit amend and rebase, including pull-with-rebase, are
denied outright, matching the prompt prohibition), gh writes (the
read-only gh set), and subagent spawning; the verifier's bash is
intentionally open so it can run tests, gated only against push, and
its edit tool and subagent spawning are denied; the reviewer holds
read-only git only; the planner pairs that read-only git with
`make test*` and the two tasks CLI channels (`tasks log*`,
`tasks report*`), its edit map opens only `.tasks/**`, and its
subagent spawning is denied.

Recurring benign commands are pre-allowed so unattended runs do not stall
on permission prompts: worker, verifier, and planner allow `make test*`,
the repo's `test` and `test-*` targets (the manager's allow-all map
subsumes them, and the reviewer is deliberately excluded, since its charter
bars running tests), the worker additionally allows `mktemp` with templates
under `/tmp/opencode/*`, the invocation forms observed in its workflow, and
the planner allows the `tasks` CLI channels because its deny-first bash map
would otherwise block the recon deposit and its work-log entries. Config
and agent files load once at session start, so permission edits take effect
in newly started sessions; running sessions keep the maps they
already loaded.

Prefix-based bash permissions are guardrails against uninstructed behavior,
not security boundaries: a determined `sh -c` or `git -C` route slips past
them. Hard enforcement would require hooks or credential separation.

## LRU context plugin

The LRU context plugin and its `/lru` sidebar panel live in their own
repository, [opencode-lru-context](https://github.com/ThoDHa/opencode-lru-context):
`make install` there symlinks the three plugin files into
`~/.config/opencode/plugin/`, so the `plugin` array in opencode.json and the
`tui` entry in tui.json resolve against the symlinked files unchanged, and the
repository's DESIGN.md carries the full design note for the eviction
pipeline, the tools, the metrics log, and the panel. tui.json passes the TUI
entry one option, `sidebarSubagents: true`, so the session sidebar's LRU
group also lists the fleet's child sessions (worker, verifier, reviewer,
planner) aggregated by agent type; the option is off by default upstream.

## Known limits

- Soft rules (the worker's task-file write restraint, its real-time work
  logging duty, and the tasks CLI's two-channel write path) depend on
  the flash worker's adherence; the reviewer's expectation check is the
  backstop, except on all-mechanical tasks where the reviewer is skipped
  and the verifier's raw results plus git reconciliation are the only
  checks. The planner's restraint inside its planning-section carve-out
  is likewise prompt-soft, and the planner runs on the session model,
  not flash: the manager's planning review of the filled-out task file
  is its backstop. The plan-review gate on high-cost plans is advisory
  by construction: the reviewer's critique is one more input to that
  planning review, and it enforces nothing.
- The manager cannot resolve merge conflicts, since it edits nothing
  outside `.tasks`: it dispatches a worker to resolve, then commits the
  merge.
- Concurrent per-unit verification is safe because suites run on
  temp-isolated fixtures: each verifier works inside its unit's
  worktree against isolated state, so parallel suites share no
  verdict-relevant mutable state (fixed scratch resources outside
  the repo, like the rules test's `/tmp` output file, do not affect
  verdicts). A suite that violates the assumption (shared paths,
  ports, caches that change outcomes) makes the territories not
  test-disjoint and forces the integration-commit path below.
- A unit's commits are verified against its branch with the siblings'
  edits absent; under disjoint territories this is equivalent to
  verifying them with the siblings' edits present, so the per-task
  verdicts hold without an integration build. When territories are not
  disjoint, verification runs at the integration commit instead, after
  the branches are combined.
- Parking replaces blocking escalation only under the standing-restart
  grant: with the grant recorded in this design, a failed-and-retried
  task waits in Blocked with its failure summary and attempt count
  while the queue continues, and restarts ride backfill and checkpoint
  events within the escalation bounds; without the grant, the
  delegation skill's default (stop, report, ask) stands.
- A rejected push escalates to the user; the manager has no fetch or pull.
- Without task files, a retried worker overwrites its
  `/tmp/opencode/reports/` artifact, the unit name fixing the path;
  under task files each deposit takes the next `NN` sequence number and
  `tasks report` refuses to overwrite an existing file, so the reports
  directory preserves failure history.
- Subagent permission denials do not propagate to the parent or the
  main thread: the denial and any user message attached to it surface
  only inside the subagent's session. The relay rule covers the
  survivable cases; a session-fatal denial cannot be relayed at all,
  an upstream platform gap declined for now.
- Children working in unit worktrees reach the main board by default:
  `.tasks/` is gitignored, so a checkout under `.worktrees/` contains
  no board of its own, but worktrees live inside the repo, and the
  `tasks` CLI's directory walk-up from the child's working directory
  finds the main repo root's `.tasks/`, so logs and reports land on
  the main board. `--dir` (or `TASKS_DIR`) are explicit overrides,
  needed only for working directories outside the repo tree.
- Subagent gating through the `permission.task` key depends on SDK
  support: on some SDK versions (for example 1.18.5) the key may be a
  no-op, so the agents' task permission blocks may not be enforced; the
  prompt prohibitions are the backstop until the running binary confirms
  the key.
