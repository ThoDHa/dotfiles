# OpenCode Orchestration Design

This note documents the manager, worker, verifier, reviewer, and planner
agent pipeline, the git authority model, the task-file integration, and the
verification chain. The agent files under the opencode config carry the
normative requirements in RFC 2119 form; this note explains the architecture
and the reasoning, pointing at each requirement's canonical home (file plus
section heading or rule number).

## Roles

| Agent | Mode | Model | Duties |
|-------|------|-------|--------|
| manager | primary | session | Decomposition, dispatch, unit worktrees and branches, planning approval, architecture duties at coordination scale (exploration, builds, verification runs, CI/CD operation), integration and history shaping, pushes, reconciliation |
| worker | subagent | glm-5.3-flash | Code writing: implementation inside an assigned territory, commit checkpoints on the unit branch, real-time work logs, reports |
| verifier | subagent | glm-5.3-flash | Runs tests, linter, and typechecker once each, reports raw results without interpretation |
| reviewer | subagent | session | simplify-review in Analysis-Only Mode, advisory plan critiques between drafting and approval, expectation checks, no command execution beyond read-only git |
| planner | subagent | session | Planning and research labor: dedicated research dispatches (territory reconnaissance, codebase investigation, findings reports through the `tasks report` channel), drafting the Triage task file's planning sections ahead of the manager's Triage → Ready approval, shared recon deposits, no implementation |

The manager is a coordinator, not an implementer: it holds no implementation
duty (it never authors implementation content), and its file edits are
limited to `.tasks/**`. Integration commits and pushing are coordination
duties, not implementation work; unit workers make their own commit
checkpoints on the branches the manager assigned them. The division of
labor between the two dispatch targets is explicit: the worker is the
code-writing agent, and the planner is the destination for research
and planning dispatches (planning labor, dedicated exploration,
investigation, and findings reports), so research-grade context
building concentrates in one session-model agent instead of eroding
the flash worker's focus. The architect grant
follows the same line: the manager delegates as much work as the fleet can
take, and the command freedom exists to unblock and steer the fleet
(scouting a dispatch, unblocking a worker, checking a unit's result); any
duty that grows into sustained work of its own is dispatched to a fleet
agent rather than absorbed (research-grade exploration to the planner,
code writing to the worker), since capability never reduces the delegation
duty.

The verifier and reviewer split verification along the judgment line:
transcription of command results is mechanical and runs on the flash model,
while code review and result interpretation need the full model. The
verifier reports exit statuses, the runner's own counts, and verbatim
failure output; interpretation happens in the manager's reconciliation,
never inside the verifier.

## Git authority

Under the worker-commit model recorded here, a unit dispatched alongside a
running sibling works in a worktree under `.worktrees/` on its own unit
branch (a lone unit may use the main tree), and the worker makes
territory-scoped commit checkpoints there, every commit a complete logical
change leaving the suite green; per-unit attribution and crash resilience
are the payoffs, and the commit rules are normative in the worker agent
file's commits paragraph and the delegation skill's Worktree Isolation
section. Integration, history shaping, staging, and pushing are the
manager's alone, keeping the main line coherent while units run in parallel:
it shapes a passed unit's branch judgment-based (squash or merge the commit
checkpoints as the change warrants), stages only the files that worker
changed, and reshapes pushed history only on explicit user request; rule 4
of the manager agent file is normative for the worktree default and the
pre-dispatch tree and base-commit checks, and its closing git-authority
section for staging, history shaping, and push rules.

## Task-file integration

Under the task-files protocol every `.tasks/` write has exactly one owner:
the manager owns the task files and the dashboard, dispatched agents own the
two `tasks` CLI channels (Work Log entries and report deposits, attributed
via `--from`), and the planner's planning-section carve-out is the single
exception (the task-files skill's Agent Write Path and Serialized Task-File
Body Edits sections). Bulky output lives under `.tasks/reports/` (the
skill's Reports Namespace and Manual Fallback sections); closure work opens
with a short digest and planning fan-out shares one reconnaissance artifact
(the skill's Closure Digest and Triage to Ready Planning Phase sections, the
latter tied to the delegation skill's Planning Approval Authority).
High-cost plans (parallel fan-out, checkpoint slicing with a contract seam,
user-flagged stakes) pass an advisory plan-review gate whose verdict never
binds (rule 2 of the manager agent file; the reviewer agent file's
plan-review dispatch type); small tasks use the skill's Documentation Scale:
Lite Profile.

## Dispatch economy

The dispatch economy requirements and the dispatched-agent conduct rules
(territory, clarification routing, permission-denial relay) are normative in
the execution-standards rule's Dispatch Economy section, and the delegation
skill's Dispatch by Reference section sanctions the pointer-form dispatch
through a task file's Instructions Given entry.

Dependent units resume the earlier worker's session (the delegation skill's
Context Continuity section, extended batch-wide by rule 5 of the manager
agent file): every fresh dispatch re-pays the prior session's exploration,
file reads, and skill loads. Two exclusions stand: the reviewer is never
resumed across units (accumulated verdicts erode its independence), and the
verifier stays stateless by design; the session-fatal denial case sits under
known limits.

## Verification chain

Verification runs as a per-unit pipeline, not in batch: when a unit's worker
returns, its verifier and reviewer are dispatched in parallel and four
independent sources are reconciled per unit (worker claims, verifier
results, reviewer findings, git ground truth). The verifier reports raw
results without interpretation, the reviewer runs the simplify-review loop
in Analysis-Only Mode and nothing beyond read-only git (normative in rule 7
of the manager agent file and the verifier and reviewer agent files). On a
pass the manager backfills the freed slot immediately and gives every
discrepancy, finding, and suggestion exactly one recorded disposition (fix,
defer, or decline), because unbounded loops hide failures and unactioned
suggestions get lost (rules 7 through 9 of the manager agent file; one
combined seam review closes the batch).

Failure handling parks instead of blocking: on the failure of the single
mandated retry, the task is parked with a Blocked status whose reason
carries the failure summary and the attempt count, reported to the user
without blocking the queue, and parked tasks are reconsidered at every
backfill or checkpoint event. Rule 6 of the manager agent file is normative
for the escalation bounds, and the backoff measurement procedure lives in
the delegation skill's Failure Semantics section. This design is the
recording that section's standing-restart grant clause requires: the user's
standing-restart grant is recorded here and takes effect on this task's
sign-off, putting parking and the checkpoint-event rule in force for this
orchestration from that point.

## Worktree isolation

Under the worker-commit model recorded here, a worktree under `.worktrees/`
on a unit branch is the default dispatch vehicle for a unit with a running
sibling (a lone unit works in the main tree; a parked unit's worktree is the
one teardown exception); this recording switches the delegation skill's
worktree regime, whose mechanics are normative in its Worktree Isolation and
Worktree Teardown sections.

## Permissions posture

Agent permission tiers mirror their prompts, defined in each agent file's
frontmatter and the global opencode.json; config and agent files load at
session start, so permission edits take effect only in newly started
sessions. The manager's edit denial is the single architectural line,
confining its edits to `.tasks/**` while bash stays open; the worker holds
everything except push, history reshaping, gh writes, and subagent spawning;
the verifier's bash is intentionally open so it can run tests; the reviewer
holds read-only git only; the planner pairs read-only git with the two
`tasks` CLI channels and an edit map opening only `.tasks/**`, the
channels its research role runs on, so the prompt-level routing added
no permission changes. Prefix-based bash permissions are
guardrails against uninstructed behavior, not security boundaries: a
determined `sh -c` or `git -C` route slips past them, and hard
enforcement would require hooks or credential separation.

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
  is its backstop. The no-implementation and territory-scoping
  restraints on research dispatches routed to the same planner are
  likewise prompt-soft, and the manager's review of the findings is
  their backstop. The plan-review gate on high-cost plans is advisory
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
