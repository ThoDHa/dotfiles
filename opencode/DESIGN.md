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

When the task-files protocol is active, each unit is a child task file.
Workers append Work Log and Progress Log entries in real time and their
final report verbatim; the manager wraps that entry with the instructions
given and its analysis, performs status transitions, and renders the
dashboard through the `tasks` CLI. Planning may be delegated to a worker,
but the Triage → Ready approval is always the manager's alone. During
execution the plan is frozen: workers may check off acceptance criteria
but never modify planning content; a wrong plan is flagged, not edited.
Small tasks use the lite profile defined in the task-files skill. Without
task files, worker reports go to `/tmp/opencode/reports/` as artifacts.

## Verification chain

Four independent sources are reconciled: worker claims from the reports,
the verifier's raw command results, the reviewer's findings, and git
ground truth (`git diff --stat` and `git log` against the base commit,
covering committed and uncommitted work). The verifier and reviewer are
dispatched in parallel after all units complete: neither edits files,
and only the verifier runs commands, so they cannot contend. The
verifier runs the test suite, linter, and typechecker once each and
reports exit statuses, the runners' own counts, and verbatim failure
output, gating on exit status rather than text matches. The reviewer
verifies logged work against each unit's objective, territory, and the
actual changes, and runs the simplify-review loop without fixing
anything; it executes nothing beyond read-only git. Discrepancies get
one fix-and-re-review cycle, then escalate to the user rather than
being hidden. Worker, verifier, and reviewer failures each retry once,
then stop and ask.

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
verifier holds everything except push, edits, and subagent spawning; the
reviewer holds read-only git only.

Prefix-based bash permissions are guardrails against uninstructed
behavior, not security boundaries: a determined `sh -c` or `git -C` route
slips past them. Hard enforcement would require hooks or credential
separation.

## Known limits

- Soft rules (plan freeze, log discipline, tasks CLI restraint) depend on
  the flash worker's adherence; the reviewer's expectation check is the
  backstop.
- The manager cannot resolve merge conflicts, since it edits nothing
  outside `.tasks`: it dispatches a worker to resolve, then commits the
  merge.
- A rejected push escalates to the user; the manager has no fetch or pull.
- A retried worker overwrites its `/tmp` report; the task-file Work Log
  preserves failure history when task files are active.
