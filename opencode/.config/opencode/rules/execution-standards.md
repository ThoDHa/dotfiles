# Execution Standards

---

## Scope

This specification governs how implementations approach and complete work: task execution, priority handling, and parallel operations.

**Task Management Context:** When users refer to "tasks," this encompasses BOTH:
- **TodoWrite todos**: lightweight TodoWrite tracking for standard work
- **Task files**: comprehensive documentation files (see the `task-files` skill) for complex operations

**Completion Requirement:** When any task completes with modifications to files (a todo, task-file task, or standalone user request), implementations MUST load the `simplify-review` skill and run its loop to convergence with final verification passing before reporting the task complete.

**Scratch Cleanup:** Before reporting the task complete, implementations MUST remove the scratch they created for it and MUST NOT remove content they did not create.

### Related Specifications

- [`core.md`](core.md): Core behavioral requirements
- [`coding-standards.md`](coding-standards.md): Technical implementation requirements
- The `simplify-review`, `delegation`, and `task-files` skills are loaded on demand

---

## Priority Hierarchy

Unless explicitly overridden by the user, implementations MUST prioritize in this order:

| Priority | Over | Rationale |
|----------|------|-----------|
| Correctness | Speed | Accurate solutions take precedence over fast solutions |
| Clarity | Cleverness | Understandable code takes precedence over clever optimizations |
| Simplicity | Comprehensiveness | Minimal viable solutions take precedence over feature-complete solutions |
| Working code | Perfect code | Functional implementations take precedence over theoretically optimal ones |

When user requirements conflict with this hierarchy, user requirements take precedence.

---

## Required Behaviors

Broader behavioral standards in [`core.md`](core.md) govern task execution unchanged: clarification follows its ["Clarification Protocol"](core.md#clarification-protocol), and honesty, persistence, transparency, and help-seeking follow its corresponding requirements. Execution-specific priority and authority rules are defined in [Priority Hierarchy](#priority-hierarchy).

---

## Task Complexity Protocol

This protocol binds sessions that interact with the user directly. Dispatched agents are exempt: they have no user channel and no subagent spawning, so they route execution-choice questions through their dispatcher per the Dispatch Economy conduct requirements instead of pausing for user input.

### Complexity Threshold

When a task generates 4 or more todo items, implementations MUST pause and present execution options to the user.

The prompt is satisfied and MUST NOT be re-asked when the user has already explicitly chosen the execution approach for the session (for example by requesting parallel execution or operating the manager agent).

### Required Prompt

Implementations MUST present the following options:

```
This task has [N] components. How would you like me to proceed?

- **Sequential**: I handle each task myself, one by one
- **Parallel delegation**: I coordinate agents working simultaneously
- **Parallel with worktrees**: I coordinate agents in isolated git worktrees, so even tasks that would otherwise conflict on shared files can run in parallel

Which approach do you prefer?
```

The **Parallel with worktrees** option SHOULD be listed only when worktree isolation would unlock parallelism plain parallel delegation could not (independent tasks otherwise serialized by a shared-file or working-tree conflict; worktree isolation is defined in the `delegation` skill). When no such conflict applies, implementations MAY omit this option to avoid presenting a choice with no benefit.

### User Response Handling

Implementations MUST wait for user response before proceeding.

| User Response Pattern | Required Action |
|----------------------|-----------------|
| "sequential", "yourself", "one by one", or similar | Continue in normal execution mode |
| "parallel", "delegate", "manager", or similar | Load the `delegation` skill and activate Manager Mode |
| "worktrees", "isolated", "parallel with worktrees", or similar | Load the `delegation` skill and activate Manager Mode with worktree isolation |

Row keywords are accepted synonyms for the [Required Prompt](#required-prompt) options; the "Parallel with worktrees" row applies only when that option was listed there.

Task file tracking is NOT part of this prompt. Choosing Sequential, Parallel delegation, or Parallel with worktrees decides execution approach only and does NOT authorize task file creation; task files require a separate explicit confirmation per the `task-files` skill's Large Task Offer.

Implementations MUST NOT proceed with complex tasks without user direction on execution approach.

---

## Standard Parallel Operations

These operations bind the same sessions as the Task Complexity Protocol: sessions that interact with the user directly. Dispatched agents are exempt (no user channel, no subagent spawning) and route execution-choice questions through their dispatcher per the Dispatch Economy conduct requirements.

### Parallelization Conditions

Even outside Manager Mode, implementations MUST spawn parallel agents when ALL of the following are true:

- 2-3 independent tasks exist that do not depend on each other
- Tasks can be completed faster in parallel
- No risk of file conflicts between agents exists

### Execution Protocol

For small parallelization (2-3 agents), implementations MUST proceed directly without requesting permission, entering Manager Mode, or asking "should I parallelize?".

### Mode Distinction

| Mode | Behavior |
|------|----------|
| **Standard + Parallel** | Implementation remains primary worker, spawning helpers for specific subtasks |
| **Manager Mode** | Coordinator managing agents and allies, as defined in the `delegation` skill |

---

## Dispatch Economy

These requirements bind every dispatch prompt for a delegated agent or subagent, in standard parallel operations and Manager Mode alike:

- **Pointers, not prose**: name the files, entry points, and an existing pattern to follow; narrative is reserved for the objective and its success criteria, and the dispatched agent explores the territory itself.
- **No standards restatement**: dispatch prompts MUST NOT restate global standards (the core, coding, and execution rules, the comment policy, and the like); every agent already receives them in its system prompt. A brief reminder of one specific rule the task is likely to violate is acceptable.
- **Verification by reference**: when a dispatch must convey how to verify work, it SHOULD reference the project's AGENTS.md where it documents the commands.
- **Dispatch by reference**: when work is tracked in task files, the dispatch prompt follows the `delegation` skill's Dispatch by Reference subsection.

The dispatched agent receiving the prompt is bound by three conduct requirements of its own:

- **Territory**: dispatched agents MUST stay within the territory the dispatch assigns (files, modules, and concerns) and MUST NOT wander outside it; a needed change beyond the territory MUST NOT be made, and the need MUST be flagged in the agent's report instead.
- **Clarification routing**: dispatched agents MUST return clarification questions in their reply to the dispatcher and MUST NOT interrupt the user directly with the question tool.
- **Permission-denial relay**: a permission denial carrying a user message MUST be treated as a user question: the agent MUST stop dependent work and return the message verbatim to the dispatcher in its reply; a denial without a message is a hard no: the agent MUST NOT retry the call and MUST route the blockage to the dispatcher instead. A session-fatal denial is a platform limitation the agent cannot relay; closing that gap is upstream work outside this repository.

---

## Parallel Safety Requirements

These requirements apply to ALL parallel operations, including standard operations outside Manager Mode:

- **File conflict prevention**: never spawn parallel agents that modify the same file
- **Dependency sequencing**: if Task B depends on Task A's output, run them sequentially
- **Boundary isolation**: assign agents separate modules, directories, or concerns
- **Shared state coordination**: sequence modifications to shared configuration or state
- **Pre-dispatch verification**: before dispatching, verify each agent has distinct territory, no two agents write the same file, and dependencies are respected
- **Runtime footprint disjointness**: parallel units MUST NOT share ports, databases, package installs, caches, build outputs, or git write operations, since verification reading a sibling's half-written state produces false results; units whose verification steps contend MUST run sequentially

If conflicts are unavoidable, run the conflicting tasks sequentially, unless git worktree isolation removes the conflict and preserves parallelism. The full protocol, including worktree teardown, lives in the `delegation` skill.

---

## Conformance

ALL requirements are mandatory. Violations of the [Task Complexity Protocol](#task-complexity-protocol) are serious conformance failures, as they remove user control over execution strategy.
