# Execution Standards

---

## Scope

This specification defines requirements for task execution, priority handling, and parallel operations. These standards govern how implementations approach and complete work.

**Task Management Context:** When users refer to "tasks," this encompasses BOTH:
- **TodoWrite todos**: Lightweight tracking via the TodoWrite tool for standard work
- **Task files**: Comprehensive documentation files (see the `task-files` skill) for complex operations

**Completion Requirement:** When any task completes with modifications to files (a todo, a task-file task, or a standalone user request), implementations MUST load the `simplify-review` skill and run its loop to convergence with final verification passing before reporting the task complete.

### Related Specifications

- [`core.md`](core.md): Core behavioral requirements
- [`coding-standards.md`](coding-standards.md): Technical implementation requirements
- The Simplify and Review Loop lives in the `simplify-review` skill; Manager Mode and task-file protocols live in the `delegation` and `task-files` skills, loaded on demand

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

Broader behavioral standards are defined authoritatively in [`core.md`](core.md): clarification follows its ["Clarification Protocol"](core.md#clarification-protocol), and honesty, persistence, transparency, and help-seeking follow its corresponding requirements. The execution-specific rows below govern priority and authority during task execution.

Implementations MUST maintain these behavioral standards:

| Required Behavior | Rationale |
|------------------|-----------|
| Let results demonstrate competence | Results speak without requiring claims |
| Respect user authority over decisions | User input guides all final choices |

---

## Task Complexity Protocol

### Complexity Threshold

When a task generates 4 or more todo items, implementations MUST pause and present execution options to the user.

### Required Prompt

Implementations MUST present the following options:

```
This task has [N] components. How would you like me to proceed?

- **Sequential**: I handle each task myself, one by one
- **Parallel delegation**: I coordinate agents working simultaneously
- **Parallel with worktrees**: I coordinate agents in isolated git worktrees, so even tasks that would otherwise conflict on shared files can run in parallel

Which approach do you prefer?
```

The **Parallel with worktrees** option SHOULD be listed only when worktree isolation would unlock parallelism that plain parallel delegation could not, that is, when independent tasks would otherwise be serialized by a shared-file or working-tree conflict (worktree isolation is defined in the `delegation` skill). When no such conflict applies, implementations MAY omit this option to avoid presenting a choice with no benefit.

### User Response Handling

Implementations MUST wait for user response before proceeding.

| User Response Pattern | Required Action |
|----------------------|-----------------|
| "sequential", "yourself", "one by one", or similar | Continue in normal execution mode |
| "parallel", "delegate", "manager", or similar | Load the `delegation` skill and activate Manager Mode |
| "worktrees", "isolated", "parallel with worktrees", or similar | Load the `delegation` skill and activate Manager Mode with worktree isolation |

The keywords in each row are accepted synonyms for the options presented in the [Required Prompt](#required-prompt) prompt. The "Parallel with worktrees" row applies only when that option was listed per the [Required Prompt](#required-prompt) conditions.

Implementations MUST NOT proceed with complex tasks without user direction on execution approach.

---

## Standard Parallel Operations

### Parallelization Conditions

Even outside Manager Mode, implementations MUST spawn parallel agents when ALL of the following are true:

- 2-3 independent tasks exist that do not depend on each other
- Tasks can be completed faster in parallel
- No risk of file conflicts between agents exists

### Execution Protocol

For small parallelization (2-3 agents), implementations MUST proceed directly without:

- Requesting permission
- Entering Manager Mode
- Asking "should I parallelize?"

### Mode Distinction

| Mode | Behavior |
|------|----------|
| **Standard + Parallel** | Implementation remains primary worker, spawning helpers for specific subtasks |
| **Manager Mode** | Coordinator managing agents and allies, as defined in the `delegation` skill |

---

## Parallel Safety Requirements

These requirements apply to ALL parallel operations, including standard parallel operations performed outside Manager Mode:

- **File conflict prevention**: never spawn parallel agents that modify the same file
- **Dependency sequencing**: if Task B depends on Task A's output, run them sequentially
- **Boundary isolation**: assign agents separate modules, directories, or concerns
- **Shared state coordination**: sequence modifications to shared configuration or state
- **Pre-dispatch verification**: before dispatching, verify each agent has distinct territory, no two agents write the same file, and dependencies are respected

If conflicts are unavoidable, run the conflicting tasks sequentially, unless git worktree isolation removes the conflict and preserves parallelism. The full protocol, including worktree teardown, lives in the `delegation` skill.

---

## Conformance

ALL requirements are mandatory. Violations of the [Task Complexity Protocol](#task-complexity-protocol) are serious conformance failures, as they remove user control over execution strategy.
