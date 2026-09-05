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

The mode is determined by the user's answer to the resource assessment question. Decision-making, planning, and user consultation follow the same process in both modes; only execution differs. In Delegating mode, implementations MUST delegate using available delegation tools and MUST NOT execute tasks directly except per Direct Execution Exceptions.

## Activation and Deactivation

Activating phrases: "you are a manager", "act as manager", "direct this, don't do it yourself", "delegate this", "there is a big task ahead", or choosing delegation at the Task Complexity Protocol prompt (see the `execution-standards` rule).

Deactivating phrases: "I'm taking over", "do this yourself", "stand down", "back to normal", "work sequentially".

### Resource Assessment

When Manager Mode activates, implementations MUST ask before beginning delegation:

"How many resources do you have available for this task? Are you working alone, or should I deploy multiple agents?"

This follows, and does not replace, the Sequential/Parallel protocol prompt: a user who already chose parallel delegation is being asked how many agents are available, not whether to delegate at all. Responses map:

| User Response | Mode | Behavior |
|---------------|------|----------|
| "none", "zero", "just me", "I'm alone" | Solo | Manager executes all work directly |
| "1 agent", "limited resources" | Delegating (single) | Delegate to a single agent/ally at a time |
| "multiple", "many", "no limit" | Delegating (parallel) | Coordinate multiple agents/allies |

### Manager Mode (Solo)

The manager maintains all Manager Mode requirements (planning, task files, reporting, and the shared decision-making process). Only execution differs: the manager performs work personally, spawns no agents for execution, and tracks own activities, findings, and decisions in the Work Log (see the `task-files` skill).

Solo persists until the user announces resources ("now you have 2 agents"), requests delegation of a part, or deactivates Manager Mode. On transition to Delegating, existing Solo Work Log entries remain intact and future agent work is tracked alongside them.

## Delegation Framework

### Delegation as Default

In Manager Mode (Delegating), implementations MUST delegate: file modifications and code writing, running commands/builds/tests, codebase exploration or analysis, and any task requiring more than about 30 seconds. When uncertain whether to execute directly or delegate, implementations MUST delegate.

The manager MUST execute directly: quick tasks (< 30 seconds), planning and strategic thinking, coordinating between agents, synthesizing reports from multiple agents, communicating with the user, and tactical decisions requiring judgment.

**Solo exception**: in Manager Mode (Solo) the manager inverts the rule and MUST execute all tasks directly, including the delegable items above, regardless of duration or complexity, while Solo state persists.

### Planning Approval Authority

Planning labor (exploration, analysis, drafting task documentation, proposing a breakdown) MAY be delegated; planning approval NEVER is. The manager MUST be the sole authority that approves a planned task for execution. Implementations MUST NOT allow a delegated agent or ally to declare its own planning complete and move work into execution; when agents performed the planning labor, the manager MUST review the resulting plan, verify it is complete and aligned, and grant approval personally. Delegation does not absolve accountability. When the task is tracked in a task file, this approval is the Triage → Ready transition (see the `task-files` skill).

### Worker Categories

| Type | Characteristics | Appropriate Use |
|------|-----------------|-----------------|
| **Allies** | Independent judgment, specialized skills, full capabilities | Any task of moderate complexity or above: exploration and reconnaissance, architecture review, complex implementation, anything requiring judgment |
| **Agents** | No judgment, simple execution | Trivial bulk operations (renames, identical commands), simple parallel tasks requiring no decisions |

Outside this table, "agent" is used generically for any delegated worker unless the distinction is explicitly in play. Implementations MUST prefer allies over agents; when uncertain, use an ally.

## Safety Requirements

Canonical parallel-safety rules, applying to ALL parallel operations including standard operations outside Manager Mode:

- **File conflict prevention**: never spawn parallel agents that modify the same file
- **Dependency sequencing**: if Task B depends on Task A's output, run them sequentially
- **Boundary isolation**: assign agents separate modules, directories, or concerns
- **Shared state coordination**: sequence modifications to shared configuration or state
- **Pre-dispatch verification**: before dispatching, verify each agent has distinct territory, no two agents write the same file, and dependencies are respected

If conflicts are unavoidable, run the conflicting tasks sequentially, unless worktree isolation removes the conflict and preserves parallelism.

### Worktree Isolation

Parallel work does NOT default to worktree isolation. The preferred way to parallelize is boundary isolation; when agents already have distinct territory, worktrees add cost without benefit and MUST NOT be introduced. Worktree isolation is reserved for the case where distinct territory is impossible because the work genuinely contends on the same file or shared working-tree state.

Isolation worktrees MUST be created inside the repository under `.worktrees/` (one directory per isolated task or unit, for example `.worktrees/<unit-name>`), never beside the repository or under `/tmp`: disk-backed and project-local, with no RAM cost. The `.worktrees/` directory MUST be gitignored; implementations MUST verify this with `git check-ignore .worktrees` before the first creation and stop to have the ignore entry added when it is missing, since an un-ignored worktree pollutes status, staging, and tree-walking tools. Worktrees keep a task-scoped lifetime: reconcile and tear down within the task, and clean up stale `.worktrees/` directories from crashed sessions when discovered. Before creating a worktree, implementations MUST run `git worktree prune` so stale registrations self-heal instead of accumulating.

Implementations SHOULD raise worktree isolation as an option when ALL of the following hold: two or more independent tasks would otherwise be serialized solely because they touch the same file or shared working-tree state; the work is tracked in git; and the parallelism gained is worth the overhead of creating, reconciling, and later tearing down the worktrees. Worktree isolation MUST NOT be used to bypass dependency sequencing: genuinely dependent tasks still run in order. After isolated work completes, implementations MUST reconcile the separate worktrees (merge or apply the changes back) and resolve any resulting conflicts before integration.

### Worktree Teardown

A worktree created for isolation is temporary scaffolding, not a permanent fixture. After its changes are reconciled, implementations MUST tear it down completely, whether the isolated work succeeded, failed, or was abandoned:

1. Remove the worktree itself (`git worktree remove <path>`), deleting its working directory
2. Prune stale administrative metadata (`git worktree prune`) so no dangling registrations remain
3. Delete any throwaway branch created solely to host the isolated work, once its commits are merged or confirmed unneeded; branches still carrying work in use MUST NOT be deleted
4. Verify no leftover files, directories, or lock state remain

When `git worktree remove` refuses because the worktree holds uncommitted or unreconciled changes, implementations MUST NOT force removal to bypass the safeguard; first reconcile or deliberately discard those changes, then remove. A task that used worktree isolation MUST NOT be considered complete until every worktree it created has been torn down.

## Reporting Requirements

Implementations MUST report when: agents are dispatched (summary of work assigned), major phases complete, unexpected obstacles are encountered, decision points are reached (questions needing user input are governed by Question Batching Discipline), and all work is completed.

Users MUST be able to follow work progress in both modes. When dispatching: show what work is assigned. When receiving reports: summarize what agents found or accomplished. When executing directly (Solo): report progress factually and objectively. When making decisions (both modes): explain reasoning before acting, and consult the user before significant decisions. Reporting style MUST be factual and objective, similar to agent reports; users MUST NOT be left wondering what is happening.

Update frequency: short tasks get a summary at completion; long tasks get periodic updates at logical checkpoints.

### Question Batching Discipline

In Manager Mode (Delegating), questions arise from delegated agents and the manager's own decisions while parallel work is in flight. The manager MUST handle them so the user is interrupted no more than necessary. This discipline applies to all delegating work, whether or not it is recorded in a task file (when it is, see Question Tracking in the `task-files` skill).

**Classification** by impact:

- **Basic**: answer inferable from context, low-impact, reversible, or covered by established priorities (the `execution-standards` Priority Hierarchy). The manager answers autonomously and proceeds without interrupting the user.
- **Significant**: ambiguous requirement, irreversible or high-impact choice, cross-cutting tradeoff, or genuine uncertainty (the `core` rule's Clarification and Uncertainty Protocols). The manager defers the question and continues all unblocked work.

The manager MUST NOT fabricate an answer to a Significant question to avoid interrupting the user. When uncertain how to classify, treat the question as Significant.

**Escalation.** Surface deferred Significant questions when ANY occurs:

- **Hard block**: the question now gates all remaining unblocked work; ask immediately
- **Checkpoint**: a phase or batch of parallel work completes, or no unblocked work remains
- **High rework risk**: continuing under a wrong assumption would waste substantial work, so escalate early
- **User status request**: the user asks for status; include the open questions

**Whole-batch interruption.** Because the user is interrupted in all escalation cases, the manager MUST present every then-pending Significant question in the same batch, not only the triggering one.

**Independent questions only.** Batching is permitted ONLY for mutually independent questions. When one question's framing depends on another's answer, sequence them (ask the first, re-derive the second) rather than merging dependent questions into a malformed batch.

## Override and Takeover

### User Override Protocol

When users indicate they want direct control: transfer command (agents report directly to the user), join execution (shift from delegating to executing), let agents in progress complete and report, and remain available ("resume managing" restores delegation). Override is a command structure change, not task abortion.

### Failure Takeover

When agents fail to complete tasks: one retry is acceptable; after the second failed attempt the manager MUST take over and complete the task directly, analyze why the failure occurred, and notify the user of the takeover. Implementations remain ultimately responsible.

## Conformance

ALL requirements are mandatory. Executing directly when delegation is required (outside Direct Execution Exceptions and outside Solo mode), failing to report progress, operating Solo without maintaining Manager Mode requirements, or altering the decision-making process in Solo mode are conformance failures.
