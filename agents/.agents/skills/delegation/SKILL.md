---
name: delegation
description: Manager Mode and delegation protocol covering activation triggers like you are a manager or delegate this, allies versus agents, parallel safety rules, worktree isolation and teardown, resource assessment, and question batching. Use when the user chooses parallel or worktree execution or asks about delegating work to agents.
---

> When Manager Mode work is tracked in task files, also load the `task-files` skill.

# Delegation Protocol

## Manager Mode Definition

Manager Mode is a state where the implementation coordinates work rather than executing directly, acting as a coordinator managing agents and allies. Two modes exist:

1. **Manager Mode (Delegating)**: coordinates and delegates work to agents/allies
2. **Manager Mode (Solo)**: executes work directly while maintaining Manager Mode structure

The mode is determined by the user's answer to the resource assessment question; when no interactive question occurs, a session carrying a recorded standing answer (the opencode manager agent's fixed fleet) has its mode determined by that standing answer. Decision-making, planning, and user consultation follow the same process in both modes; only execution differs. In Delegating mode, implementations MUST delegate using available delegation tools and MUST NOT execute tasks directly except per Direct Execution Exceptions.

## Activation and Deactivation

Activating phrases: "you are a manager", "act as manager", "direct this, don't do it yourself", "delegate this", "there is a big task ahead", or choosing delegation at the Task Complexity Protocol prompt (see the `execution-standards` rule).

Deactivating phrases: "I'm taking over", "do this yourself", "stand down", "back to normal", "work sequentially".

### Resource Assessment

When Manager Mode activates interactively, in a session that interacts with the user directly, implementations MUST ask before beginning delegation:

"How many resources do you have available for this task? Are you working alone, or should I deploy multiple agents?"

This follows, and does not replace, the Sequential/Parallel protocol prompt: a user who already chose parallel delegation is being asked how many agents are available, not whether to delegate at all. Responses map:

| User Response | Mode | Behavior |
|---------------|------|----------|
| "none", "zero", "just me", "I'm alone" | Solo | Manager executes all work directly |
| "1 agent", "limited resources" | Delegating (single) | Delegate to a single agent/ally at a time |
| "multiple", "many", "no limit" | Delegating (parallel) | Coordinate multiple agents/allies |

The opencode manager agent is exempt from this gate: its fleet is fixed (worker, verifier, reviewer, planner via its permission map), which serves as the standing answer to the resource question.

### Manager Mode (Solo)

The manager maintains all Manager Mode requirements (planning, task files, reporting, and the shared decision-making process). Only execution differs: the manager performs work personally, spawns no agents for execution, and tracks own activities, findings, and decisions in the Work Log (see the `task-files` skill).

Solo persists until the user announces resources ("now you have 2 agents"), requests delegation of a part, or deactivates Manager Mode. On transition to Delegating, existing Solo Work Log entries remain intact and future agent work is tracked alongside them.

## Delegation Framework

### Delegation as Default

The manager delegates as much work as its available agents can take: in Manager Mode (Delegating), direct execution is the exception, never a convenience, and manager capability never reduces the delegation duty, since a more capable manager dispatches richer, better-specified work rather than absorbing it. While a delegated worker is available and the work is delegable, implementations MUST dispatch it rather than do it. Implementations MUST delegate: file modifications and code writing, running commands/builds/tests, codebase exploration or analysis, and any task requiring more than 30 seconds. The sole carve-out is an orchestration design in force that allocates architecture duties to the manager directly, and that carve-out MUST be read narrowly: an allocated duty is executed directly only at coordination scale (scouting a dispatch, unblocking a worker, checking a unit's result), and once it grows into sustained work of its own it MUST be delegated. When uncertain whether to execute directly or delegate, implementations MUST delegate.

### Direct Execution Exceptions

The manager MUST execute directly: quick tasks (< 30 seconds), planning and strategic thinking, coordinating between agents, synthesizing reports from multiple agents, communicating with the user, and tactical decisions requiring judgment. This list is exhaustive and MUST be construed narrowly: the manager MUST NOT extend it by analogy or let borderline items accumulate into direct execution. An item qualifies only when dispatching costs more than doing (the quick-task bound) or the work structurally requires the manager (every other item); borderline work defaults to delegation.

**Solo exception**: in Manager Mode (Solo) the manager inverts the rule and MUST execute all tasks directly, including the delegable items above, regardless of duration or complexity, while Solo state persists.

### Planning Approval Authority

Planning labor (exploration, analysis, drafting task documentation, proposing a breakdown) MAY be delegated; planning approval NEVER is. When work is tracked in task files and the planned breakdown fans out into parallel children with overlapping territory, the planning labor MUST satisfy the `task-files` skill's shared-reconnaissance default (deposit the shared reconnaissance artifact under the parent or record the Decision Log exception), defined in that skill's Triage to Ready Planning Phase. The manager MUST be the sole authority that approves a planned task for execution. Implementations MUST NOT allow a delegated agent or ally to declare its own planning complete and move work into execution; when agents performed the planning labor, the manager MUST review the resulting plan, verify it is complete and aligned, and grant approval personally. Delegation does not absolve accountability. When the task is tracked in a task file, this approval is the Triage → Ready transition (see the `task-files` skill).

### Worker Categories

| Type | Characteristics | Appropriate Use |
|------|-----------------|-----------------|
| **Allies** | Independent judgment, specialized skills, full capabilities | Any task of moderate complexity or above: exploration and reconnaissance, architecture review, complex implementation, anything requiring judgment |
| **Agents** | No judgment, simple execution | Trivial bulk operations (renames, identical commands), simple parallel tasks requiring no decisions |

Outside this table, "agent" is used generically for any delegated worker unless the distinction is explicitly in play. Implementations MUST prefer allies over agents; when uncertain, use an ally.

### Dispatched Agent Conduct

Conduct requirements for dispatched agents are canonical in the Dispatch Economy section of the `execution-standards` rule, which every dispatched agent receives in its system prompt.

### Dispatch by Reference

When the work is tracked in task files, the dispatch prompt MAY be a pointer instead of a duplicated payload; the pointer form is sanctioned:

1. **Instructions Given first.** The manager writes the full dispatch instructions verbatim into the target task file's Work Log (the **Instructions Given** field of the dispatch entry, per the `task-files` skill) before making the Task call. That entry is the authoritative instruction record.
2. **Minimal bootstrap frame.** The Task call carries only a bootstrap frame: the agent's role, the task file to read (naming the exact path and the **Instructions Given** entry that is the contract), and the report-back expectation (including the report mechanism when task files are active, per the `task-files` skill).
3. **Mid-flight steering stays in the call.** Any instruction issued while the agent runs goes through the dispatch channel, never only in the file: the agent cannot be assumed to re-read the file mid-flight.
4. **Write once.** The manager MUST NOT restate the entry's instructions in the Task call; the prompt is written once, in the file.

Without task-file tracking, dispatches carry the full prompt as usual.

### Context Continuity

When a unit of work depends on the output of an earlier unit the same agent produced, implementations SHOULD resume that agent's session with the new objective instead of dispatching a fresh one: the context already lives there, and retelling it through the dispatcher wastes tokens. A fresh dispatch is REQUIRED when the dependency crosses agents or when the earlier session's context is poisoned; in that case the dispatch prompt MUST include the earlier unit's report as background the receiving agent MUST verify for itself, never as predetermined outcomes (when task files are active, the report's path under `.tasks/reports/` may serve in place of an inline copy, per the `task-files` skill).

## Safety Requirements

The parallel-safety rules are canonical in the Parallel Safety Requirements section of the `execution-standards` rule and apply to all parallel operations, including standard operations outside Manager Mode. When runtime-footprint disjointness cannot be determined, uncertainty is resolved as sequencing. When conflicts are unavoidable, the fallback defined in that section governs. The worktree protocol lives in the Worktree Isolation and Worktree Teardown sections below.

### Worktree Isolation

Two regimes govern worktree use, set by the orchestration design in force. When that design records the worker-commit model (workers make commit checkpoints on per-unit branches), a worktree under `.worktrees/` on a unit branch is the default dispatch vehicle for a unit dispatched alongside a running sibling and MUST be created before dispatch; a lone unit with no sibling in flight MAY work in the main tree instead. The per-unit branch carries the unit's commits, verification runs against it, and in-flight work survives a lost session, so a sibling-dispatched unit gets its worktree whether or not territories contend. Setups without such a design keep the contention-only reservation: parallel work does NOT default to worktree isolation, the preferred way to parallelize is boundary isolation, and when agents already have distinct territory, worktrees add cost without benefit and MUST NOT be introduced. Under the reservation, worktree isolation is reserved for the case where distinct territory is impossible because the work genuinely contends on the same file or shared working-tree state.

Isolation worktrees MUST be created inside the repository under `.worktrees/` (one directory per isolated task or unit, for example `.worktrees/<unit-name>`), never beside the repository or under `/tmp`: disk-backed and project-local, with no RAM cost. The `.worktrees/` directory MUST be gitignored; implementations MUST verify this with `git check-ignore .worktrees` before the first creation and stop to have the ignore entry added when it is missing, since an un-ignored worktree pollutes status, staging, and tree-walking tools. Worktrees keep a task-scoped lifetime: reconcile and tear down within the task, and clean up stale `.worktrees/` directories from crashed sessions when discovered. Before creating a worktree, implementations MUST run `git worktree prune` so stale registrations self-heal instead of accumulating.

Under the contention-only reservation, implementations SHOULD raise worktree isolation as an option when all of the following hold: two or more independent tasks would otherwise be serialized solely because they touch the same file or shared working-tree state; the work is tracked in git; and the parallelism gained is worth the overhead of creating, reconciling, and later tearing down the worktrees. Worktree isolation MUST NOT be used to bypass dependency sequencing: genuinely dependent tasks still run in order. After isolated work completes, implementations MUST reconcile the separate worktrees (merge or apply the changes back) and resolve any resulting conflicts before integration.

### Worktree Teardown

A worktree created for isolation is temporary scaffolding, not a permanent fixture. After its changes are reconciled, implementations MUST tear it down completely, whether the isolated work succeeded, failed, or was abandoned:

1. Remove the worktree itself (`git worktree remove <path>`), deleting its working directory
2. Prune stale administrative metadata (`git worktree prune`) so no dangling registrations remain
3. Delete any throwaway branch created solely to host the isolated work, once its commits are merged or confirmed unneeded; branches still carrying work in use MUST NOT be deleted
4. Verify no leftover files, directories, or lock state remain

When `git worktree remove` refuses because the worktree holds uncommitted or unreconciled changes, implementations MUST NOT force removal to bypass the safeguard; first reconcile or deliberately discard those changes, then remove. A task that used worktree isolation MUST NOT be considered complete until every worktree it created has been torn down. Under the worker-commit model one deferral is sanctioned: a parked unit (a failed unit awaiting its restart turn per Failure Semantics) keeps its worktree while parked. The teardown obligation is deferred, not lifted: the effort is not complete while a unit is parked, and the parked unit's worktree is torn down when its integration lands or the unit is cancelled.

## Reporting Requirements

Implementations MUST report when: agents are dispatched (summary of work assigned), major phases complete, unexpected obstacles are encountered, decision points are reached (questions needing user input are governed by Question Batching Discipline), and all work is completed.

Users MUST be able to follow work progress in both modes. When dispatching: show what work is assigned. When receiving reports: summarize what agents found or accomplished. When executing directly (Solo): report progress factually and objectively. When making decisions (both modes): explain reasoning before acting, and consult the user before significant decisions. Reporting style MUST be factual and objective, similar to agent reports; users MUST NOT be left wondering what is happening.

When work is tracked in task files, agent reports are recorded per the `task-files` skill's report mechanism: the verbatim report lives in a file under `.tasks/reports/` and the Work Log entry carries the link and the agent's digest. The user-facing summary required above draws on the digest and the manager's analysis rather than re-reading the full report.

Update frequency: short tasks get a summary at completion; long tasks get periodic updates at logical checkpoint events.

### Question Batching Discipline

In Manager Mode (both Delegating and Solo), questions arise from delegated agents, the manager's own decisions, and the work the manager executes directly. The manager MUST handle them so the user is interrupted no more than necessary. This discipline applies to all Manager Mode work, whether or not it is recorded in a task file (when it is, see Question Tracking in the `task-files` skill).

**Classification** by impact:

- **Basic**: answer inferable from context, low-impact, reversible, or covered by established priorities (the `execution-standards` Priority Hierarchy). The manager answers autonomously and proceeds without interrupting the user.
- **Significant**: ambiguous requirement, irreversible or high-impact choice, cross-cutting tradeoff, or genuine uncertainty (the `core` rule's Clarification and Uncertainty Protocols). The manager defers the question and continues all unblocked work.

The manager MUST NOT fabricate an answer to a Significant question to avoid interrupting the user. When uncertain how to classify, treat the question as Significant.

**Escalation.** Surface deferred Significant questions when any occurs:

- **Hard block**: the question now gates all remaining unblocked work; ask immediately
- **Checkpoint event**: a phase or batch of parallel work completes, or no unblocked work remains
- **High rework risk**: continuing under a wrong assumption would waste substantial work, so escalate early
- **User status request**: the user asks for status; include the open questions

**Whole-batch interruption.** Because the user is interrupted in all escalation cases, the manager MUST present every then-pending Significant question in the same batch, not only the triggering one.

**Independent questions only.** Batching is permitted ONLY for mutually independent questions. When one question's framing depends on another's answer, sequence them (ask the first, re-derive the second) rather than merging dependent questions into a malformed batch.

## Override and Takeover

### User Override Protocol

When users indicate they want direct control: transfer command (agents report directly to the user), join execution (shift from delegating to executing), let agents in progress complete and report, and remain available ("resume managing" restores delegation). Override is a command structure change, not task abortion.

### Failure Semantics

When a delegated agent fails to complete its task, it gets exactly one retry. When the retry also fails:

- Implementations that can execute directly (standard implementations, managers in Solo mode) MUST take over, complete the task themselves, analyze why the failures occurred, and notify the user of the takeover.
- Pure coordinators that cannot execute directly (for example, agents whose edit permissions deny implementation) MUST stop, report what was attempted and why it failed, and ask the user how to proceed.

**Standing restart grant.** When the user has granted standing restart authorization, recorded in the orchestration design in force, a pure coordinator parks the failed task instead of stopping the whole effort: the task carries a Blocked status whose reason states the failure summary and the attempt count, reported to the user without blocking the remaining work, and the coordinator re-dispatches it per the design's checkpoint-event rule (restart consideration rides backfill and checkpoint events, oldest-cleared-first, never into an unchanged blocking condition, restart-eligible only after the design's backoff interval has elapsed since the task's last dispatch attempt, with hard escalation per the manager agent file's escalation bounds). The stop-report-ask path above remains the default whenever no such grant is recorded.

The design's backoff interval is measured on wall-clock time taken from the board's own timestamps: the tasks CLI stamps task file headers (Updated) and Work Log entries with real times, and the coordinator reads the current time by refreshing a header through the CLI and reading it back, never from a shell clock.

No failure is hidden or minimized, under either mode. Without a standing restart grant, no failure gets a third attempt; under a recorded grant, re-dispatches of a parked task follow the design's checkpoint-event rule within its escalation bounds. Implementations remain ultimately responsible.

## Conformance

All requirements are mandatory. Executing directly when delegation is required (outside Direct Execution Exceptions, outside Solo mode, and outside the Delegation as Default architecture carve-out for duties the orchestration design in force allocates to the manager directly), failing to report progress, operating Solo without maintaining Manager Mode requirements, or altering the decision-making process in Solo mode are conformance failures.
