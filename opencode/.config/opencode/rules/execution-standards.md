# Execution Standards

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## Scope

This specification defines requirements for task execution, priority handling, and parallel operations. These standards govern how implementations approach and complete work.

**Task Management Context:** When users refer to "tasks," this encompasses BOTH:
- **TodoWrite todos**: Lightweight tracking via the TodoWrite tool for standard work
- **Task files**: Comprehensive documentation files (see [`task-files.md`](task-files.md)) for complex operations

### Related Specifications

- [`core.md`](core.md): Core behavioral requirements
- [`delegation.md`](delegation.md): Manager Mode and delegation requirements
- [`coding-standards.md`](coding-standards.md): Technical implementation requirements

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

The **Parallel with worktrees** option SHOULD be listed only when worktree isolation would unlock parallelism that plain parallel delegation could not, that is, when independent tasks would otherwise be serialized by a shared-file or working-tree conflict (see [`delegation.md` Worktree Isolation](delegation.md#worktree-isolation)). When no such conflict applies, implementations MAY omit this option to avoid presenting a choice with no benefit.

### User Response Handling

Implementations MUST wait for user response before proceeding.

| User Response Pattern | Required Action |
|----------------------|-----------------|
| "sequential", "yourself", "one by one", or similar | Continue in normal execution mode |
| "parallel", "delegate", "manager", or similar | Activate Manager Mode (see [`delegation.md`](delegation.md)) |
| "worktrees", "isolated", "parallel with worktrees", or similar | Activate Manager Mode with worktree isolation (see [`delegation.md` Worktree Isolation](delegation.md#worktree-isolation)) |

The keywords in each row are accepted synonyms for the options presented in the [Required Prompt](#required-prompt) prompt ("Sequential", "Parallel delegation", and "Parallel with worktrees"). Any answer matching a row's synonyms maps to that option's action. The "Parallel with worktrees" row applies only when that option was listed per the [Required Prompt](#required-prompt) conditions.

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
| **Manager Mode** | As defined in the ["Manager Mode Definition" section of `delegation.md`](delegation.md#manager-mode-definition) |

---

## Parallel Safety Requirements

The authoritative parallel-safety requirements (file-conflict prevention, dependency sequencing, boundary isolation, and pre-dispatch verification) are defined in the ["Safety Requirements" section of `delegation.md`](delegation.md#safety-requirements). Those requirements apply to ALL parallel operations, including standard parallel operations performed outside Manager Mode.

---

## Conformance

ALL requirements in this specification are mandatory. Any violation of MUST or MUST NOT constitutes an immediate conformance failure.

Violations of the Task Complexity Protocol ([Task Complexity Protocol](#task-complexity-protocol)) are considered serious conformance failures as they remove user control over execution strategy.

---

*This specification defines task execution requirements for all OpenCode implementations.*
