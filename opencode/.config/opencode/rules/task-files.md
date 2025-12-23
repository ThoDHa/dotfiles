# Task File Management Protocol

**RFC 2119 Compliant**

This document specifies requirements for creating and managing task files during complex operations.

---

## 1. When to Create Task Files

Task files SHALL only be created when:
- User **explicitly requests** task file creation or planning documentation
- User **explicitly activates** Manager Mode with commands like "act as manager" or "there is a big task ahead"
- User **explicitly confirms** delegation when prompted at the 4+ todo item threshold

Task files MUST NOT be created proactively without user request. Standard todo tracking via TodoWrite is sufficient for most operations.

---

## 2. Directory Structure

When task files are required, implementations SHALL use this structure:

```
Project Root:
└── .opencode/
    ├── tasks.md                              # Master index/tracker
    └── tasks/
        ├── YYYYMMDD-HHMM-task-description.md # Individual task files
        └── [additional task files...]
```

The `.opencode/` directory keeps task management artifacts separate from project code. This directory MAY be extended in the future for other OpenCode artifacts (session logs, cache, etc.).

### 2.1 Gitignore Recommendation

Users SHOULD add `.opencode/` to their global gitignore to prevent task files from polluting repository history:

```bash
# Add to ~/.config/git/ignore (global) or project .gitignore
.opencode/
```

Alternatively, if task history should be preserved with the project, users MAY commit `.opencode/` selectively.

### 2.2 Naming Convention

Individual task files MUST follow this format:
- **Pattern:** `YYYYMMDD-HHMM-task-description.md`
- **Date/Time:** Use 24-hour format, local time
- **Description:** Kebab-case, 3-5 words maximum
- **Example:** `20241222-0710-api-auth-refactor.md`

---

## 3. Master Index Template

The master index file (`.opencode/tasks.md`) tracks all task files:

```markdown
# Task Management Dashboard

*Master index for all task management operations. Auto-updated when new task files are created.*

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

---

## 4. Individual Task File Template

Each task file MUST be structured as a complete record of work performed:

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

What we're trying to achieve and why.

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

Record all significant decisions with full reasoning:

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

**Rationale:** [Full explanation of why this was chosen, what tradeoffs were accepted]

---

*[Repeat Decision section for each significant decision]*

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
Detailed description of what needs to be done.

#### Acceptance Criteria
- [ ] Specific requirement 1
- [ ] Specific requirement 2

#### Progress Log
- [Timestamp] Started by [Agent identifier]
- [Timestamp] Update: [Progress description]
- [Timestamp] Completed: [Results summary]

---

*[Repeat Task section for each task]*

---

## 6. Agent Conversations

This section captures the full dialogue between the manager and delegated agents/allies, in chronological order. This provides complete context for understanding what was explored, what was found, and how work was executed.

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
[How the manager interpreted these findings, what was learned, what actions were taken as a result]

**Follow-up Actions:**
- [Action 1 triggered by this report]
- [Action 2 triggered by this report]

---

### 6.2 [Timestamp] — [Agent/Ally Name] — [Task ID]

**Purpose:** [Brief description]

**Instructions Given:**
```
[Verbatim prompt]
```

**Agent Report:**
```
[Verbatim output]
```

**Manager Analysis:**
[Interpretation and next steps]

---

*[Continue chronologically for all agent interactions]*

---

## 7. Execution Log

### Project Timeline
- **YYYY-MM-DD HH:MM** - Task file created, project initiated
- **YYYY-MM-DD HH:MM** - [Milestone or significant event]
- **YYYY-MM-DD HH:MM** - [Milestone or significant event]
- **Status:** [Current phase]
- **Next Steps:** [Immediate actions]

### Agent Summary

| Agent/Ally | Tasks Assigned | Status | Key Contributions |
|------------|----------------|--------|-------------------|
| [Name] | [Task IDs] | Complete/In Progress | [What they accomplished] |

### Failed Approaches

Document approaches that were tried but didn't work:

#### Attempt: [What was tried]
*Timestamp: YYYY-MM-DD HH:MM*

**Approach:** [Description of what was attempted]

**Result:** [What happened — error messages, unexpected behavior, etc.]

**Why It Failed:** [Analysis of root cause]

**Lessons Learned:** [What this taught us, how it informed the successful approach]

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

---

*This task file provides a complete record of work performed, decisions made, and knowledge gained.*
```

---

## 5. Task ID Format

Task IDs follow a prefix-number pattern for easy reference:

| Prefix | Meaning | Example |
|--------|---------|---------|
| `AUTH` | Authentication-related | `AUTH-001` |
| `API` | API endpoints | `API-002` |
| `UI` | User interface | `UI-003` |
| `TEST` | Testing tasks | `TEST-004` |
| `DOCS` | Documentation | `DOCS-005` |
| `INFRA` | Infrastructure | `INFRA-006` |
| `TASK` | Generic tasks | `TASK-007` |
| `EXPLORE` | Exploration/discovery | `EXPLORE-008` |

Custom prefixes MAY be used when they improve clarity.

---

## 6. Task Lifecycle States

| State | Description |
|-------|-------------|
| **Pending** | Not yet started, awaiting assignment or dependencies |
| **In Progress** | Actively being worked on |
| **Completed** | Successfully finished, acceptance criteria met |
| **Blocked** | Cannot proceed due to external dependency or issue |
| **Cancelled** | No longer needed, will not be completed |
| **Deferred** | Postponed to future date or phase |

---

## 7. Update Protocol

### 7.1 Real-time Updates

Implementations MUST update task documentation in real-time:
- Agent Conversations section updated immediately when agents report back
- Decision Log updated when significant choices are made
- Task status updated as work progresses
- Failed Approaches documented when attempts don't succeed

### 7.2 Verbatim Recording

Agent output MUST be recorded verbatim in the Agent Conversations section. Do not summarize or paraphrase agent reports — the full context is valuable for:
- Understanding the complete picture of what was discovered
- Debugging issues that arise later
- Learning from the exploration process
- Providing accountability and traceability

### 7.3 Decision Documentation

All significant decisions MUST include:
- **Alternatives considered** — what other options were evaluated
- **Rejection reasoning** — why alternatives were not chosen
- **Tradeoffs accepted** — what downsides of the chosen approach were acknowledged

### 7.4 Completion Protocol

When a task completes:
1. Update task status to "Completed"
2. Check all acceptance criteria boxes
3. Add final progress log entry with summary
4. Complete the Final Summary section
5. Update master index with completion date

---

*This protocol ensures complete documentation of complex operations, preserving the full context of exploration, decisions, and execution for future reference.*
