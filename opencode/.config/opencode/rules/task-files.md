# Task File Protocol

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## Scope

This specification defines requirements for creating and managing task files during complex operations. Task files provide comprehensive documentation of work performed, decisions made, knowledge gained, bugs encountered, and progress tracking.

Task files serve multiple purposes:

- Tracking agent/allies work and conversations (Manager Mode (Delegating))
- Tracking manager's own work, findings, and decisions (Manager Mode (Solo))
- Documenting bugs discovered and resolutions
- Recording strategic decisions and their rationale
- Maintaining a complete work history for review and reference

### Related Specifications

- [`delegation.md`](delegation.md): Manager Mode and delegation requirements
- [`execution-standards.md`](execution-standards.md): Task execution requirements and task terminology context

### Tone and Voice Policy

- All sections MUST use professional, formal tone with no character voice, per [`core.md` Formal Output Standards](core.md#formal-output-standards).
- Exceptions (both in the Work Log template, [Task File Template](#task-file-template)):
  - The Agent Report entry: record verbatim, regardless of tone.
  - The Manager entry: MAY use informal conversational tone appropriate to ongoing work updates while remaining factual and objective.
- Every other section of the task file MUST remain formal.

---

## Creation Rules

### Creation Triggers

Task files MUST be created ONLY when:

- User explicitly requests task file creation or planning documentation
- User requests in-depth documentation of work performed, findings, or decisions 
  (e.g., "full report", "write a report", "document your findings", 
  "write up what you found", "document this investigation")
- User explicitly activates Manager Mode
- User explicitly confirms delegation at the 4+ todo item threshold

Note: Casual summary requests (e.g., "summarize", "quick summary", "recap") 
do NOT trigger task file creation. Use direct responses for these.

### Creation Prohibition

Task files MUST NOT be created proactively without user request.

Standard todo tracking via TodoWrite is sufficient for most operations.

---

## Directory Structure

### Required Structure

When task files are required, implementations MUST use this structure:

```
Project Root/
└── .tasks/
    ├── dashboard.md                              # Jira-style dashboard board
    ├── current/
    │   └── YYYYMMDD-HHMM-task-description.md      # Active and recently completed task files
    └── archive/
        └── YYYYMMDD-HHMM-task-description.md      # Archived task files
```

Individual task files live in `.tasks/current/` while active or recently completed. When a task is moved to the dashboard's Archive table, its file MUST be moved from `.tasks/current/` into `.tasks/archive/` to keep the current set uncluttered. Only `dashboard.md` sits at the top of `.tasks/`; every individual task file lives in one of the two subfolders.

### Directory Purpose

The `.tasks/` directory keeps task management artifacts separate from project code. It holds the dashboard board at its top, the `current/` subfolder for active task files, and the `archive/` subfolder for retired tasks.

This directory is task-specific. Other OpenCode artifacts (for example the `.opencode/no-verify.log` audit trail defined in [`git-protocol.md`](git-protocol.md)) live under their own namespaces and are not affected by this structure.

### Gitignore Recommendation

Users SHOULD add `.tasks/` to their global gitignore:

```bash
# ~/.config/git/ignore or project .gitignore
.tasks/
```

Users MAY commit `.tasks/` selectively if task history should be preserved.

### File Naming Convention

Individual task files MUST follow this format:

| Component | Requirement |
|-----------|-------------|
| Pattern | `YYYYMMDD-HHMM-task-description.md` |
| Date/Time | 24-hour format, local time |
| Description | Kebab-case, 3-5 words maximum |
| Example | `20241222-0710-api-auth-refactor.md` |

The kebab-case rule above governs the **filename** only. The task's human-readable **descriptive name** (the `# Task: [Descriptive Name]` title, the dashboard link text, and any reference to the task in prose) MUST use headline / AP-style title case: capitalize the first and last word and every noun, pronoun, verb, adjective, and adverb; lowercase only articles (a, an, the), coordinating conjunctions (and, but, or, nor, for, so, yet), and prepositions of three letters or fewer when they fall mid-title. Example: filename `20241222-0710-api-auth-refactor.md`, descriptive name `Refactor the API Auth Flow`.

---

## Master Index Requirements

### Master Index Location

The master index MUST be located at `.tasks/dashboard.md`.

### Master Index Template

```markdown
# Task Board Dashboard

*Jira-style task management board. Auto-updated when task statuses change.*

## Triage

| Task | Priority | Updated |
|------|----------|---------|

## Ready

| Task | Priority | Updated |
|------|----------|---------|

## In Progress

| Task | Progress | Updated | Priority |
|------|----------|---------|----------|
| [Task Name](./current/20241222-0710-task-name.md) | 45% | 2024-12-31 19:45 | High |

**Note:** Details of what was done and what remains live in the task file itself, not on the board.

## Blocked/Cancelled

| Task | Status | Updated |
|------|--------|---------|

## Completed

| Task | Completed | Duration |
|------|-----------|----------|

## Archive

| Task | Completed | Duration |
|------|-----------|----------|

---

*Last updated: YYYY-MM-DD HH:MM - Auto-updated when task status changes*
```

In every lane, the `Task` cell MUST be a markdown link whose text is the task's descriptive name (headline / AP-style title case, see [File Naming Convention](#file-naming-convention)) and whose target is the task file: `./current/<file>.md` while active or recently completed, `./archive/<file>.md` once archived.

### Index Maintenance

The master index (`dashboard.md`) and individual task files MUST remain synchronized at all times. Update both in a single atomic operation whenever task documentation changes.

Required actions (MANDATORY):

1. After ANY task file write, IMMEDIATELY update the dashboard.
2. When task status changes, you MUST update both the task file AND the dashboard IN THE SAME OPERATION.
3. A modification is complete ONLY when the dashboard reflects it.

**Mandatory synchronization triggers:**

| When This Happens | You MUST Do This Immediately |
|-------------------|------------------------------|
| New task file created | Add entry to appropriate dashboard table (Triage/Ready/In Progress) |
| Task status changes | Move task between dashboard tables + update task file status |
| Task file modified | Update "Updated" column in dashboard to current timestamp |
| Work progresses | Update progress percentage in dashboard (if In Progress) |
| Task moves between states | Move row to new table + update all relevant columns |
| Task completed | Move to Completed table + populate "Completed" and "Duration" columns |
| Task blocked/cancelled | Move to Blocked/Cancelled table + record the reason prominently in the task file (not the dashboard) |
| ANY task file write | Update dashboard "Last updated" timestamp |

---

## Task File Structure

### Required Sections

Each task file MUST contain these sections, as they appear within the standard task file template ([Task File Template](#task-file-template)):

- Objective
- Success Criteria
- Technical Approach (with Decision Log)
- Risk Assessment
- Testing Strategy
- TDD Workflow
- Task Breakdown
- Work Log
- Execution Log

### Cross-Reference Convention

Within a task file, references to its own sections, to another task file, or to these specifications MUST cite the target by its heading title as a markdown link (for example, `[Completion Protocol](#completion-protocol)`), never by a section number. Work Log entries follow this rule as well: when an entry points to a section, decision, or another task, it links to that heading by title.

### Child Task Files

A Task Breakdown subtask MAY be tracked inline within this task file, or as a *child task file*: a link to a separately-tracked task file. A child task file is itself an ordinary task file and MAY have its own child task files, so the structure nests to any depth.

Every child task file, and every subtask within a Task Breakdown, MUST be identified by a proper hierarchical Task ID derived from its parent (`PREFIX-N-N`, see [Task ID Format](#task-id-format)) AND a descriptive name. Its filename MUST follow the [File Naming Convention](#file-naming-convention). Implementations MUST NOT label child tasks or subtasks with placeholder single-letter or sequential markers (for example, `A`, `B`, `C`, or `Task 1`, `Task 2`), nor with a dot-and-letter suffix such as `PREFIX-N.A`; each identifier MUST be numeric and describe the work it represents.

Because a child task file is an ordinary task file, it MUST be registered in the master index dashboard ([Index Maintenance](#index-maintenance)) and MUST move between the dashboard tables as its own state changes, exactly as a standalone task does. Implementations MUST NOT track a child task file solely within its parent's Task Breakdown while leaving the dashboard unaware of it. Specifically:

- When the child task file is created, it MUST be added to the appropriate dashboard table (Triage, Ready, or In Progress) per [Index Maintenance](#index-maintenance).
- As work on the child progresses, its state transitions MUST be reflected on the dashboard in real time, following [Automatic State Transitions](#automatic-state-transitions) and the [Real-Time Updates](#real-time-updates) mandate. The child moves Triage → Ready → In Progress → Completed (or Blocked/Cancelled) on the board independently of its parent's row. The parent entering In Progress does NOT cascade to its children: each child remains in Ready until execution of that child actually begins. At the moment the parent coordination task starts working a Ready child (directly or by dispatching it to an agent/ally), the manager MUST transition that child Ready → In Progress, independently of the parent's own row.
- A child task file MUST reach Completed or Cancelled on the dashboard before the parent task may close, consistent with the [Completion Protocol](#completion-protocol) requirement that all Task Breakdown subtasks be Completed or Cancelled.

### Coordination Tasks and Work Documentation Ownership

When a task is broken into child task files, the parent and child task files play distinct documentation roles. Implementations MUST observe this division.

**The child task file owns the work record.** A child task file is worked exactly as if it were a single standalone task. All documentation of the work performed on the child lives in the child task file itself: its Work Log, its Decision Log (within Technical Approach), its Execution Log, and its Progress Log entries, all sections of the standard task file template ([Task File Template](#task-file-template)). The actions, findings, decisions, failed approaches, and per-iteration Simplify and Review Loop records for the child's work MUST be written into the child task file, not the parent. The same [Real-Time Updates](#real-time-updates) mandate applies to the child while it is being worked.

**The parent task file is a coordination task.** A parent that exists to break work across child task files is an orchestration record, not a second copy of the children's work. Its role is to coordinate the children being worked together: sequencing them by dependency, dispatching and tracking them, and handling conflicts between them (shared-file contention, shared state, integration order, and reconciliation, including any [Worktree Isolation](delegation.md#worktree-isolation) used to keep conflicting children parallel). The parent's Work Log records this coordination activity, not the granular per-child work. Implementations MUST NOT duplicate a child's detailed work log into the parent, and MUST NOT record a child's work only in the parent while leaving the child task file empty.

The parent reflects each child's status through its Task Breakdown entry and the dashboard ([Index Maintenance](#index-maintenance)); the substance of how each child was accomplished is read from the child task file.

### Task File Template

```markdown
# Task: [Descriptive Name]

*Created: YYYY-MM-DD HH:MM*
**Status:** Triage | Ready | In Progress | Blocked | Cancelled | Completed
**Status Reason:** [Required when Blocked or Cancelled: one line stating plainly why. Omit otherwise.]

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
- [ ] Specific, measurable requirement 3

## Technical Approach

**Strategy:** [High-level approach]

**Architecture Changes:**

- Change 1
- Change 2

**Files to Review:**

*Critical files that must be examined to complete this task. This provides a roadmap for anyone working on the task.*

- `src/path/to/critical-file.ts` - [Brief description of why this file is important]
- `config/settings.json` - [Configuration that affects the task]
- `tests/related-test.spec.js` - [Tests that need to be updated or provide context]
- `docs/api-documentation.md` - [Documentation that needs updating]

### Decision Log

**Decision: [title]** · [YYYY-MM-DD HH:MM]
- **Context:** [What problem or choice prompted this decision]
- **Alternatives + why rejected:** [Option A: rejected because ...; Option C: rejected because ...]
- **Chosen + rationale:** [Option B: why this was chosen]

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
| Unit Tests | [Specific functions/modules] | High/Medium/Low | [What needs to be tested] |
| Integration Tests | [System interactions] | High/Medium/Low | [Integration points to verify] |
| End-to-End Tests | [User workflows] | High/Medium/Low | [Critical user paths] |
| Performance Tests | [Performance-critical areas] | High/Medium/Low | [Benchmarks to meet] |

### Test Data Requirements

**Test Data Needed:**
- [Type of data] - [Volume, characteristics, source]
- [Mock data requirements] - [What needs to be mocked, why]
- [Real data considerations] - [When real data is needed, privacy concerns]

**Test Environment Setup:**
- [Environment requirements for testing]
- [Data setup/teardown procedures]
- [Test isolation requirements]

### Success Criteria for Testing

- [ ] All existing tests continue to pass
- [ ] New functionality has [X]% test coverage
- [ ] Performance benchmarks are met: [specific metrics]
- [ ] Security tests pass (if applicable)
- [ ] Cross-browser/platform testing completed (if applicable)

## TDD Workflow

### TDD Execution Protocol

**Mandatory TDD Sequence:** When working on any task, implementations MUST follow this sequence:

1. **Check Existing Tests:** Run test suite to identify currently failing tests
2. **Update Tests First:** Modify or create tests to reflect expected behavior for the task
3. **Verify Tests Fail:** Confirm tests fail with current implementation (demonstrates test validity)
4. **Implement Solution:** Write production code to make tests pass
5. **Run Tests:** Execute test suite to verify all tests pass
6. **Refactor If Needed:** Improve code quality while maintaining test coverage
7. **Final Verification:** Run tests again to ensure no regressions
8. **Simplify and Review Loop:** Run a simplify pass, then a review pass, fix every finding, and repeat the cycle as long as any iteration still produces fixes (see "Simplify and Review Loop" below)

**TDD Requirements:**

| Phase | Action | Validation | Documentation |
|-------|--------|-------------|----------------|
| **Check Tests** | Run existing test suite | Identify failing tests and pass count | Document baseline test results |
| **Update/Create Tests** | Write/modify tests for expected behavior | Tests MUST fail before implementation | Document test changes in Work Log |
| **Verify Failures** | Run tests to confirm failures | Confirms tests detect missing behavior | Record failure messages |
| **Implement** | Write production code | Code focused on making tests pass | Update code with implementation |
| **Verify Pass** | Run full test suite | All tests MUST pass | Record passing results |
| **Refactor** | Improve code quality | Tests must continue passing | Document refactoring if significant |
| **Final Run** | Complete test suite execution | Zero failures | Final test results documented |
| **Simplify and Review Loop** | Iterate simplify pass then review pass, applying fixes | Clean iteration: zero fixes produced | Document each iteration in Work Log |

### Simplify and Review Loop

**Mandatory Convergence Requirement:** After tests pass, implementations MUST iterate a simplify-then-review cycle over the task's changes before the task may be marked Completed. The loop runs as long as any iteration still produces fixes, and stops only when a full iteration produces none.

**Each iteration MUST perform both passes, in this order:**

1. **Simplify Pass (cleanup):** Review the changed code for reuse opportunities, simplification, dead code, redundancy, and efficiency improvements. Where the environment provides the `/simplify` command, implementations MUST use it; otherwise perform an equivalent manual cleanup. Apply every accepted improvement.

2. **Review Pass (bug hunt):** Review the changed code for correctness bugs, logic errors, missing error handling, edge cases, and security issues. Where the environment provides the `/code-review` command, implementations MUST use it; otherwise perform an equivalent manual review. Fix every confirmed finding.

A "fix" means any change applied during the iteration, whether from the simplify pass or the review pass.

**Loop Control:**

- After applying any fix, implementations MUST re-run the test suite to confirm no regressions were introduced.
- The loop repeats as long as an iteration produced at least one fix (a fix can introduce a new bug or a new simplification opportunity).
- The loop **converges** when one complete iteration (simplify pass then review pass) produces **no fixes**. Only then is the loop satisfied.
- Implementations MUST cap the loop at a reasonable iteration count (default: 5 iterations). If the loop has not converged at the cap, implementations MUST stop, document the outstanding findings in the Work Log, and consult the user before marking the task Completed.

**Loop Work Log Entry Format:**

Each iteration MUST be recorded in the Work Log:

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

Deviations from the TDD workflow MUST be justified in the Work Log, cross-referencing [`coding-standards.md` Test Planning Requirement](coding-standards.md#test-planning-requirement) and [Test Change Intent Verification](coding-standards.md#test-change-intent-verification).

### Ready → In Progress Transition Requirements

Before transitioning to In Progress, task file MUST have:
- [ ] Test command identified (how to run tests)
- [ ] Test framework documented
- [ ] Test file locations identified
- [ ] Existing test baseline recorded

### Completion Validation

Task CANNOT be marked Completed unless:
- All tests pass (including newly written tests)
- Test coverage meets or exceeds target percentage (if specified)
- TDD workflow is documented in Work Log
- No TDD exceptions exist without justification and follow-up plan
- The Simplify and Review Loop has converged (a full iteration produced no fixes), or the iteration cap was reached and outstanding findings were documented and accepted by the user
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

**Progress Log Update Requirement:** For tasks expected to take >5 minutes, implementations MUST add progress updates DURING execution, not only at completion. Updates MUST capture:
- What is currently being worked on
- Interim findings or discoveries
- Obstacles encountered and how they're being addressed
- Current status and next immediate steps

**Example entries:**
- [Timestamp] Started by [Agent identifier]
- [Timestamp] Update: [Progress description - added DURING work]
- [Timestamp] Update: [Another progress checkpoint]
- [Timestamp] Completed: [Results summary]

---

## Work Log

This section tracks all work performed during the task, whether by agents/allies or by the manager. Tone note: Work Log entries follow the exception in [Tone and Voice Policy](#tone-and-voice-policy).

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
- [Action 2 triggered by this report]

### [Timestamp]: Manager: [Task ID or Activity Description]

**Activity:** [What the manager was doing - e.g., "bug investigation", "implementation", "code review", "exploration"]

**Actions Performed:**

- [Action 1 - e.g., "Read file src/auth.ts:1-50"]
- [Action 2 - e.g., "Identified null reference on line 24"]
- [Action 3 - e.g., "Applied fix: added null check"]

**Findings:**

[Objective findings - bugs discovered, patterns observed, issues encountered]

**Decisions Made:**

[Significant decisions and reasoning]

**Outcome:**

[Result - e.g., "Bug fixed", "Code refactored", "Issue documented"]

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

This section summarizes all work performed, whether by agents/allies or by the manager.

| Agent/Ally/Manager | Tasks/Activities | Mode | Status | Key Contributions |
|--------------------|------------------|------|--------|-------------------|
| [Name or "Manager"] | [Task IDs or Activity IDs] | Delegating/Solo | Complete/In Progress | [What they accomplished] |

**Note:** When operating in Manager Mode (Solo), "Manager" appears as a row in this table tracking personal work execution.

### Failed Approaches

#### Attempt: [What was tried]

*Timestamp: YYYY-MM-DD HH:MM*

**Approach:** [Description of what was attempted]

**Result:** [What happened: error messages, unexpected behavior]

**Why It Failed:** [Root cause analysis]

**Lessons Learned:** [What this taught us]

---

### Final Summary

**Outcome:** [Success/Partial Success/Failed]

**What Was Accomplished:**

- [Accomplishment 1]
- [Accomplishment 2]

**What Was Learned:**

- [Insight 1]
- [Insight 2]

**Remaining Work:** [If any]
```

---

## Task ID Format

### ID Pattern

Top-level task IDs MUST follow the pattern: `PREFIX-N`, where `N` is a sequential number with no zero-padding (for example, `AUTH-1`, `API-14`).

Subtask and child task IDs MUST be derived hierarchically from their parent by appending a dash and a sequential number: `PREFIX-N-N`. Nesting MAY continue to any depth by appending further `-N` segments (`PREFIX-N-N-N`). Numbering restarts at `1` within each parent.

| Level | ID | Name |
|-------|-----|------|
| Parent | `AUTH-1` | User authentication |
| Subtask | `AUTH-1-1` | Token refresh |
| Subtask | `AUTH-1-2` | Session store |
| Sub-subtask | `AUTH-1-2-1` | Redis adapter |

Implementations MUST NOT substitute placeholder labels (single letters such as `A`, `B`, `C`, or bare sequential markers such as `Task 1`, `Task 2`) for a Task ID, and MUST NOT use a dot-and-letter suffix such as `AUTH-1.A` or `AUTH-1.B` for subtasks. Every task and subtask, including those spawned at closure ([Deferred Work Capture at Closure](#deferred-work-capture-at-closure)) and child task files ([Child Task Files](#child-task-files)), MUST receive a real numeric Task ID and a descriptive name: `PREFIX-N` at the top level, `PREFIX-N-N` for subtasks and children.

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

Implementations MUST automatically transition task states when triggering events occur:

| Trigger Event | Required State Change | Dashboard Action |
|---------------|----------------------|------------------|
| Work begins on a Ready task | Ready → In Progress | Move from Ready table to In Progress table |
| A coordination (parent) task begins execution of a Ready child task (whether the manager works it directly or dispatches it to an agent/ally) | child: Ready → In Progress | Move the child row from Ready table to In Progress table |
| Task becomes blocked | In Progress → Blocked | Move to Blocked/Cancelled table; record reason in task file |
| Blocked task can proceed | Blocked → Ready or In Progress | Move back to appropriate table |
| All acceptance criteria met AND Simplify and Review Loop converged | In Progress → Completed | Move to Completed table with completion timestamp |
| Task no longer needed | Any state → Cancelled | Move to Blocked/Cancelled table; record reason in task file |



### Triage to Ready Planning Phase

The transition from Triage to Ready is the **planning and clarification phase**: the critical stage where a sparse task skeleton becomes a fully-fleshed execution plan.

#### Purpose of Triage State

Tasks are created in Triage state **intentionally incomplete**:

- Quick creation captures the task concept
- Minimal information documented initially
- Placeholders for investigation and discovery
- Designed to require active planning work

**Triage is NOT a work-ready state** but rather a signal that planning must happen before execution.

#### Planning Phase Activities

During Triage → Ready transition, implementations MUST:

1. **Apply Clarification Protocol** (see [`core.md` Clarification Protocol](core.md#clarification-protocol))
   - Ask pointed questions to understand requirements
   - Clarify vague or ambiguous objectives
   - Identify specific success criteria
   - Determine scope boundaries

2. **Conduct Exploration and Reconnaissance**
   - **Quick lookups (< 30 seconds):** Manager uses direct tools (glob, grep, read)
   - **Proper reconnaissance:** Implementations MUST conduct thorough reconnaissance, delegating to exploration allies where the delegation rules require.
   - Understand existing architecture and patterns
   - Identify relevant files and modules
   - Map dependencies and relationships

3. **Populate All Task File Sections**
   - **Objective:** Clear statement of what and why
   - **Success Criteria:** Specific, measurable, testable requirements
   - **Technical Approach:** Strategy and architecture changes
   - **Risk Assessment:** Identified risks with mitigation strategies
   - **Task Breakdown:** Subtasks with dependencies and acceptance criteria
   - **Decision Log:** Document any decisions made during planning

4. **Assess and Document Risks**
   - Identify potential blockers
   - Evaluate technical complexity
   - Document dependencies on external systems
   - Plan mitigation strategies

#### Ready State Criteria

A task moves from Triage to Ready ONLY when:

- All clarifying questions have been answered
- Exploration findings are documented
- All required task file sections are populated
- Technical approach is defined and validated
- Risks are identified and mitigation planned
- Success criteria are clear and measurable
- Task breakdown is complete with acceptance criteria

#### Philosophy: Plan Before Execute

The Triage → Ready phase embodies "think first, do second":

- **Triage:** Capture the idea quickly
- **Planning Phase:** Think deeply, ask questions, explore thoroughly
- **Ready:** Clear path forward, ready for execution
- **In Progress:** Execute the plan

**A task MUST NOT move to In Progress without first being properly planned in the Triage → Ready phase.**

---

## Update Requirements

### Real-Time Updates

**Absolute Update Mandate:**
For any work done related to a task file, the task file MUST be updated immediately and thoroughly, in real time, as the work occurs. This includes actions, discoveries, decisions, status changes, and progress, with no exceptions.

It is strictly prohibited to defer, batch, or omit updates. Task files are the single, authoritative, living record for the related work. The master index dashboard must also be updated in parallel with each change, per [Index Maintenance](#index-maintenance).

Failure to update the task file for any related work is a critical conformance failure and will be treated as such.

Task files are **living documents** updated DURING work execution, not historical records written afterward.

Implementations MUST update task documentation continuously as work progresses:

- Work Log section updated AS work happens:
  - DURING agent execution: Add progress updates to Progress Log (not just at completion)
  - DURING manager work: Document findings, decisions, and actions as they occur
  - After agent reports: Record full verbatim output immediately
  - After manager activities: Document outcomes when activity concludes
- Decision Log updated AT THE MOMENT significant choices are made
- Task status updated as work progresses through phases
- Failed Approaches documented IMMEDIATELY when attempts fail
- Task status updates MUST follow [Index Maintenance](#index-maintenance) synchronization rules (single source of truth).

**Dashboard Synchronization:** The master index (`dashboard.md`) MUST be updated in parallel with task file changes. When task files are updated, the dashboard MUST reflect those changes immediately. This ensures the dashboard remains an accurate real-time view of all work in progress.

**Critical principle:** Users should be able to open a task file at ANY moment and see current work status, not outdated information.

### Verbatim Recording Requirement

Agent output MUST be recorded verbatim in the Work Log section (agent entries).

Implementations MUST NOT summarize or paraphrase agent reports.

Manager work entries (the Work Log manager-entry format in the standard task file template, [Task File Template](#task-file-template)) MUST accurately document actions, findings, and outcomes.

Full context is valuable for:

- Understanding the complete picture of discoveries
- Debugging issues that arise later
- Learning from the exploration process
- Providing accountability and traceability
- Reviewing manager's own work and decisions later

### Decision Documentation Requirement

All significant decisions MUST include:

- Alternatives considered
- Rejection reasoning for each alternative not chosen
- Tradeoffs accepted with the chosen approach

### Completion Protocol

When a task completes, implementations MUST:

1. Confirm all Task Breakdown subtasks, whether tracked inline or as child task files ([Child Task Files](#child-task-files)), are themselves Completed or Cancelled before declaring completion
2. Confirm the Simplify and Review Loop has converged (see the TDD Workflow section of the standard task file template, [Task File Template](#task-file-template)) before declaring completion
3. Capture all deferred work as new task files per [Deferred Work Capture at Closure](#deferred-work-capture-at-closure) before declaring completion
4. Update task status to "Completed"
5. Check all acceptance criteria boxes
6. Add final progress log entry with summary
7. Complete the Final Summary section
8. Update master index with completion date
9. Move task from In Progress table to Completed table in dashboard
10. Populate "Completed" and "Duration" columns in dashboard
11. Update dashboard "Last updated" timestamp

### Content Preservation

Implementations MUST NEVER delete, clear, or overwrite any previously written content in task files. Task files are cumulative records that only grow, never shrink: this preservation mandate holds across task switches, status changes, and updates.

When updating a task file, implementations MUST use append operations for new content and preserve all existing sections. The master index dashboard likewise preserves all task references; statuses update without removing any task entry.

The ONLY permissible content deletion is when a user explicitly and specifically commands it (for example, "Delete this task file", "Remove this entry", "Clear this section"). Ambiguous instructions MUST NOT trigger content deletion.

### Deferred Work Capture at Closure

This requirement applies to EVERY task closure, in Manager Mode (Solo) and Manager Mode (Delegating).

Before a task may be marked Completed, implementations MUST capture every piece of work that was identified during the task but intentionally left undone. Such work includes:

- Deferred improvements (work consciously postponed)
- Follow-up items and "nice-to-have" enhancements
- Anything discovered during the task but ruled out of scope
- Simpler-solution tradeoffs recorded per [`coding-standards.md` Simple Solution Documentation](coding-standards.md#simple-solution-documentation)

For each such item, implementations MUST:

1. Create a new task file in Triage state ([Triage to Ready Planning Phase](#triage-to-ready-planning-phase)), assigned a proper Task ID (`PREFIX-N`, see [Task ID Format](#task-id-format)) and a descriptive name, with its filename per [File Naming Convention](#file-naming-convention). Placeholder single-letter or sequential labels (for example, `A`, `B`, `C`) MUST NOT be used.
2. Register it in the master index dashboard ([Index Maintenance](#index-maintenance)).
3. Link it from the closing task's Final Summary "Remaining Work" entry.

Deferred or out-of-scope work MUST NOT survive a closure recorded only as prose, a TODO, or a Work Log note: any such work that outlives the task becomes its own task file. A task MUST NOT be marked Completed while identified deferred or out-of-scope work remains uncaptured as task files.

When a task is closed as Cancelled rather than Completed, deferred or out-of-scope work that is still desired MUST likewise be captured as new task files; work that is no longer wanted requires no capture.

---

## Question Tracking

This section provides the persistent bookkeeping that any Manager-Mode (Delegating) task file MAY use for questions and blockers. The classification and escalation **policy** is canonical in [`delegation.md` Question Batching Discipline](delegation.md#question-batching-discipline) and is not restated here. This is only the file-based artifact that records it.

A question is recorded in one of two places:

- A **Basic** question (answered autonomously per the policy) is recorded in the **Question Log** with its source, the answer, and the rationale that justified answering without interrupting the user.
- A **Significant** question (deferred per the policy) is recorded in the **Question Queue** with its source, current state, the task IDs it blocks (or "none yet"), and the user resolution once answered.

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

Permitted transitions: `Open → Self-Answered`; `Open → Queued → Blocking → Asked → Resolved`; `Queued → Asked → Resolved` (checkpoint, high rework risk, or status request); any Queued/Blocking/Asked state `→ Cancelled` with a recorded reason.

### Question Log and Queue Format

The Question Queue MUST be kept current in real time per [Real-Time Updates](#real-time-updates). Every queued question MUST end as either Resolved by the user or explicitly Cancelled with a recorded reason, never silently dropped. A question MAY be Cancelled when it becomes irrelevant (for example, when the task it blocked is itself Cancelled).

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

Violations of MUST requirements constitute conformance failures.

- Failing to keep dashboard and task files synchronized ([Index Maintenance](#index-maintenance))
- Creating task files without user request ([Creation Prohibition](#creation-prohibition))
- Summarizing agent output instead of recording verbatim ([Verbatim Recording Requirement](#verbatim-recording-requirement))
- Marking a task Completed before the Simplify and Review Loop has converged, or without documenting each loop iteration in the Work Log (the TDD Workflow section of the standard task file template, [Task File Template](#task-file-template)), is a conformance failure.
- Failure to immediately and thoroughly update associated task file for any work done related to the task (by any agent, manager, engineer, or reviewer, in any role) is a critical conformance failure with zero tolerance for exceptions.
- Deleting or overwriting previously written task file content ([Content Preservation](#content-preservation)) is a critical conformance failure with zero tolerance for exceptions.
- Fabricating an answer to a Significant question to avoid interrupting the user ([`delegation.md` Question Batching Discipline](delegation.md#question-batching-discipline)), or silently dropping a queued question ([Question Log and Queue Format](#question-log-and-queue-format)), is a conformance failure.
- Closing a task while identified deferred, follow-up, "nice-to-have", or out-of-scope work remains uncaptured as new task files ([Deferred Work Capture at Closure](#deferred-work-capture-at-closure)) is a conformance failure.

---

*This specification defines task documentation requirements for all OpenCode implementations.*
