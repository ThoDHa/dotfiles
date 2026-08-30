---
name: task-files
description: Task file protocol covering the .tasks directory, dashboard board, task IDs, child task files, checkpoint slicing, and the tasks CLI. Use when the user requests task files, a task board or dashboard, in-depth documentation of work such as full reports, activates Manager Mode, or mentions dashboard.md or .tasks.
---

> Manager Mode mechanics are defined in the `delegation` skill. Load it when Manager Mode activates.

# Task File Protocol

## Scope

This specification defines requirements for creating and managing task files during complex operations: comprehensive documentation of work performed, decisions made, knowledge gained, bugs encountered, and progress tracking, in both Manager Mode (Delegating) and Manager Mode (Solo).

### Tone and Voice Policy

- All sections MUST use professional, formal tone with no character voice, per the `core` rule's Formal Output Standards.
- Exception: the Agent Report entry in the Work Log template ([Task File Template](#task-file-template)) records agent output verbatim, regardless of tone.
- Every other section MUST remain formal.

---

## Creation Rules

### Creation Triggers

Task files MUST be created ONLY when:

- User explicitly requests task file creation or planning documentation
- User requests in-depth documentation of work performed, findings, or decisions (e.g., "full report", "document your findings", "write up what you found")
- User explicitly activates Manager Mode
- User explicitly confirms delegation at the 4+ todo item threshold

Casual summary requests ("summarize", "quick recap") do NOT trigger task file creation.

### Creation Prohibition

Task files MUST NOT be created proactively without user request. Standard todo tracking via TodoWrite is sufficient for most operations.

---

## Directory Structure

### Required Structure

```
Project Root/
└── .tasks/
    ├── dashboard.md                              # Jira-style dashboard board
    ├── current/
    │   └── YYYYMMDD-HHMM-task-description.md      # Active and recently completed task files
    └── archive/
        └── YYYYMMDD-HHMM-task-description.md      # Archived task files
```

Only `dashboard.md` sits at the top of `.tasks/`; every individual task file lives in `current/` or `archive/`. When a task is moved to the dashboard's Archive table, its file MUST be moved from `current/` into `archive/`. The directory is task-specific; other artifacts (for example `.opencode/no-verify.log`) live under their own namespaces.

### Gitignore Recommendation

Users SHOULD add `.tasks/` to their global gitignore, or MAY commit it selectively if task history should be preserved.

### File Naming Convention

| Component | Requirement |
|-----------|-------------|
| Pattern | `YYYYMMDD-HHMM-task-description.md` |
| Date/Time | 24-hour format, local time |
| Description | Kebab-case, 3-5 words maximum |
| Example | `20241222-0710-api-auth-refactor.md` |

The kebab-case rule governs the **filename** only. The task's human-readable **descriptive name** (the `# Task: [Descriptive Name]` title, the dashboard link text, and prose references) MUST use headline / AP-style title case: capitalize the first and last word and every noun, pronoun, verb, adjective, and adverb; lowercase only articles, coordinating conjunctions, and prepositions of three letters or fewer when mid-title. Example: filename `20241222-0710-api-auth-refactor.md`, descriptive name `Refactor the API Auth Flow`.

---

## Master Index Requirements

### Master Index Location

The master index MUST be located at `.tasks/dashboard.md`.

### Master Index Template

```markdown
# Task Board Dashboard

*Jira-style task management board. Auto-updated when task statuses change.*

## Triage

| Task | Priority | Created | Updated |
|------|----------|---------|---------|

## Ready

| Task | Priority | Created | Updated |
|------|----------|---------|---------|

## In Progress

| Task | Progress | Updated | Priority |
|------|----------|---------|----------|
| [Task Name](./current/20241222-0710-task-name.md) | 45% | 2024-12-31 19:45 | High |

**Note:** Details of what was done and what remains live in the task file itself, not on the board.

## Blocked/Cancelled

| Task | Status | Created | Updated |
|------|--------|---------|---------|

## Completed

| Task | Completed | Duration |
|------|-----------|----------|

## Archive

| Task | Completed | Duration |
|------|-----------|----------|

---

*Last updated: YYYY-MM-DD HH:MM - Auto-updated when task status changes*
```

Cell rules:

- In every lane, the `Task` cell MUST be a markdown link whose text is the task's descriptive name (title case, see [File Naming Convention](#file-naming-convention)) and whose target is `./current/<file>.md` while active or `./archive/<file>.md` once archived.
- In Triage, Ready, and Blocked/Cancelled tables, `Created` and `Updated` MUST each hold only a `YYYY-MM-DD HH:MM` timestamp, drawn from the task file's **Created** and **Updated** header fields. `Created` is set once and MUST NOT change; `Updated` moves with every change, so a waiting task's age stays visible. Use `N/A` when no creation timestamp is derivable.
- In Progress: `Progress` MUST be only a completion percentage (`10%`, `45%`), never a summary or status phrase. The at-a-glance summary lives in the task file's [Latest Update field](#latest-update-field).
- Completed/Archive: `Duration` MUST be only an active working time value (`3h 20m`, `2d 4h`, `45m`) or `N/A`. It is the accumulated working time from the task's logs (including Triage → Ready planning work), excluding Blocked periods and idle waits. Never a date, description, or placeholder like `-` or `TBD`.

### Index Maintenance

The master index and individual task files MUST remain synchronized at all times: a modification is complete ONLY when the dashboard reflects it, and status changes MUST update both the task file AND the dashboard in the same operation.

| When This Happens | You MUST Do This Immediately |
|-------------------|------------------------------|
| New task file created | Add entry to appropriate dashboard table (Triage/Ready/In Progress) |
| Task status changes | Move task between dashboard tables + update task file status |
| Task file modified | Update "Updated" column in dashboard to current timestamp |
| Work progresses | Update progress percentage in dashboard (if In Progress) |
| Task completed | Move to Completed table + populate "Completed" and "Duration" columns |
| Task blocked/cancelled | Move to Blocked/Cancelled table + record the reason prominently in the task file (not the dashboard) |
| ANY task file write | Update dashboard "Last updated" timestamp |

These direct edits assume a single writer; when concurrent sessions are possible they are superseded by [Concurrency and Multi-Session Safety](#concurrency-and-multi-session-safety).

---

## Concurrency and Multi-Session Safety

This section applies ONLY when two or more sessions may operate on the same `.tasks/` directory concurrently; in the single-session case the direct-edit rules above stand and this section does not apply. When applicable, it GOVERNS and supersedes conflicting in-place-edit instructions.

Sessions do not share memory, and every session rewrites `dashboard.md` on each state change, so naive concurrent edits produce lost updates. Two hazards exist: shared-aggregate contention (many sessions writing the single board) and same-task contention (two sessions claiming one task file). Every shared mutable file MUST have exactly one writer at any instant, enforced structurally:

### Derived Dashboard with Serialized Mutation

1. **Task files are the source of truth.** The dashboard MUST be fully reconstructable from the task files' canonical header fields (**Status**, **Priority**, **Progress**, **Created**, **Updated**, **Completed**, **Duration**; location distinguishes Completed from Archive). No state may exist only on the board.
2. **No direct edits.** Sessions MUST NOT edit `dashboard.md` in place; every change is a regeneration from the task files.
3. **Serialized regeneration.** Each regeneration MUST hold an exclusive advisory lock (e.g., `flock` on `.tasks/.lock`) for the read-and-write span, then release. Regeneration is an idempotent full rebuild, so concurrent sessions serialize harmlessly. The lock file is a transient artifact, exempt from task-file rules.
4. **Process-held, never agent-held.** The lock MUST be held by the regenerating process for the single rebuild command (milliseconds) and released on process exit, including abnormal exit. Implementations MUST NOT hold the lock across LLM tool calls, model turns, or agent reasoning; an agent-held lock deadlocks other sessions when a session is abandoned.

### Atomic Task Claiming

A session MUST claim a task before beginning work on it, atomically:

- The task file carries an **Owner** header field identifying the holding session (a human-readable mirror, not the gate itself).
- The claim gate MUST be atomic on the local filesystem: the provided tool implements it as an exclusive-create (`O_EXCL`) of `.tasks/current/<taskfile>.claim`, whose contents record the owning session. The kernel guarantees exactly one winner; losers observe the claim and MUST NOT proceed (select other work or defer). The winner writes its identifier into **Owner**. The sidecar is a transient artifact, exempt from task-file rules.
- Ownership MUST be released when the session finishes or is known to have exited (removes the sidecar, clears **Owner**), so abandoned claims do not strand work. Staleness detection MAY reclaim sidecars by timestamp.

### External Tooling Dependency

Concurrent operation requires a mutation tool performing the lock-rebuild-release cycle and the atomic claim. Until such a tool exists, concurrent multi-session operation against one `.tasks/` directory is UNSAFE and implementations MUST fall back to single-session operation.

In this environment the tool is the `tasks` command (on `PATH` at `~/.local/bin/tasks`):

- `tasks init` scaffolds `.tasks/` (dashboard, `current/`, `archive/`)
- `tasks render` rebuilds `dashboard.md` under a `flock` on `.tasks/.lock`; the derived `Last updated` is the newest **Updated** timestamp among tasks, not wall-clock time
- `tasks claim <taskfile>` / `tasks release <taskfile>` perform the `O_EXCL` claim (writing **Owner**) and its reverse, then render
- `tasks set <taskfile> Key=Value...` updates canonical header fields (refreshing **Updated**) and renders
- `tasks new --id <ID> --name <Name>` creates a task file with canonical header fields, then renders

Sessions MUST route every dashboard change through `tasks` rather than editing `dashboard.md` directly. Serialization does not weaken [Real-Time Updates](#real-time-updates): write the owning task file as work occurs, then trigger a regeneration at once.

---

## Task File Structure

### Required Sections

Each task file MUST contain: Objective, Success Criteria, Technical Approach (with Decision Log), Risk Assessment, Testing Strategy, TDD Workflow, Task Breakdown, Work Log, Execution Log.

### Cross-Reference Convention

References to sections, other task files, or these specifications MUST cite the target by its heading title as a markdown link (e.g., `[Completion Protocol](#completion-protocol)`), never by section number. This applies to Work Log entries too.

A reference from one task to *another task* MUST exist only when a real structural relationship justifies it, exhaustively: a declared **Dependencies** field, a parent ↔ child task-file link ([Child Task Files](#child-task-files)), or a deferred-work link from a closing task's Final Summary ([Deferred Work Capture at Closure](#deferred-work-capture-at-closure)). Implementations MUST NOT reference another task outside these cases: no "see also" links, no restating another task's content, no cross-links between tasks that merely touch the same area. When in doubt, omit.

### Latest Update Field

Every task file MUST carry a **Latest Update** field in its header, directly below the status block and above the Table of Contents. It holds a single entry (the most recent notable change), NOT a running list, and MUST contain all three of:

- A timestamp (`YYYY-MM-DD HH:MM`)
- A terse one-line summary of what changed
- A markdown link by heading title to the detailed record (the relevant Work Log entry, Decision Log decision, Progress Log, Failed Approach, or Execution Log milestone)

It is a live pointer, refreshed in place whenever a more recent notable change occurs. Refreshing it does NOT violate [Content Preservation](#content-preservation): the full cumulative history remains in the log section it links to; only the pointer moves.

### Child Task Files

A Task Breakdown subtask MAY be tracked inline or as a *child task file*: a link to a separately-tracked task file. Child task files nest to any depth, are ordinary task files, and MUST be identified by a proper hierarchical Task ID (`PREFIX-N-N`, see [Task ID Format](#task-id-format)) and a descriptive name. Placeholder labels (`A`, `B`, `C`, `Task 1`) or dot-suffixes (`PREFIX-N.A`) MUST NOT be used.

A child task file MUST be registered in the master index dashboard and move between tables as its own state changes, exactly like a standalone task; implementations MUST NOT track a child solely within its parent's breakdown. The parent entering In Progress does NOT cascade: each child remains in Ready until execution of that child actually begins, at which moment the manager MUST transition it Ready → In Progress. A child MUST reach Completed or Cancelled before the parent may close (see [Completion Protocol](#completion-protocol)).

### Coordination Tasks and Work Documentation Ownership

**The child task file owns the work record.** All documentation of the child's work (Work Log, Decision Log, Execution Log, Progress Log, Simplify and Review Loop records) lives in the child, written in real time exactly as for a standalone task.

**The parent task file is a coordination task.** A parent that breaks work across children is an orchestration record: sequencing children by dependency, dispatching and tracking them, and handling conflicts between them (shared-file contention, shared state, integration order, including any worktree isolation used to keep conflicting children parallel, per the `delegation` skill). The parent's Work Log records coordination activity, not the granular per-child work. Implementations MUST NOT duplicate a child's work log into the parent, and MUST NOT record a child's work only in the parent.

### Task File Template

```markdown
# Task: [Descriptive Name]

**Created:** YYYY-MM-DD HH:MM [Set once, never changed; drives dashboard Created column]
**Status:** Triage | Ready | In Progress | Blocked | Cancelled | Completed
**Status Reason:** [Required when Blocked or Cancelled: one line stating why. Omit otherwise.]
**Priority:** High | Medium | Low
**Progress:** [Integer percent with % sign, e.g. 45%. 0% until work begins.]
**Owner:** [Session identifier holding the atomic claim, or empty; managed by the claim tool]
**Checkpoint Gating:** autonomous | sign-off [Required for checkpoint-sliced tasks; omit otherwise. Default: autonomous.]
**Updated:** YYYY-MM-DD HH:MM [Timestamp of the last change; drives dashboard Updated column]
**Completed:** [YYYY-MM-DD HH:MM, set when Status becomes Completed; omit otherwise.]
**Duration:** [Active working time, e.g. 3h 20m, or N/A. Set when Completed; omit otherwise.]
**Latest Update:** [YYYY-MM-DD HH:MM] [One-line summary of the most recent notable change] ([detail](#anchor-of-the-detailed-record))

## Table of Contents

- [Objective](#objective)
- [Success Criteria](#success-criteria)
- [Technical Approach](#technical-approach)
- [Risk Assessment](#risk-assessment)
- [Testing Strategy](#testing-strategy)
- [TDD Workflow](#tdd-workflow)
- [Task Breakdown](#task-breakdown)
- [Work Log](#work-log)
- [Execution Log](#execution-log)

---

## Objective

[What we're trying to achieve and why]

**Business Value:** [Why this matters]

## Success Criteria

- [ ] Specific, measurable requirement 1
- [ ] Specific, measurable requirement 2

## Technical Approach

**Strategy:** [High-level approach]

**Architecture Changes:**

- Change 1
- Change 2

**Files to Review:**

*Critical files that must be examined to complete this task; a roadmap for anyone working on it.*

- `src/path/to/critical-file.ts` - [Why this file is important]
- `tests/related-test.spec.js` - [Tests to update or providing context]

### Decision Log

**Decision: [title]** · [YYYY-MM-DD HH:MM]
- **Context:** [What problem or choice prompted this decision]
- **Alternatives + why rejected:** [Option A: rejected because ...]
- **Chosen + rationale:** [Option B: why chosen]

---

## Risk Assessment

### High Risk

- **[Risk name]**
  - *Mitigation:* [Strategy]

### Medium Risk

- **[Risk name]**
  - *Mitigation:* [Strategy]

### Low Risk

- **[Risk name]**
  - *Mitigation:* [Strategy]

## Testing Strategy

### Test Plan Overview

**Testing Approach:** [Overall strategy - unit, integration, e2e, manual, automated]

**Test Types Required:**

| Test Type | Coverage Area | Priority | Notes |
|-----------|---------------|----------|-------|
| Unit Tests | [Specific functions/modules] | High/Medium/Low | [What needs testing] |
| Integration Tests | [System interactions] | High/Medium/Low | [Integration points to verify] |
| End-to-End Tests | [User workflows] | High/Medium/Low | [Critical user paths] |
| Performance Tests | [Performance-critical areas] | High/Medium/Low | [Benchmarks to meet] |

### Test Data Requirements

- [Type of data] - [Volume, characteristics, source]
- [Mock data requirements] - [What needs mocking, why]
- [Real data considerations] - [When real data is needed, privacy concerns]

### Success Criteria for Testing

- [ ] All existing tests continue to pass
- [ ] New functionality has [X]% test coverage
- [ ] Performance benchmarks are met: [specific metrics]

## TDD Workflow

### TDD Execution Protocol

**Mandatory TDD Sequence:** When working on any task, implementations MUST follow:

1. **Check Existing Tests:** run the suite to identify currently failing tests; document the baseline
2. **Update Tests First:** modify or create tests reflecting expected behavior; they MUST fail before implementation; document changes in the Work Log
3. **Verify Tests Fail:** confirm failures with the current implementation
4. **Implement Solution:** write production code to make tests pass
5. **Run Tests:** verify all pass
6. **Refactor If Needed:** improve quality while maintaining coverage; document significant refactoring
7. **Final Verification:** run tests again to ensure no regressions
8. **Simplify and Review Loop:** run the loop below to convergence

### Simplify and Review Loop

After tests pass, implementations MUST iterate a simplify-then-review cycle before the task may be marked Completed. Each iteration performs both passes in order:

1. **Simplify Pass (cleanup):** review the changed code for reuse, simplification, dead code, redundancy, and efficiency. Use `/simplify` where provided, otherwise equivalent manual cleanup. Apply every accepted improvement.
2. **Review Pass (bug hunt):** review for correctness bugs, logic errors, missing error handling, edge cases, and security issues. Use `/code-review` where provided, otherwise equivalent manual review. Fix every confirmed finding.

A "fix" is any change applied during the iteration, from either pass.

**Loop control:**

- After applying any fix, re-run the test suite to confirm no regressions
- The loop repeats as long as an iteration produced at least one fix
- The loop **converges** when one complete iteration produces **no fixes**
- Cap at a reasonable iteration count (default: 5). If not converged at the cap, stop, document outstanding findings in the Work Log, and consult the user before marking Completed

**Each iteration MUST be recorded in the Work Log:**

```
[Timestamp] Simplify and Review Loop: Iteration [N]
- Simplify pass: [N simplifications found] / [list findings or "none"]
- Simplifications applied: [description or "none"]
- Review pass: [N bugs found] / [list findings or "none"]
- Fixes applied: [description or "none"]
- Tests re-run: [pass/fail result]
- Converged: [yes/no - yes only when the iteration produced no fixes]
```

### TDD Exceptions

Deviations from the TDD workflow MUST be justified in the Work Log, cross-referencing the `coding-standards` rule's Test Planning Requirement and Test Change Intent Verification.

### Ready → In Progress Transition Requirements

Before transitioning to In Progress, the task file MUST have:

- [ ] Test command identified (how to run tests)
- [ ] Test framework documented
- [ ] Test file locations identified
- [ ] Existing test baseline recorded

### Completion Validation

A task CANNOT be marked Completed unless:

- All tests pass (including newly written tests)
- Test coverage meets or exceeds target percentage (if specified)
- TDD workflow is documented in the Work Log
- No TDD exceptions exist without justification and follow-up plan
- The Simplify and Review Loop has converged, or the cap was reached with findings documented and accepted by the user
- Each loop iteration is documented in the Work Log

## Task Breakdown

### Task [PREFIX-N-N]: [Name]

**Status:** Triage | Ready | In Progress | Blocked | Cancelled | Completed
**Priority:** High | Medium | Low
**Dependencies:** [Other task IDs or "None"]
**Assigned To:** [Agent/Ally name or "Unassigned"]

#### Description

[Detailed description of what needs to be done]

#### Acceptance Criteria

- [ ] Specific requirement 1
- [ ] Specific requirement 2

#### Progress Log

**Progress Log Update Requirement:** for tasks expected to take >5 minutes, implementations MUST add updates DURING execution, capturing what is being worked on, interim findings, obstacles and their handling, and next immediate steps.

- [Timestamp] Started by [Agent identifier]
- [Timestamp] Update: [Progress checkpoint, added DURING work]
- [Timestamp] Completed: [Results summary]

---

## Work Log

This section tracks all work performed during the task, whether by agents/allies or by the manager. Tone note: Manager entries remain factual and objective; Agent Report entries are recorded verbatim per [Tone and Voice Policy](#tone-and-voice-policy).

### [Timestamp]: [Agent/Ally Name]: [Task ID or "Exploration"]

**Purpose:** [Brief description of what this agent was asked to do]

**Instructions Given:**

```
[Verbatim prompt/instructions sent to the agent]
```

**Agent Report:**

```
[Verbatim output returned by the agent: full findings, not summarized]
```

**Manager Analysis:**

[How the manager interpreted these findings and what actions were taken]

**Follow-up Actions:**

- [Action 1 triggered by this report]

### [Timestamp]: Manager: [Task ID or Activity Description]

**Activity:** [e.g., "bug investigation", "implementation", "code review"]

**Actions Performed:**

- [e.g., "Read file src/auth.ts:1-50", "Applied fix: added null check"]

**Findings:**

[Objective findings - bugs discovered, patterns observed, issues encountered]

**Decisions Made:**

[Significant decisions and reasoning]

**Outcome:**

[e.g., "Bug fixed", "Issue documented"]

**Next Steps:**

[Immediate next actions or pending items]

---

## Execution Log

### Project Timeline

- **YYYY-MM-DD HH:MM** - Task file created
- **YYYY-MM-DD HH:MM** - [Milestone or significant event]
- **Status:** [Current phase]
- **Next Steps:** [Immediate actions]

### Work Summary

| Agent/Ally/Manager | Tasks/Activities | Mode | Status | Key Contributions |
|--------------------|------------------|------|--------|-------------------|
| [Name or "Manager"] | [Task IDs or Activity IDs] | Delegating/Solo | Complete/In Progress | [What they accomplished] |

When operating in Manager Mode (Solo), "Manager" appears as a row tracking personal work execution.

### Failed Approaches

#### Attempt: [What was tried]

*Timestamp: YYYY-MM-DD HH:MM*

**Approach:** [What was attempted]
**Result:** [What happened: error messages, unexpected behavior]
**Why It Failed:** [Root cause analysis]
**Lessons Learned:** [What this taught us]

---

### Final Summary

**Outcome:** [Success/Partial Success/Failed]

**What Was Accomplished:**

- [Accomplishment 1]

**What Was Learned:**

- [Insight 1]

**Remaining Work:** [If any]
```

---

## Task ID Format

Top-level task IDs MUST follow `PREFIX-N` (`N` sequential, no zero-padding: `AUTH-1`, `API-14`). Subtask and child IDs append `-N` segments hierarchically (`PREFIX-N-N`, `PREFIX-N-N-N`); numbering restarts at 1 within each parent.

| Level | ID | Name |
|-------|-----|------|
| Parent | `AUTH-1` | User authentication |
| Subtask | `AUTH-1-1` | Token refresh |
| Subtask | `AUTH-1-2` | Session store |
| Sub-subtask | `AUTH-1-2-1` | Redis adapter |

Placeholder labels (`A`, `B`, `C`, `Task 1`, `Task 2`) or dot-and-letter suffixes (`AUTH-1.A`) MUST NOT substitute for a Task ID. Every task and subtask, including closure-spawned work and child task files, MUST receive a real numeric Task ID and a descriptive name.

### Standard Prefixes

| Prefix | Meaning |
|--------|---------|
| `AUTH` | Authentication-related |
| `API` | API endpoints |
| `UI` | User interface |
| `TEST` | Testing tasks |
| `DOCS` | Documentation |
| `INFRA` | Infrastructure |
| `TASK` | Generic tasks |
| `EXPLORE` | Exploration/discovery |

Custom prefixes MAY be used when they improve clarity.

---

## Task Lifecycle States

| State | Description |
|-------|-------------|
| **Triage** | Quick task file created, needs more information/exploration |
| **Ready** | Fully fleshed out, ready to work on |
| **In Progress** | Actively being worked on |
| **Blocked** | Cannot proceed due to external dependency |
| **Cancelled** | No longer needed |
| **Completed** | Finished successfully, acceptance criteria met |

### Automatic State Transitions

| Trigger Event | Required State Change | Dashboard Action |
|---------------|----------------------|------------------|
| Work begins on a Ready task | Ready → In Progress | Move row to In Progress table |
| A coordination (parent) task begins executing a Ready child (directly or via dispatch) | child: Ready → In Progress | Move the child row to In Progress table |
| Task becomes blocked | In Progress → Blocked | Move to Blocked/Cancelled table; record reason in task file |
| Blocked task can proceed | Blocked → Ready or In Progress | Move back to appropriate table |
| All acceptance criteria met AND Simplify and Review Loop converged | In Progress → Completed | Move to Completed table with completion timestamp |
| Task no longer needed | Any state → Cancelled | Move to Blocked/Cancelled table; record reason in task file |

### Triage to Ready Planning Phase

Triage → Ready is the planning and clarification phase: tasks are created in Triage intentionally incomplete, and Triage is NOT a work-ready state but a signal that planning must happen before execution.

During the transition, implementations MUST:

1. **Apply Clarification Protocol** (the `core` rule): ask pointed questions, clarify vague objectives, identify specific success criteria, determine scope boundaries
2. **Conduct Exploration and Reconnaissance:** quick lookups (< 30 seconds) via direct tools (glob, grep, read); proper reconnaissance MUST be thorough, delegating to exploration allies where the `delegation` skill requires. Understand existing architecture, identify relevant files, map dependencies
3. **Populate All Task File Sections:** Objective, Success Criteria, Technical Approach, Risk Assessment, Task Breakdown, Decision Log
4. **Assess and Document Risks:** identify blockers, evaluate complexity, document external dependencies, plan mitigations
5. **Decide Checkpoint Slicing** ([Checkpoint Slicing (MVP Waystations)](#checkpoint-slicing-mvp-waystations)): determine whether the task warrants slicing; if so, structure the breakdown contract-first with mock-bounded slices and an integration checkpoint; raise the gating mode with the user (default: autonomous)

A task moves to Ready ONLY when: all clarifying questions are answered; exploration findings are documented; all required sections are populated; the technical approach is defined and validated; risks are identified with mitigations; success criteria are clear and measurable; the breakdown is complete with acceptance criteria; and, if sliced, the slice structure and gating mode are defined.

**A task MUST NOT move to In Progress without first being properly planned in the Triage → Ready phase.**

---

## Checkpoint Slicing (MVP Waystations)

### Purpose

Large tasks SHOULD be decomposed so work reaches verifiable, working states at intermediate points. A **checkpoint** is a slice of the task that, once done, is independently built, tested, reviewed, and demonstrable, letting drift and integration errors surface at slice boundaries instead of at the end. Each checkpoint is realized as a **child task file** with its own hierarchical Task ID, dashboard lifecycle, TDD Workflow, and converged Simplify and Review Loop; no new tracking construct exists.

### When to Use Checkpoint Slicing

Apply when BOTH hold: the task is large enough that a single build-then-verify pass would leave substantial work unverified for a long stretch (as a guide, two or more independently meaningful slices); and the seams between slices have a **definable contract** (interface, schema, or API agreed in advance).

MUST NOT apply when: the task is small enough that one slice is the whole job; or the contract is genuinely unknown (mocking a guessed contract only defers the mismatch). In the unknown-contract case, first build a thin **walking skeleton** (one minimal end-to-end slice through all layers with real components) to establish the contract, then fan out.

### Slicing Doctrine

When slicing applies, the parent's Task Breakdown MUST be structured as:

1. **Contract first.** Before any slice depending on a seam, define that seam as a shared artifact both mock and real implementation MUST honor. It MAY be its own checkpoint child task, but MUST exist before dependent slices begin.
2. **Mock-bounded slices.** Each slice mocks cross-slice dependencies it does not own, coded against the shared contract, and MUST reach a genuinely working, tested state on its own (own tests, own converged loop). Slices with distinct territory MAY run in parallel per the `delegation` skill's boundary isolation.
3. **Integration checkpoint.** A final child task MUST replace mocks with real wiring and test the seams end-to-end, declaring `Dependencies` on the slices it connects so it runs only after they are Completed.

Example decomposition for a feature spanning a web UI and a database:

| Checkpoint | Task ID | Slice | Verified state |
|------------|---------|-------|----------------|
| Contract | `WEB-1-1` | Define the data-access interface | Interface compiles and is agreed |
| Web slice | `WEB-1-2` | Build pages against a mocked data layer | Pages work, tested against the mock |
| Data slice | `WEB-1-3` | Build the real data layer against the interface | Data layer tested in isolation |
| Integration | `WEB-1-4` | Wire pages to the real layer, remove mock | End-to-end flow works, tested |

`WEB-1-2` and `WEB-1-3` share no files and MAY run in parallel; `WEB-1-4` depends on both.

### Checkpoint Gating

Each checkpoint-sliced task MUST record a **gating mode** in the **Checkpoint Gating** header field:

- **autonomous** (default): the manager self-verifies the checkpoint (tests pass, loop converged), records a milestone in the parent's Execution Log timeline, and proceeds without interrupting the user, escalating only on failure or a Significant question (per the `delegation` skill's Question Batching Discipline)
- **sign-off**: reaching a checkpoint is a hard stop; the manager presents the slice overview plus test and review results and waits for user confirmation before the next checkpoint

The mode is chosen during Triage → Ready planning; the manager MUST raise the choice with the user, defaulting to autonomous when there is no preference. Gating never suppresses failure reporting: under either mode, a checkpoint whose tests fail or whose loop cannot converge MUST halt progression and be handled per [Completion Validation](#completion-validation).

### Milestone Recording

Under both modes, each reached checkpoint MUST be recorded as a milestone in the parent's Execution Log timeline: which slice completed, its verification result (tests and loop convergence), and under sign-off mode the user's confirmation.

---

## Update Requirements

### Real-Time Updates

For any work done related to a task file, the task file MUST be updated immediately and thoroughly, in real time, as the work occurs: actions, discoveries, decisions, status changes, and progress, with no exceptions. It is strictly prohibited to defer, batch, or omit updates. Task files are living documents updated DURING execution, not historical records written afterward; failure to update the task file for related work is a critical conformance failure.

- Work Log updated AS work happens: progress during agent execution (not only at completion), findings/decisions/actions as the manager works, full verbatim agent output immediately after reports
- Decision Log updated AT THE MOMENT significant choices are made
- [Latest Update field](#latest-update-field) refreshed whenever a more recent notable change occurs
- Failed Approaches documented IMMEDIATELY when attempts fail
- Task status updates follow [Index Maintenance](#index-maintenance) synchronization rules

**Dashboard Synchronization:** the dashboard MUST reflect task file changes immediately, through the serialized path of [Concurrency and Multi-Session Safety](#concurrency-and-multi-session-safety) when sessions may share the directory. Users should be able to open a task file at ANY moment and see current status, not outdated information.

### Verbatim Recording Requirement

Agent output MUST be recorded verbatim in Work Log agent entries. Implementations MUST NOT summarize or paraphrase agent reports; full context is valuable for debugging, accountability, and traceability. Manager entries MUST accurately document actions, findings, and outcomes.

### Decision Documentation Requirement

All significant decisions MUST include: alternatives considered, rejection reasoning for each alternative not chosen, and tradeoffs accepted with the chosen approach.

### Completion Protocol

When a task completes, implementations MUST:

1. Confirm all Task Breakdown subtasks (inline or child task files) are Completed or Cancelled
2. Confirm the Simplify and Review Loop has converged
3. Capture all deferred work as new task files per [Deferred Work Capture at Closure](#deferred-work-capture-at-closure)
4. Update task status to "Completed"
5. Check all acceptance criteria boxes
6. Add final progress log entry with summary
7. Complete the Final Summary section
8. Update the master index: move to the Completed table, populate "Completed" and "Duration", refresh "Last updated"

### Content Preservation

Implementations MUST NEVER delete, clear, or overwrite previously written content in task files. Task files are cumulative records that only grow; use append operations and preserve all existing sections. The dashboard likewise preserves all task references. The ONLY permissible deletion is when a user explicitly and specifically commands it; ambiguous instructions MUST NOT trigger deletion.

### Deferred Work Capture at Closure

This applies to EVERY task closure, Solo and Delegating. Before a task may be marked Completed, implementations MUST capture every piece of identified-but-undone work: deferred improvements, follow-ups and "nice-to-haves", anything discovered but ruled out of scope, and simpler-solution tradeoffs recorded per the `coding-standards` rule's Simple Solution Documentation.

For each item: create a new task file in Triage state with a proper Task ID and descriptive name; register it in the dashboard; link it from the closing task's Final Summary "Remaining Work" entry. Placeholder labels MUST NOT be used.

Deferred work MUST NOT survive closure as prose, a TODO, or a Work Log note: any work that outlives the task becomes its own task file. A task MUST NOT be marked Completed while identified deferred work remains uncaptured. When closing as Cancelled, still-desired work is likewise captured; unwanted work needs no capture.

---

## Question Tracking

This is the file-based bookkeeping for the question policy canonical in the `delegation` skill's Question Batching Discipline; the policy itself is not restated here.

- A **Basic** question (answered autonomously per policy) is recorded in the **Question Log** with its source, the answer, and the rationale justifying answering without interrupting the user.
- A **Significant** question (deferred per policy) is recorded in the **Question Queue** with its source, current state, the task IDs it blocks (or "none yet"), and the user resolution once answered.

### Question States

| State | Meaning |
|-------|---------|
| **Open** | Just raised, not yet classified |
| **Self-Answered** | Basic question resolved by the manager and logged |
| **Queued** | Significant question deferred, work continues around it |
| **Blocking** | Queued question now gates all remaining work |
| **Asked** | Presented to the user, awaiting answer |
| **Resolved** | User answered, resolution recorded |
| **Cancelled** | No longer relevant, reason recorded |

Permitted transitions: `Open → Self-Answered`; `Open → Queued → Blocking → Asked → Resolved`; `Queued → Asked → Resolved`; any Queued/Blocking/Asked state `→ Cancelled` with a recorded reason.

### Question Log and Queue Format

The Question Queue MUST be kept current in real time per [Real-Time Updates](#real-time-updates). Every queued question MUST end as either Resolved by the user or explicitly Cancelled with a recorded reason, never silently dropped.

```
Question Log (Basic, self-answered):
- [Timestamp] Q (source: API-001 agent): [question]
  - Answer: [manager answer]
  - Rationale: [why answering autonomously was justified]

Question Queue (Significant):
- [Timestamp] Q (source: API-002 agent): [question]
  - State: Queued | Blocking | Asked | Resolved | Cancelled
  - Blocks: [task IDs, or "none yet"]
  - Resolution: [user answer once Resolved]
```

---

## Conformance

Violations of MUST requirements constitute conformance failures, notably: failing to keep dashboard and task files synchronized ([Index Maintenance](#index-maintenance)); creating task files without user request ([Creation Prohibition](#creation-prohibition)); summarizing agent output instead of recording verbatim ([Verbatim Recording Requirement](#verbatim-recording-requirement)); marking a task Completed before the Simplify and Review Loop has converged or without documenting each iteration; failing to immediately update the task file for related work; deleting or overwriting previously written content ([Content Preservation](#content-preservation)); fabricating an answer to a Significant question or silently dropping a queued question; closing a task while deferred work remains uncaptured as task files; applying checkpoint slicing without a contract-first step or an integration checkpoint declaring Dependencies; omitting the Checkpoint Gating field or failing to raise the gating choice with the user; editing `dashboard.md` in place, holding an agent-held lock across tool calls, or beginning work without an atomic claim when sessions may share the directory ([Concurrency and Multi-Session Safety](#concurrency-and-multi-session-safety)).
