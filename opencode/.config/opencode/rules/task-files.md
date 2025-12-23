# Task File Protocol

**Specification Document — RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## 1. Scope

This specification defines requirements for creating and managing task files during complex operations. Task files provide comprehensive documentation of work performed, decisions made, and knowledge gained.

### 1.1 Related Specifications

- `delegation.md` — Manager Mode and delegation requirements
- `execution-standards.md` — Task execution requirements

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
    ├── tasks.md                              # Master index
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
# Task Management Dashboard

*Master index for all task management operations.*

## Active Tasks

| Task File | Status | Created | Progress | Priority |
|-----------|--------|---------|----------|----------|
| [Task Name](./tasks/YYYYMMDD-HHMM-task-name.md) | Status | YYYY-MM-DD HH:MM | 0% | High |

## Completed Tasks

| Task File | Completed | Duration | Final Status |
|-----------|-----------|----------|--------------|
| *No completed tasks yet* | - | - | - |

---

*Last updated: YYYY-MM-DD HH:MM*
```

### 4.3 Index Maintenance

Implementations MUST update the master index when:

- New task files are created
- Task status changes
- Tasks are completed

---

## 5. Task File Structure

### 5.1 Required Sections

Each task file MUST contain these sections:

1. Objective
2. Success Criteria
3. Technical Approach (with Decision Log)
4. Risk Assessment
5. Task Breakdown
6. Agent Conversations
7. Execution Log

### 5.2 Task File Template

```markdown
# Task: [Descriptive Name]

*Created: YYYY-MM-DD HH:MM*

## Table of Contents

1. [Objective](#1-objective)
2. [Success Criteria](#2-success-criteria)
3. [Technical Approach](#3-technical-approach)
4. [Risk Assessment](#4-risk-assessment)
5. [Task Breakdown](#5-task-breakdown)
6. [Agent Conversations](#6-agent-conversations)
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

**Status:** Pending | In Progress | Completed | Blocked | Cancelled | Deferred
**Priority:** High | Medium | Low
**Dependencies:** [Other task IDs or "None"]
**Assigned To:** [Agent/Ally name or "Unassigned"]

#### Description

[Detailed description of what needs to be done]

#### Acceptance Criteria

- [ ] Specific requirement 1
- [ ] Specific requirement 2

#### Progress Log

- [Timestamp] Started by [Agent identifier]
- [Timestamp] Update: [Progress description]
- [Timestamp] Completed: [Results summary]

---

## 6. Agent Conversations

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

[How the manager interpreted these findings, what actions were taken]

**Follow-up Actions:**

- [Action 1 triggered by this report]
- [Action 2 triggered by this report]

---

## 7. Execution Log

### Project Timeline

- **YYYY-MM-DD HH:MM** - Task file created
- **YYYY-MM-DD HH:MM** - [Milestone or significant event]
- **Status:** [Current phase]
- **Next Steps:** [Immediate actions]

### Agent Summary

| Agent/Ally | Tasks Assigned | Status | Key Contributions |
|------------|----------------|--------|-------------------|
| [Name] | [Task IDs] | Complete/In Progress | [What they accomplished] |

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
| **Pending** | Not yet started, awaiting assignment or dependencies |
| **In Progress** | Actively being worked on |
| **Completed** | Successfully finished, acceptance criteria met |
| **Blocked** | Cannot proceed due to external dependency |
| **Cancelled** | No longer needed |
| **Deferred** | Postponed to future phase |

---

## 8. Update Requirements

### 8.1 Real-Time Updates

Implementations MUST update task documentation in real-time:

- Agent Conversations section updated immediately when agents report
- Decision Log updated when significant choices are made
- Task status updated as work progresses
- Failed Approaches documented when attempts fail

### 8.2 Verbatim Recording Requirement

Agent output MUST be recorded verbatim in the Agent Conversations section.

Implementations MUST NOT summarize or paraphrase agent reports.

Full context is valuable for:

- Understanding the complete picture of discoveries
- Debugging issues that arise later
- Learning from the exploration process
- Providing accountability and traceability

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

---

## 9. Conformance

Violations of MUST requirements constitute conformance failures.

Creating task files without user request (Section 2.2) is a conformance failure.

Summarizing agent output instead of recording verbatim (Section 8.2) is a conformance failure.

---

*This specification defines task documentation requirements for all OpenCode implementations.*
