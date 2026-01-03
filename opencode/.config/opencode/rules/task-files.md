# Task File Protocol

**Specification Document — RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## 1. Scope

This specification defines requirements for creating and managing task files during complex operations. Task files provide comprehensive documentation of work performed, decisions made, knowledge gained, bugs encountered, and progress tracking.

Task files serve multiple purposes:

- Tracking agent/allies work and conversations (Manager Mode (Delegating))
- Tracking manager's own work, findings, and decisions (Manager Mode (Solo))
- Documenting bugs discovered and resolutions
- Recording strategic decisions and their rationale
- Maintaining a complete work history for review and reference

### 1.1 Related Specifications

- `delegation.md` — Manager Mode and delegation requirements
- `execution-standards.md` — Task execution requirements and task terminology context

---

## 2. Creation Requirements

### 2.1 Creation Triggers

Task files MUST be created ONLY when:

- User explicitly requests task file creation or planning documentation
- User requests in-depth documentation of work performed, findings, or decisions 
  (e.g., "full report", "write a report", "document your findings", 
  "write up what you found", "document this investigation")
- User explicitly activates Manager Mode
- User explicitly confirms delegation at the 4+ todo item threshold

Note: Casual summary requests (e.g., "summarize", "quick summary", "recap") 
do NOT trigger task file creation. Use direct responses for these.

### 2.2 Creation Prohibition

Task files MUST NOT be created proactively without user request.

Standard todo tracking via TodoWrite is sufficient for most operations.

---

## 3. Directory Structure

### 3.1 Required Structure

When task files are required, implementations MUST use this structure:

```
Project Root/
└── .opencode/
    ├── tasks.md                              # Jira-style dashboard (stowed from ~/.config/opencode/tasks.md)
    └── tasks/
        └── YYYYMMDD-HHMM-task-description.md # Individual task files
```

### 3.2 Directory Purpose

The `.opencode/` directory keeps task management artifacts separate from project code.

This directory MAY be extended for other OpenCode artifacts (session logs, cache, etc.).

### 3.3 Gitignore Recommendation

Users SHOULD add `.opencode/` to their global gitignore:

```bash
# ~/.config/git/ignore or project .gitignore
.opencode/
```

Users MAY commit `.opencode/` selectively if task history should be preserved.

### 3.4 File Naming Convention

Individual task files MUST follow this format:

| Component | Requirement |
|-----------|-------------|
| Pattern | `YYYYMMDD-HHMM-task-description.md` |
| Date/Time | 24-hour format, local time |
| Description | Kebab-case, 3-5 words maximum |
| Example | `20241222-0710-api-auth-refactor.md` |

---

## 4. Master Index Requirements

### 4.1 Master Index Location

The master index MUST be located at `.opencode/tasks.md`.

### 4.2 Master Index Template

```markdown
# Task Board Dashboard

*Jira-style task management board. Auto-updated when task statuses change.*

## Triage

| Task | Priority | Updated |
|------|----------|---------|
| [API Auth Refactor](./tasks/20241222-0710-api-auth-refactor.md) | High | 2024-12-31 19:00 |

## Ready

| Task | Priority | Updated |
|------|----------|---------|
| [Task Name](./tasks/20241222-0710-task-name.md) | Medium | 2024-12-31 19:30 |

## In Progress

| Task | Progress | Updated | Priority |
|------|----------|---------|----------|
| [Task Name](./tasks/20241222-0710-task-name.md) | 45% | 2024-12-31 19:45 | High |

## Blocked/Cancelled

| Task | Status | Reason | Updated |
|------|--------|---------|---------|
| [Task Name](./tasks/20241222-0710-task-name.md) | Blocked | Waiting for API | 2024-12-31 19:50 |

## Completed

| Task | Completed | Duration |
|------|-----------|----------|
| [Task Name](./tasks/20241222-0710-task-name.md) | 2024-12-30 20:00 | 2d |

**Note:** Tasks are listed in chronological order (oldest completion first, newest completion last).

## Archive

| Task | Completed | Duration |
|------|-----------|----------|
| [Older Task](./tasks/20241201-0900-older-task.md) | 2024-12-01 10:00 | 1d |

**Note:** Older completed tasks moved here for record keeping. Listed chronologically (oldest first).

---

## Task Management

**Task Creation:** Quick task files created in Triage, requires exploration and fleshing out
**Triage → Ready:** Task fully fleshed out, all information collected
**Ready → In Progress:** Work begins on task
**In Progress → Completed:** Acceptance criteria met, work finished
**State Recovery:** Blocked/Cancelled tasks can return to Ready/In Progress
**Automatic Promotion:** Tasks auto-promote through lifecycle as work progresses

---

*Last updated: YYYY-MM-DD HH:MM - Auto-updated when task status changes*
```

### 4.3 Index Maintenance

**CRITICAL REQUIREMENT:** The master index (`tasks.md`) and individual task files MUST be synchronized at ALL times.

Implementations MUST update the master index (`tasks.md`) in real-time, in parallel with ANY task file modification:

- New task files are created → Update dashboard immediately
- Task status changes → Update dashboard immediately
- Task files are modified → Update "Updated" column immediately
- Work progresses → Update dashboard immediately
- Tasks move between states → Move between dashboard tables immediately
- "Last updated" timestamp → Refresh on any task movement

**Dashboard Synchronization Principle:** When you write to a task file, you MUST also write to `tasks.md` in the same operation. These are NOT separate steps — they are one synchronized action.

**Failure to maintain dashboard synchronization is a conformance failure.**

---

## 5. Task File Structure

### 5.1 Required Sections

Each task file MUST contain these sections:

1. Objective
2. Success Criteria
3. Technical Approach (with Decision Log)
4. Risk Assessment
5. Task Breakdown
6. Work Log
7. Execution Log

### 5.2 Task File Template

```markdown
# Task: [Descriptive Name]

*Created: YYYY-MM-DD HH:MM*
**Status:** Triage | Ready | In Progress | Blocked | Cancelled | Completed

## Table of Contents

1. [Objective](#1-objective)
2. [Success Criteria](#2-success-criteria)
3. [Technical Approach](#3-technical-approach)
4. [Risk Assessment](#4-risk-assessment)
5. [Task Breakdown](#5-task-breakdown)
6. [Work Log](#6-work-log)
7. [Execution Log](#7-execution-log)

---

## 1. Objective

[What we're trying to achieve and why]

**Business Value:** [Why this matters]

## 2. Success Criteria

- [ ] Specific, measurable requirement 1
- [ ] Specific, measurable requirement 2
- [ ] Specific, measurable requirement 3

## 3. Technical Approach

**Strategy:** [High-level approach]

**Architecture Changes:**

- Change 1
- Change 2

### 3.1 Decision Log

#### Decision: [Short title]

*Timestamp: YYYY-MM-DD HH:MM*

**Context:** [What problem or choice prompted this decision]

**Alternatives Considered:**

| Option | Pros | Cons |
|--------|------|------|
| **Option A: [Name]** | [Benefits] | [Drawbacks] |
| **Option B: [Name]** | [Benefits] | [Drawbacks] |
| **Option C: [Name]** | [Benefits] | [Drawbacks] |

**Rejected Alternatives:**

- **Option A rejected because:** [Specific reasoning]
- **Option C rejected because:** [Specific reasoning]

**Final Decision:** Option B — [Name]

**Rationale:** [Full explanation of why this was chosen]

---

## 4. Risk Assessment

### High Risk

- **[Risk name]**
  - *Mitigation:* [Strategy]

### Medium Risk

- **[Risk name]**
  - *Mitigation:* [Strategy]

### Low Risk

- **[Risk name]**
  - *Mitigation:* [Strategy]

## 5. Task Breakdown

### Task [PREFIX-NNN]: [Name]

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

**Progress Log Update Requirement:** For tasks expected to take >5 minutes, implementations MUST add progress updates DURING execution, not only at completion. Updates should capture:
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

## 6. Work Log

This section tracks all work performed during to task, whether by agents/allies or by the manager.

### 6.1 [Timestamp] — [Agent/Ally Name] — [Task ID or "Exploration"]

**Purpose:** [Brief description of what this agent was asked to do]

**Instructions Given:**

```
[Verbatim prompt/instructions sent to the agent]
```

**Agent Report:**

```
[Verbatim output returned by the agent — full findings, not summarized]
```

**Manager Analysis:**

[How to manager interpreted these findings, what actions were taken]

**Follow-up Actions:**

- [Action 1 triggered by this report]
- [Action 2 triggered by this report]

### 6.2 [Timestamp] — Manager — [Task ID or Activity Description]

**Activity:** [What is manager was doing - e.g., "bug investigation", "implementation", "code review", "exploration"]

**Actions Performed:**

- [Action 1 - e.g., "Read file src/auth.ts:1-50"]
- [Action 2 - e.g., "Identified null reference on line 24"]
- [Action 3 - e.g., "Applied fix: added null check"]

**Findings:**

[Objective findings - bugs discovered, patterns observed, issues encountered]

**Decisions Made:**

[Significant decisions and reasoning - decision process is IDENTICAL in both Manager Mode (Delegating) and Manager Mode (Solo)]

**Outcome:**

[Result - e.g., "Bug fixed", "Code refactored", "Issue documented"]

**Next Steps:**

[Immediate next actions or pending items]

---

## 7. Execution Log

### Project Timeline

- **YYYY-MM-DD HH:MM** - Task file created
- **YYYY-MM-DD HH:MM** - [Milestone or significant event]
- **Status:** [Current phase]
- **Next Steps:** [Immediate actions]

### Work Summary

This section summarizes all work performed, whether by agents/allies or by to manager.

| Agent/Ally/Manager | Tasks/Activities | Mode | Status | Key Contributions |
|--------------------|------------------|------|--------|-------------------|
| [Name or "Manager"] | [Task IDs or Activity IDs] | Delegating/Solo | Complete/In Progress | [What they accomplished] |

**Note:** When operating in Manager Mode (Solo), "Manager" appears as a row in this table tracking personal work execution.

### Failed Approaches

#### Attempt: [What was tried]

*Timestamp: YYYY-MM-DD HH:MM*

**Approach:** [Description of what was attempted]

**Result:** [What happened — error messages, unexpected behavior]

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

## 6. Task ID Format

### 6.1 ID Pattern

Task IDs MUST follow the pattern: `PREFIX-NNN`

### 6.2 Standard Prefixes

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

## 7. Task Lifecycle States

| State | Description |
|-------|-------------|
| **Triage** | Quick task file created, needs more information/exploration |
| **Ready** | Fully fleshed out, ready to work on |
| **In Progress** | Actively being worked on |
| **Blocked** | Cannot proceed due to external dependency |
| **Cancelled** | No longer needed |
| **Completed** | Finished successfully, acceptance criteria met |

### 7.1 Automatic State Transitions

Implementations MUST automatically transition task states when triggering events occur:

| Trigger Event | Required State Change | Dashboard Action |
|---------------|----------------------|------------------|
| Work begins on a Ready task | Ready → In Progress | Move from Ready table to In Progress table |
| Task becomes blocked | In Progress → Blocked | Move to Blocked/Cancelled table with reason |
| Blocked task can proceed | Blocked → Ready or In Progress | Move back to appropriate table |
| All acceptance criteria met | In Progress → Completed | Move to Completed table with completion timestamp |
| Task no longer needed | Any state → Cancelled | Move to Blocked/Cancelled table with reason |

**Critical Rule:** When an implementation or agent begins work on a task in Ready state, that task MUST immediately transition to In Progress in both the task file AND the dashboard.

### 7.2 Triage to Ready Planning Phase

The transition from Triage to Ready is the **planning and clarification phase** — the critical stage where a sparse task skeleton becomes a fully-fleshed execution plan.

#### Purpose of Triage State

Tasks are created in Triage state **intentionally incomplete**:

- Quick creation captures the task concept
- Minimal information documented initially
- Placeholders for investigation and discovery
- Designed to require active planning work

**Triage is NOT a work-ready state** — it is a signal that planning must happen before execution.

#### Planning Phase Activities

During Triage → Ready transition, implementations MUST:

1. **Apply Clarification Protocol** (see `core.md` Section 3.1)
   - Ask pointed questions to understand requirements
   - Clarify vague or ambiguous objectives
   - Identify specific success criteria
   - Determine scope boundaries

2. **Conduct Exploration and Reconnaissance**
   - **Quick lookups (< 30 seconds):** Manager uses direct tools (glob, grep, read)
   - **Proper reconnaissance:** Delegate to exploration allies (see persona for ally details)
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

**No task should move to In Progress without first being properly planned in the Triage → Ready phase.**

---

## 8. Update Requirements

### 8.1 Real-Time Updates

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
- Dashboard tables updated in real-time when task status changes
- "Last updated" timestamp in dashboard refreshed on any task movement
- Task moved between dashboard tables automatically (no directory moves)
- "Updated" column updated whenever task file is modified

**Dashboard Synchronization:** The master index (`tasks.md`) MUST be updated in parallel with task file changes. When task files are updated, the dashboard MUST reflect those changes immediately. This ensures the dashboard remains an accurate real-time view of all work in progress.

**Critical principle:** Users should be able to open a task file at ANY moment and see current work status, not outdated information.

### 8.2 Verbatim Recording Requirement

Agent output MUST be recorded verbatim in the Work Log section (agent entries).

Implementations MUST NOT summarize or paraphrase agent reports.

Manager work entries (Section 6.2) MUST accurately document actions, findings, and outcomes.

Full context is valuable for:

- Understanding the complete picture of discoveries
- Debugging issues that arise later
- Learning from the exploration process
- Providing accountability and traceability
- Reviewing manager's own work and decisions later

### 8.3 Decision Documentation Requirement

All significant decisions MUST include:

- Alternatives considered
- Rejection reasoning for each alternative not chosen
- Tradeoffs accepted with the chosen approach

### 8.4 Completion Protocol

When a task completes, implementations MUST:

1. Update task status to "Completed"
2. Check all acceptance criteria boxes
3. Add final progress log entry with summary
4. Complete the Final Summary section
5. Update master index with completion date
6. Move task from In Progress table to Completed table in dashboard
7. Populate "Completed" and "Duration" columns in dashboard
8. Update dashboard "Last updated" timestamp

---

## 9. Conformance

Violations of MUST requirements constitute conformance failures.

Creating task files without user request (Section 2.2) is a conformance failure.

Summarizing agent output instead of recording verbatim (Section 8.2) is a conformance failure.

---

*This specification defines task documentation requirements for all OpenCode implementations.*
