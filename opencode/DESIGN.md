# OpenCode Orchestration Design

This note documents the manager, worker, verifier, and reviewer agent
pipeline, the git authority model, and the task-file integration. The
agent files under the opencode config carry the normative requirements
in RFC 2119 form; this note explains the architecture and the reasoning
behind them.

## Roles

| Agent | Mode | Model | Duties |
|-------|------|-------|--------|
| manager | primary | session | Decomposition, dispatch, planning approval, commits, pushes, reconciliation |
| worker | subagent | glm-5.3-flash | Implementation inside an assigned territory, real-time work logs, reports |
| verifier | subagent | glm-5.3-flash | Runs tests, linter, and typechecker once each, reports raw results without interpretation |
| reviewer | subagent | session | simplify-review in analysis-only mode, expectation checks, no command execution beyond read-only git |

The manager is a pure coordinator: it holds no implementation duty, and its
file edits are limited to `.tasks/**`. Committing and pushing are
coordination duties, not implementation work.

The verifier and reviewer split verification along the judgment line:
transcription of command results is mechanical and runs on the flash
model, while code review and result interpretation need the full model.
The verifier reports exit statuses, the runner's own counts, and
verbatim failure output; interpretation happens in the manager's
reconciliation, never inside the verifier.

## Git authority

Workers never push, in any form: the `git push*` permission is denied and
the prompt prohibition covers force variants, aliases, and `sh -c` routes.
Workers commit only when a dispatch explicitly instructs it; the default is
to return uncommitted work.

The manager owns history. It decides what gets committed and how it is
grouped, possibly combining several workers' output into one logical
commit, and stages only the files workers changed, never sweeping
pre-existing changes. Before the first dispatch it confirms a clean tree
with `git status` and records the base commit with `git rev-parse HEAD`.

Amend and force-push variants are ask-gated everywhere. The manager
pushes on its own judgment once a unit is complete and verified, the
verifier's results are clean, and the reviewer passes the combined
result, without waiting to be asked, and pushes whenever the user
asked; it never pushes half-finished or unverified work and never
when the user forbade it.

## Task-file integration

When the task-files protocol is active, each unit is a child task file,
and every `.tasks/` write has exactly one owner. The manager owns the
task files themselves: header fields, acceptance-criteria checkboxes,
status transitions, and the dashboard, rendered through the `tasks`
CLI. Dispatched workers own exactly two channels, both inside that CLI
and both attributed to them via `--from`, per the task-files skill's
Agent Write Path: interim progress as appended Work Log entries, and
the final report as a verbatim deposit under `.tasks/reports/` whose
Work Log entry carries the agent-supplied digest and a relative link.
The manager never restates
report bodies: its dispatch entry records the instructions given,
written before the call, and its analysis is an independent check on
the digest, not a retelling. A worker that finds the plan wrong flags
that in its report instead of editing the file. The single carve-out is
the planning-mode exception: a worker dispatched to plan a Triage task
may edit exactly the planning sections of that named file (Objective,
Success Criteria, Technical Approach, Risk Assessment, Testing
Strategy, Task Breakdown, Decision Log), while header fields,
checkboxes, Progress, status, and the dashboard stay manager-owned, and
no status transition, Triage → Ready included, belongs to the planning
worker.

The reports mechanism keeps bulky output out of the task files, per the
task-files skill's Reports Namespace: one directory per task file under
`.tasks/reports/`, keyed by the file's full basename including `.md`,
holding deposits named `NN-<slug>.md`. `NN` is a zero-padded sequence
number assigned in deposit order, one past the highest already on disk,
so numbers are never reused even when gaps appear. Because `current/`,
`archive/`, and `reports/` are siblings, the `../reports/...` relative
link in a task file resolves identically from both directories, so
archiving moves the task file alone and reports never move. `tasks
log`, `tasks report`, and the dashboard render they trigger each hold
the exclusive `flock` on `.tasks/.lock` for their read-modify-write
span, a process-held lock released on exit, so concurrent sessions
serialize instead of racing. `tasks show <taskfile> --tail N` prints
the header fields, the Latest Update pointer, and the last N Work Log
entries without taking the lock: the delta read for catching up on a
task. Until the subcommands exist in an environment, the manual
fallback preserves the same contract by hand: the worker writes the
next report file at the canonical path without overwriting and returns
path and digest to the manager, who makes the entry and header writes
(the task-files skill's Manual Fallback). Without task files at all,
worker reports go to `/tmp/opencode/reports/<unit-name>.md` as
artifacts.

Every completed task's Final Summary opens with a closure digest, at
most five lines naming the outcome, the key decisions, and links into
the details (report deposit paths, the Decision Log), sized
proportionally to the task; the normative text is the task-files
skill's Closure Digest section. When planning fans the work out into
parallel children with overlapping territory, a shared reconnaissance
artifact is the default: the parent deposits a `01-recon` report via
`tasks report --slug recon`, and each child references it from its
Files to Review, so exploration happens once instead of once per
child; skipping it requires a Decision Log exception naming the reason
(a single child, territory already mapped, or the unknown-contract
case where a walking skeleton precedes fan-out). The normative text is
the task-files skill's Triage to Ready Planning Phase, tied to the
manager's approval review by the delegation skill's Planning Approval
Authority. Small tasks use the lite profile defined in the task-files
skill.

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
in the worker and reports are not retold through the manager; fresh
dispatches with the report as background remain for cross-worker
dependencies and poisoned contexts.

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

Four independent sources are reconciled: worker claims from the reports,
the verifier's raw command results, the reviewer's findings, and git
ground truth (`git diff --stat` and `git log` against the base commit,
covering committed and uncommitted work). The verifier and reviewer are
dispatched in parallel after all units complete: neither edits files,
and only the verifier runs non-git commands, so they cannot contend.
The verifier always runs; the reviewer is skipped only when every unit
was mechanical (dependency bump, rename, formatting,
documentation-only). The reviewer does not re-report simplifications
the worker's own simplify-review run already records as addressed,
only findings that remain. The
verifier runs the test suite, linter, and typechecker once each and
reports exit statuses, the runners' own counts, and verbatim failure
output, gating on exit status rather than text matches. The reviewer
verifies logged work against each unit's objective, territory, and the
actual changes, and runs the simplify-review loop (simplify pass
first, then review pass) without fixing anything; it executes nothing
beyond read-only git. Discrepancies get
one fix-and-re-review cycle, then escalate to the user rather than
being hidden. Reviewer suggestions each get one disposition: small
ones (mechanical, contained in the unit's changed files) are done
now by a worker and re-verified once, big ones and any scope creep
are deferred to their own new task as maybe-later work and proposed
as the next one, and only suggestions that do not serve the user's
intent may be declined, with a recorded reason. Every disposition is
recorded (Decision Log
under task files, the completion report otherwise), and undecided or
unactioned suggestions are restated verbatim to the user when work
stops; without task files the report is the only durable record.
Worker, verifier, and reviewer failures follow the delegation skill's
failure semantics; the manager always takes the coordinator path
(stop, report, ask), since it cannot execute directly.

## Worktree isolation

Reserved for same-file contention that would otherwise serialize
independent work. Worktrees live inside the repo under `.worktrees/`
(disk-backed, no RAM cost), verified gitignored via `git check-ignore`
before first creation, pruned (`git worktree prune`) before creation, and
torn down completely after reconciliation: worktree removed, metadata
pruned, throwaway branch deleted.

## Permissions posture

The global config allows `/tmp/**` for external-directory access and
auto-approves `doom_loop` so unattended runs cannot halt on repeated
identical tool calls. Agent permission tiers mirror their prompts: the
manager holds read-only git plus add, commit, worktree, merge, branch, and
push, plus read-only gh (view, list, diff, checks, status, search; gh api
excluded because patterns cannot gate its HTTP method); the worker holds
everything except push, gh writes (same read-only gh set), and subagent
spawning; the
verifier's bash is intentionally open so it can run tests, gated only
against push, and its edit tool and subagent spawning are denied; the
reviewer holds read-only git only.

Recurring benign commands are pre-allowed so unattended runs do not
stall on permission prompts: worker, manager, and verifier allow `make
test*`, the repo's `test` and `test-*` targets (the reviewer is
deliberately excluded, since its charter bars running tests), and the
worker additionally allows `mktemp` with templates under
`/tmp/opencode/*`, the invocation forms observed in its workflow.
Config and agent files load once at
session start, so permission edits take effect in newly started
sessions; running sessions keep the maps they already loaded.

Prefix-based bash permissions are guardrails against uninstructed
behavior, not security boundaries: a determined `sh -c` or `git -C` route
slips past them. Hard enforcement would require hooks or credential
separation.

## Known limits

- Soft rules (plan freeze, log discipline, tasks CLI restraint) depend on
  the flash worker's adherence; the reviewer's expectation check is the
  backstop, except on all-mechanical tasks where the reviewer is skipped
  and the verifier's raw results plus git reconciliation are the only
  checks.
- The manager cannot resolve merge conflicts, since it edits nothing
  outside `.tasks`: it dispatches a worker to resolve, then commits the
  merge.
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
- Worktree-isolated children reach the main board by default:
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
