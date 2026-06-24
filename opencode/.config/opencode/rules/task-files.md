# Task File Protocol

**Specification Document: RFC 2119 Terminology**

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

- [`delegation.md`](delegation.md): Manager Mode and delegation requirements
- [`execution-standards.md`](execution-standards.md): Task execution requirements and task terminology context

### 1.2 Tone and Voice Policy

- All sections MUST use professional, formal tone with no character voice, per [core.md Section 5.1](core.md#51-formal-output-standards).
- Exceptions:
  - 6.1 Agent Report: record verbatim, regardless of tone.
  - 6.2 Manager entry: MAY use informal conversational tone appropriate to ongoing work updates while remaining factual and objective.
- Execution Log, Objective, Success Criteria, Technical Approach, Risk Assessment, Dependencies and Prerequisites, Testing Strategy, Rollback and Recovery Plan, Communication Plan, Post-Completion Actions, Task Breakdown MUST remain formal.

---

## 2. Creation Rules

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

| Task | Progress | What Was Done | Updated | Priority |
|------|----------|---------------|---------|----------|
| [Task Name](./tasks/20241222-0710-task-name.md) | 45% | Token refresh wired up; session store integration pending | 2024-12-31 19:45 | High |

**Note:** "What Was Done" is a concise snapshot of the current state, overwritten on each update. It MUST NOT be a running list of every change.

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

**Coordination task files** ([Section 9](#9-coordination-task-files)) appear in these same tables, distinguished by a `[COORD]` prefix on the task name. Their "What Was Done" snapshot summarizes child-task rollup (for example, `4/7 child tasks complete, 2 questions queued`).

### 4.3 Index Maintenance

The master index (`tasks.md`) and individual task files MUST remain synchronized at all times. Update both in a single atomic operation whenever task documentation changes.

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
| Work progresses | Update progress percentage and overwrite the "What Was Done" snapshot in dashboard (if In Progress) |
| Task moves between states | Move row to new table + update all relevant columns |
| Task completed | Move to Completed table + populate "Completed" and "Duration" columns |
| Task blocked/cancelled | Move to Blocked/Cancelled table + add "Reason" column |
| ANY task file write | Update dashboard "Last updated" timestamp |

---

## 5. Task File Structure

### 5.1 Required Sections

Each task file MUST contain these sections, numbered as they appear within the standard task file template in [Section 5.2](#52-task-file-template) (these numbers are internal to the template, not trunk section numbers of this specification):

1. Objective
2. Success Criteria
3. Technical Approach (with Decision Log)
4. Risk Assessment
5. Dependencies and Prerequisites
6. Testing Strategy
7. TDD Workflow
8. Rollback and Recovery Plan
9. Communication Plan
10. Post-Completion Actions
11. Task Breakdown
12. Work Log
13. Execution Log

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
5. [Dependencies and Prerequisites](#5-dependencies-and-prerequisites)
6. [Testing Strategy](#6-testing-strategy)
7. [TDD Workflow](#7-tdd-workflow)
8. [Rollback and Recovery Plan](#8-rollback-and-recovery-plan)
9. [Communication Plan](#9-communication-plan)
10. [Post-Completion Actions](#10-post-completion-actions)
11. [Task Breakdown](#11-task-breakdown)
12. [Work Log](#12-work-log)
13. [Execution Log](#13-execution-log)

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

**Files to Review:**

*Critical files that must be examined to complete this task. This provides a roadmap for anyone working on the task.*

- `src/path/to/critical-file.ts` - [Brief description of why this file is important]
- `config/settings.json` - [Configuration that affects the task]
- `tests/related-test.spec.js` - [Tests that need to be updated or provide context]
- `docs/api-documentation.md` - [Documentation that needs updating]

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

**Final Decision:** Option B: [Name]

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

## 5. Dependencies and Prerequisites

### External Dependencies

**System Dependencies:**
- [External API/service name] - [Why needed, what functionality depends on it]
- [Database/data source] - [Access requirements, data needed]
- [Third-party service] - [Integration points, reliability concerns]

**Tool Requirements:**
- [Specific tool] version X.Y.Z or higher - [Why this version is required]
- [Configuration requirement] - [Specific setup needed]
- [Access permissions] - [What level of access is needed where]

### Knowledge Prerequisites

**Domain Expertise Required:**
- [Subject area] - [Level of expertise needed, who has this knowledge]
- [Technical skill] - [Specific knowledge areas that will be essential]
- [Business context] - [Domain understanding required for good decisions]

**Learning Resources:**
- [Documentation/guide] - [Key resources for getting up to speed]
- [Expert contact] - [Who to consult for domain questions]
- [Previous related work] - [Past projects/tasks that provide context]

### Environmental Prerequisites

**Development Environment:**
- [Specific setup requirements]
- [Local dependencies that must be installed]
- [Configuration files that must be present]

**Access Requirements:**
- [Systems that must be accessible]
- [Credentials/permissions needed]
- [VPN/network access requirements]

## 6. Testing Strategy

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

## 7. TDD Workflow

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

### TDD Decision Points

**When Tests Already Exist:**
- If existing tests cover the functionality: Update tests to match new expected behavior
- If tests need extension: Add new test cases for edge cases and requirements
- If tests are obsolete: Document deprecation and replace with new tests

**When No Tests Exist:**
- Write tests that define expected behavior BEFORE any implementation
- Focus on testing public interfaces and critical paths
- Include edge cases, error conditions, and boundary values
- Document why tests couldn't be written (if applicable) for future reference

**When Test Execution Fails:**
- Determine if failure is due to environment, dependencies, or test code
- Fix infrastructure issues before proceeding with implementation
- Document infrastructure problems and resolutions
- Do not proceed to implementation if test infrastructure is broken

### TDD Work Log Entry Format

When following TDD workflow, Work Log entries MUST include:

**Example TDD Work Log Entry:**

```
[Timestamp] TDD Phase 1: Check Existing Tests
- Command: `npm test` / `pytest` / [test command]
- Result: [X] passing, [Y] failing
- Failing tests: [list test names/IDs]

[Timestamp] TDD Phase 2: Update Tests
- File modified: `tests/example.test.js`
- Changes: Added test case [name] to verify [behavior]
- Expected behavior: [description of what should happen]

[Timestamp] TDD Phase 3: Verify Tests Fail
- Command: `npm test` / [test command]
- Result: [X] passing, [Y] failing (including new test)
- Failure message: [specific error confirming test works]

[Timestamp] TDD Phase 4: Implement Solution
- File modified: `src/example.js`
- Changes: [description of implementation]

[Timestamp] TDD Phase 5: Verify Tests Pass
- Command: `npm test` / [test command]
- Result: All tests passing
- Coverage: [X]% (if measured)
```

### TDD Exceptions and Edge Cases

**Exceptions Requiring Documented Justification:**

Implementations MAY deviate from TDD workflow ONLY when:

- **Emergency Hotfixes:** Document the production fix, THEN write regression tests
- **Exploratory Work:** When behavior is unknown, write tests after understanding system
- **Infrastructure Changes:** When no production code changes (only test infrastructure)
- **External API Integration:** When external dependencies prevent test-first approach

**Exception Documentation Requirement:**

When deviating from TDD workflow, implementions MUST:
1. Document the exception in the Work Log with justification
2. Explain why TDD workflow couldn't be followed
3. Document when tests will be written (if deferred)
4. Get explicit approval if the exception is significant

**Example Exception Entry:**

```
[Timestamp] TDD Exception: Emergency Production Hotfix
- Justification: Production outage requires immediate fix, cannot run tests in prod
- Action: Applied fix to [file], deferring tests to follow-up
- Follow-up required: Write regression tests for this fix within 24 hours
```

### TDD Integration with Task Lifecycle

**Ready → In Progress Transition Requirements:**

Before transitioning to In Progress, task file MUST have:
- [ ] Test command identified (how to run tests)
- [ ] Test framework documented
- [ ] Test file locations identified
- [ ] Existing test baseline recorded

**In Progress Work Execution:**

All work MUST follow TDD sequence documented in Section 7. Work Log MUST track each phase with timestamps and results.

**Completion Validation:**

Task CANNOT be marked Completed unless:
- All tests pass (including newly written tests)
- Test coverage meets or exceeds target percentage (if specified)
- TDD workflow is documented in Work Log
- No TDD exceptions exist without justification and follow-up plan
- The Simplify and Review Loop has converged (a full iteration produced no fixes), or the iteration cap was reached and outstanding findings were documented and accepted by the user
- Each loop iteration is documented in the Work Log

## 8. Rollback and Recovery Plan

### Rollback Strategy

**Rollback Triggers:**
- [Specific conditions that would require rollback]
- [Performance degradation thresholds]
- [Error rate increases beyond X%]
- [User-reported issues of type Y]

**Rollback Procedure:**

1. **Immediate Actions:**
   - [Step 1: Immediate safety measures]
   - [Step 2: Traffic/load management]
   - [Step 3: System state preservation]

2. **Rollback Steps:**
   - [Step 1: Reverse code changes]
   - [Step 2: Database rollback (if needed)]
   - [Step 3: Configuration restoration]
   - [Step 4: Cache clearing/reset]

3. **Verification Steps:**
   - [Step 1: Functionality verification]
   - [Step 2: Performance verification]
   - [Step 3: Data integrity checks]

### Data Protection

**Backup Requirements:**
- [What data needs backup before changes]
- [Backup procedure and location]
- [Recovery testing requirements]

**Data Migration Safety:**
- [Reversible migration strategy]
- [Data validation procedures]
- [Rollback data requirements]

### Recovery Procedures

**System Recovery:**
- [Steps to restore system functionality]
- [Dependencies that need restoration]
- [Monitoring to confirm recovery]

**Communication During Incidents:**
- [Who to notify immediately]
- [Escalation procedures]
- [User communication requirements]

## 9. Communication Plan

### Stakeholder Notifications

**Pre-Work Communications:**

| Stakeholder Group | Notification Method | Timeline | Information Needed |
|-------------------|---------------------|----------|-------------------|
| [Team/Department] | [Email/Slack/Meeting] | [X days before] | [What they need to know] |
| [End Users] | [Communication channel] | [Timeline] | [Impact information] |
| [Leadership] | [Method] | [When] | [Business impact summary] |

**During-Work Communications:**
- [Progress update schedule and recipients]
- [Issue escalation procedures]
- [Status communication channels]

**Post-Work Communications:**
- [Completion notifications and recipients]
- [Results summary requirements]
- [Follow-up meeting needs]

### Documentation Updates

**Internal Documentation:**
- [System documentation to update]
- [Process documentation changes]
- [Knowledge base updates]

**External Documentation:**
- [User-facing documentation]
- [API documentation updates]
- [Public-facing change logs]

### Knowledge Transfer

**Team Knowledge Sharing:**
- [What knowledge needs to be shared]
- [Knowledge transfer sessions required]
- [Documentation handoffs needed]

## 10. Post-Completion Actions

### Immediate Follow-Up (Within 24-48 hours)

**Monitoring Requirements:**
- [Specific metrics to watch]
- [Duration of intensive monitoring]
- [Alert thresholds to set]
- [Who is responsible for monitoring]

**Validation Steps:**
- [ ] Functionality verification in production
- [ ] Performance baseline confirmation
- [ ] User acceptance validation (if applicable)
- [ ] Integration points verification

### Short-Term Follow-Up (1-2 weeks)

**Performance Review:**
- [Metrics to evaluate after initial period]
- [Success criteria validation]
- [User feedback collection]

**Process Improvements:**
- [Lessons learned documentation]
- [Process refinements identified]
- [Tool/workflow improvements needed]

### Long-Term Actions

**Future Work Identification:**
- [Related work that should be scheduled]
- [Technical debt items created/resolved]
- [Optimization opportunities identified]

**Knowledge Documentation:**
- [Best practices to document]
- [Pitfalls to record for future reference]
- [Reusable components/patterns created]

### Success Metrics Review

**Quantitative Measures:**
- [Performance improvements achieved]
- [Error rate changes]
- [User adoption metrics (if applicable)]

**Qualitative Measures:**
- [Team feedback on changes]
- [User satisfaction impacts]
- [Development workflow improvements]

## 11. Task Breakdown

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

## 12. Work Log

This section tracks all work performed during the task, whether by agents/allies or by the manager. Tone note: Work Log entries follow the exception in Section 1.2.

### 6.1 [Timestamp]: [Agent/Ally Name]: [Task ID or "Exploration"]

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

### 6.2 [Timestamp]: Manager: [Task ID or Activity Description]

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

## 7. Execution Log

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
| `COORD` | Coordination task file orchestrating multiple task files ([Section 9](#9-coordination-task-files)) |

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
| All acceptance criteria met AND Simplify and Review Loop converged | In Progress → Completed | Move to Completed table with completion timestamp |
| Task no longer needed | Any state → Cancelled | Move to Blocked/Cancelled table with reason |



### 7.2 Triage to Ready Planning Phase

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

1. **Apply Clarification Protocol** (see [`core.md` Section 3.1](core.md#31-clarification-protocol))
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

## 8. Update Requirements

### 8.1 Real-Time Updates

**Absolute Update Mandate:**
For any work done related to a task file, the task file MUST be updated immediately and thoroughly, in real time, as the work occurs. This includes actions, discoveries, decisions, status changes, and progress, with no exceptions.

It is strictly prohibited to defer, batch, or omit updates. Task files are the single, authoritative, living record for the related work. The master index dashboard must also be updated in parallel with each change, per [Section 4.3](#43-index-maintenance).

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
- Task status updates MUST follow [Section 4.3](#43-index-maintenance) synchronization rules (single source of truth).

**Dashboard Synchronization:** The master index (`tasks.md`) MUST be updated in parallel with task file changes. When task files are updated, the dashboard MUST reflect those changes immediately. This ensures the dashboard remains an accurate real-time view of all work in progress.

**Critical principle:** Users should be able to open a task file at ANY moment and see current work status, not outdated information.

### 8.2 Verbatim Recording Requirement

Agent output MUST be recorded verbatim in the Work Log section (agent entries).

Implementations MUST NOT summarize or paraphrase agent reports.

Manager work entries (the Work Log manager-entry format in the standard task file template, [Section 5.2](#52-task-file-template)) MUST accurately document actions, findings, and outcomes.

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

1. Confirm the Simplify and Review Loop has converged (see the TDD Workflow section of the standard task file template, [Section 5.2](#52-task-file-template)) before declaring completion
2. Capture all deferred work as new task files per [Section 8.6](#86-deferred-work-capture-at-closure) before declaring completion
3. Update task status to "Completed"
4. Check all acceptance criteria boxes
5. Add final progress log entry with summary
6. Complete the Final Summary section
7. Update master index with completion date
8. Move task from In Progress table to Completed table in dashboard
9. Populate "Completed" and "Duration" columns in dashboard
10. Update dashboard "Last updated" timestamp

### 8.5 Content Preservation

**Absolute Preservation Mandate:**

Implementations MUST NEVER delete, clear, or overwrite any previously written content in task files. Task files are cumulative records that only grow, never shrink.

**Prohibited Operations:**

- **NEVER** delete Work Log entries when switching tasks or contexts
- **NEVER** clear Decision Log entries
- **NEVER** overwrite Task Breakdown sections
- **NEVER** remove completed Progress Log entries
- **NEVER** reset task file content when moving between tasks
- **NEVER** use file write operations that replace entire content

**Required Operations:**

- **ALWAYS** use append operations for new content
- **ALWAYS** preserve all existing sections when updating
- **ALWAYS** maintain chronological order of Work Log entries
- **ALWAYS** keep all historical decisions in Decision Log
- **ALWAYS** maintain completed task information even when switching focus

**Multi-Task Scenarios:**

When working on multiple tasks sequentially:

1. **Task Switching:** Switching between tasks MUST NOT affect previously written content in other task files
2. **Context Preservation:** Each task file's content remains intact regardless of which task is currently active
3. **Dashboard Accuracy:** Master index MUST accurately reflect state of ALL tasks, not just the active one
4. **Work Continuity:** When returning to a task, all previous work MUST be present and accessible

**Task File Update Pattern:**

When updating a task file, implementations MUST:

```markdown
## 12. Work Log

### 12.1 [Timestamp]: Manager: Task AUTH-001

**Activity:** Authentication flow investigation

[Content written for AUTH-001]

### 12.2 [Timestamp]: Manager: Task AUTH-002

**Activity:** Token refresh implementation

[Content written for AUTH-002 - AUTH-001 content above MUST be preserved]
```

**Prohibited Update Pattern:**

```markdown
## 12. Work Log

### 12.1 [Timestamp]: Manager: Task AUTH-002

**Activity:** Token refresh implementation

[ONLY AUTH-002 content - AUTH-001 content DELETED - PROHIBITED]
```

**Verification Requirements:**

Before and after any task file update, implementations MUST verify:

- [ ] All previous Work Log entries remain present
- [ ] All Decision Log entries remain present
- [ ] Task Breakdown sections remain intact
- [ ] Progress Log entries preserve chronological history
- [ ] No sections have been removed or truncated

**Dashboard Synchronization:**

When updating master index:

- [ ] All task files represented in dashboard remain listed
- [ ] No task entries removed from dashboard tables
- [ ] Task statuses update WITHOUT removing task references
- [ ] All task information preserved regardless of active task

**Failure to Preserve Content:**

Any deletion of previously written task file content is a critical conformance failure. This includes:

- Intentional deletion (prohibited)
- Accidental deletion due to poor file handling (prohibited)
- Deletion when switching between tasks (prohibited)
- Deletion when updating content (prohibited)
- Deletion during task transitions (prohibited)

**Exception: Explicit User Command:**

The ONLY permissible content deletion is when a user explicitly commands it:

- "Delete this task file"
- "Remove this entry"
- "Clear this section"

User requests MUST be explicit and specific. Ambiguous instructions must NOT trigger content deletion.

### 8.6 Deferred Work Capture at Closure

This requirement applies to EVERY task closure, in both standard and coordination task files, in Manager Mode (Solo) and Manager Mode (Delegating).

Before a task may be marked Completed, implementations MUST capture every piece of work that was identified during the task but intentionally left undone. Such work includes:

- Deferred improvements (work consciously postponed)
- Follow-up items and "nice-to-have" enhancements
- Anything discovered during the task but ruled out of scope
- Simpler-solution tradeoffs recorded per [`coding-standards.md` Section 11.2](coding-standards.md#112-simple-solution-documentation)

For each such item, implementations MUST:

1. Create a new task file in Triage state ([Section 7.2](#72-triage-to-ready-planning-phase)), named per [Section 3.4](#34-file-naming-convention).
2. Register it in the master index dashboard ([Section 4.3](#43-index-maintenance)).
3. Link it from the closing task's Final Summary "Remaining Work" entry.

Deferred or out-of-scope work MUST NOT survive a closure recorded only as prose, a TODO, or a Work Log note: any such work that outlives the task becomes its own task file. A task MUST NOT be marked Completed while identified deferred or out-of-scope work remains uncaptured as task files.

When a task is closed as Cancelled rather than Completed, deferred or out-of-scope work that is still desired MUST likewise be captured as new task files; work that is no longer wanted requires no capture.

---

## 9. Coordination Task Files

### 9.1 Definition and Purpose

A **coordination task file** is a specialized task file whose unit of work is *other task files*. Where a standard task file documents and executes a single coherent task (with subtasks in its Task Breakdown), a coordination task file orchestrates a set of related, independently-tracked task files toward a shared objective (an epic, a multi-part feature, a migration, a release).

| Aspect | Standard Task File | Coordination Task File |
|--------|--------------------|------------------------|
| Unit of work | One task | A set of task files |
| Execution | Work performed within the file | No implementation performed within the file; work happens in child task files |
| Role | Worker or Manager (Solo) | Manager (Delegating, parallel) only |
| Lifespan | One task's lifecycle | Spans the lifecycle of all coordinated tasks |
| Primary output | Completed task and logs | Dispatch decisions, integration, follow-ups, resolved questions |

A coordination task file MUST NOT contain implementation work. Its responsibilities are dispatching work to child tasks, monitoring their progress, integrating their results, creating follow-up tasks, and handling questions ([Section 9.8](#98-question-handling-protocol)).

### 9.2 Operating Mode

A coordination task file MUST operate in **Manager Mode (Delegating - parallel)** as defined in [`delegation.md`](delegation.md).

The coordinator MUST:

- Dispatch parallel agents/allies to child tasks, subject to the safety requirements in [`delegation.md` Section 5](delegation.md#5-safety-requirements) (file-conflict prevention, dependency sequencing, boundary isolation, pre-dispatch verification).
- Prefer allies over agents per [`delegation.md` Section 4.4](delegation.md#44-ally-preference-requirement).
- Restrict its own direct action to the exceptions in [`delegation.md` Section 4.2](delegation.md#42-direct-execution-exceptions) (quick tasks under 30 seconds, planning, coordination, synthesis, user communication) and failure takeover per [`delegation.md` Section 7.2](delegation.md#72-failure-takeover).

If the user declares no parallel resources are available, the effort MUST be run as standard Manager Mode (Solo) task files instead. A coordination task file is not appropriate without parallel delegation.

### 9.3 Creation Triggers

In addition to the standard triggers in [Section 2.1](#21-creation-triggers), a coordination task file MUST be created when ALL of the following hold:

- The user has activated Manager Mode (Delegating - parallel), AND
- The effort decomposes into two or more independent child task files, AND
- Those task files benefit from orchestration (shared objective, ordering dependencies, or a shared integration point).

A coordination task file MUST NOT be created for a single task. Use a standard task file with a Task Breakdown section instead.

### 9.4 Naming and Identification

| Component | Requirement |
|-----------|-------------|
| File name | `YYYYMMDD-HHMM-coord-<description>.md` |
| Coordination ID prefix | `COORD` (e.g., `COORD-001`) |
| Child task files | Retain their own names and IDs (see File Naming Convention and Task ID Format); referenced by relative link from the coordination file |

A coordination ID MUST NOT be reused as a child task ID. Child tasks keep their domain prefixes (AUTH, API, and similar).

### 9.5 Required Sections

A coordination task file MUST contain:

1. Objective (the shared goal across all coordinated tasks)
2. Success Criteria (program-level, measured by child task completion plus integration)
3. Child Task Registry ([Section 9.6](#96-child-task-registry))
4. Coordination Strategy and Decision Log
5. Coordination Loop and Execution Waves ([Section 9.7](#97-coordination-loop-and-execution-waves))
6. Question Queue and Question Log ([Section 9.8](#98-question-handling-protocol))
7. Follow-up Tracking ([Section 9.9](#99-follow-up-task-creation))
8. Work Log (coordinator dispatch and integration entries)
9. Execution Log

Sections shared with the standard template (Objective, Success Criteria, Decision Log, Work Log, Execution Log) follow the same rules as the standard Task File Structure ([Section 5](#5-task-file-structure)).

### 9.6 Child Task Registry

The coordination file MUST maintain a registry of every coordinated task file. The registry is the authoritative map of the program and MUST be updated whenever a child task is added, changes state, or completes.

| Field | Description |
|-------|-------------|
| Task | Linked name of the child task file |
| ID | Child task ID (e.g., AUTH-001) |
| Status | Child lifecycle state (see Task Lifecycle States) |
| Depends On | Child task IDs that must complete first, or "None" |
| Wave | Dispatch wave or batch number |
| Assigned | Ally/agent currently executing, or "Unassigned" |
| Notes | Integration points, blockers, follow-up origin |

### 9.7 Coordination Loop and Execution Waves

The coordinator MUST run a repeating loop:

1. **Plan wave:** Select the set of child tasks whose dependencies are satisfied and whose territories do not conflict (per [`delegation.md` Section 5](delegation.md#5-safety-requirements)).
2. **Dispatch:** Launch parallel agents/allies for the selected tasks. Record dispatch in the Work Log.
3. **Monitor:** Track progress. Receive reports verbatim into child task files ([Section 8.2](#82-verbatim-recording-requirement)) and summarize into the coordinator Work Log.
4. **Integrate:** Reconcile completed child results, resolve cross-task conflicts, and update the registry.
5. **Decide:** Determine the next wave, create follow-ups ([Section 9.9](#99-follow-up-task-creation)), and handle accumulated questions ([Section 9.8](#98-question-handling-protocol)).

The loop continues until no unblocked child tasks or follow-ups remain.

### 9.8 Question Handling Protocol

Classification and escalation of questions raised by child agents and by the coordinator's own decisions follow the **Question Batching Discipline** in [`delegation.md` Section 6.4](delegation.md#64-question-batching-discipline), which governs all Manager Mode (Delegating) work. This section does not restate those rules. It instantiates them with the persistent bookkeeping a coordination file provides: a Question Log, a Question Queue, and the explicit states below.

#### 9.8.1 Classification

Each question begins in state **Open** ([Section 9.8.3](#983-question-states)). Classify it as Basic or Significant per [`delegation.md` Section 6.4](delegation.md#64-question-batching-discipline). In the coordination file:

- A **Basic** question is recorded in the Question Log ([Section 9.8.4](#984-question-log-and-queue-format)) with its answer, marked **Self-Answered**, and work proceeds.
- A **Significant** question enters the Question Queue ([Section 9.8.4](#984-question-log-and-queue-format)) in state **Queued** ([Section 9.8.3](#983-question-states)), and all unblocked work continues.

#### 9.8.2 Escalation

Escalate queued questions per the triggers and batching rules in [`delegation.md` Section 6.4](delegation.md#64-question-batching-discipline) (hard block, checkpoint, high rework risk, status request; whole-batch interruption; independent-questions-only sequencing). Map each escalation to a queue-state transition:

- A **hard block** moves the question to **Blocking**, then immediately to **Asked** (it is asked at once).
- A **checkpoint**, **high-rework-risk**, or **status-request** escalation moves all then-pending queued questions to **Asked**, presented in one batch.

A question moves from **Asked** to **Resolved** when the user answers.

#### 9.8.3 Question States

| State | Meaning |
|-------|---------|
| **Open** | Just raised, not yet classified |
| **Self-Answered** | Basic question resolved by the coordinator and logged |
| **Queued** | Significant question deferred, work continues around it |
| **Blocking** | Queued question now gates all remaining work |
| **Asked** | Presented to the user, awaiting answer |
| **Resolved** | User answered, resolution recorded |
| **Cancelled** | No longer relevant, reason recorded |

Permitted transitions: `Open → Self-Answered`; `Open → Queued → Blocking → Asked → Resolved`; `Queued → Asked → Resolved` (checkpoint, high rework risk, or status request); any Queued/Blocking/Asked state `→ Cancelled` with a recorded reason.

#### 9.8.4 Question Log and Queue Format

Self-answered (Basic) questions are recorded in the **Question Log** with the source, the coordinator's answer, and the rationale that justified answering autonomously.

Deferred (Significant) questions are recorded in the **Question Queue** with the source, current state, the task IDs the question blocks (or "none yet"), and the user resolution once Resolved.

The Question Queue MUST be kept current in real time per [Section 8.1](#81-real-time-updates). Every queued question MUST end as either Resolved by the user or explicitly Cancelled with a recorded reason, never silently dropped. A question MAY be Cancelled when it becomes irrelevant (for example, when the child task it blocked is itself Cancelled).

### 9.9 Follow-up Task Creation

Work that surfaces while a child task is in progress and falls within that task's scope MUST be handled within the child task itself. The coordinator MUST NOT spin up a new task file for every surfaced item.

A new follow-up task file is created only when work is deferred or ruled out of the originating task's scope. This is the coordination-mode instance of the general Deferred Work Capture rule ([Section 8.6](#86-deferred-work-capture-at-closure)), applied as the child task closes: any deferred, follow-up, or "nice-to-have" work the child ruled out of scope MUST become its own task file before that child task is marked Completed. When this occurs, the coordinator MUST:

1. Create a follow-up task file in Triage state ([Section 7.2](#72-triage-to-ready-planning-phase)), named per [Section 3.4](#34-file-naming-convention).
2. Register it in the Child Task Registry ([Section 9.6](#96-child-task-registry)) with its origin recorded in Notes.
3. Link it from the originating child task and from the coordination file.
4. Update the master index dashboard ([Section 4.3](#43-index-maintenance)).

Exception: work the coordination effort genuinely requires to meet its objective (for example, a newly discovered blocking dependency) MAY be created as a child task as soon as it is identified, rather than waiting for closure, because the coordinator must track and sequence it. This exception does not extend to nice-to-have or deferrable work, which waits for closure.

Follow-up tasks participate in the coordination loop like any other child task. The coordination file itself MUST NOT be marked Completed ([Section 9.11](#911-lifecycle-and-completion)) while deferred or out-of-scope work remains uncaptured.

### 9.10 Dashboard Integration

A coordination task file MUST appear in the master index (`tasks.md`) and MUST be visually distinguished from standard task files by prefixing its dashboard entry with `[COORD]`. Its dashboard row MUST summarize child rollup (for example, "4/7 child tasks complete, 2 questions queued").

Child task files continue to appear in the dashboard individually under their own lifecycle lanes. The coordination file's "What Was Done" snapshot MUST reference the current wave and the queue depth.

### 9.11 Lifecycle and Completion

A coordination task file MAY be marked Completed ONLY when ALL of the following hold:

- Every child task and follow-up task is Completed or Cancelled.
- The Question Queue is empty (all Significant questions Resolved or Cancelled).
- Program-level Success Criteria are met and integration is verified.

If child tasks remain but the coordinator is blocked solely on user input, the coordination file MUST be moved to Blocked (see Task Lifecycle States) with the blocking questions referenced, not Completed.

### 9.12 Coordination Task File Template

```markdown
# Coordination: [Descriptive Name]

*Created: YYYY-MM-DD HH:MM*
**Type:** Coordination
**ID:** COORD-NNN
**Status:** Triage | Ready | In Progress | Blocked | Cancelled | Completed
**Mode:** Manager Mode (Delegating - parallel)

## 1. Objective

[The shared goal across all coordinated tasks and why it matters]

## 2. Success Criteria

- [ ] Program-level criterion 1
- [ ] Program-level criterion 2
- [ ] All child tasks Completed or Cancelled; integration verified

## 3. Child Task Registry

| Task | ID | Status | Depends On | Wave | Assigned | Notes |
|------|----|--------|------------|------|----------|-------|
| [Task A](./YYYYMMDD-HHMM-task-a.md) | API-001 | In Progress | None | 1 | Nezha | Shared schema owner |
| [Task B](./YYYYMMDD-HHMM-task-b.md) | API-002 | Ready | API-001 | 2 | Unassigned | Consumes Task A output |

## 4. Coordination Strategy and Decision Log

**Strategy:** [How waves are sequenced, how territories are isolated]

### Decision: [Short title]

*Timestamp: YYYY-MM-DD HH:MM*

**Context / Alternatives / Final Decision / Rationale:** [Per the Decision Log format in the standard task file template (Section 5.2)]

## 5. Coordination Loop / Execution Waves

### Wave 1

- Dispatched: [task IDs] to [allies/agents]
- Status: [in progress / complete]
- Integration result: [summary]

## 6. Question Log (Self-Answered, Basic)

- [Timestamp] Q (source: API-001 agent): [question]
  - Class: Basic
  - Answer: [coordinator answer]
  - Rationale: [why answering autonomously was justified]

## 7. Question Queue (Significant)

- [Timestamp] Q (source: API-002 agent): [question]
  - State: Queued | Blocking | Asked | Resolved | Cancelled
  - Blocks: [task IDs, or "none yet"]
  - Resolution: [user answer once Resolved]

## 8. Follow-up Tracking

| Follow-up | ID | Origin | Status | Link |
|-----------|----|--------|--------|------|
| [Name] | TASK-010 | Surfaced by API-001 | Triage | [link] |

## 9. Work Log

[Coordinator dispatch and integration entries per the Work Log section; agent reports recorded verbatim per Section 8.2]

## 10. Execution Log

[Timeline, work summary, failed approaches, final summary per the Execution Log of the standard task file template]
```

---

## 10. Conformance

Violations of MUST requirements constitute conformance failures.

- Failing to keep dashboard and task files synchronized ([Section 4.3](#43-index-maintenance))
- Creating task files without user request ([Section 2.2](#22-creation-prohibition))
- Summarizing agent output instead of recording verbatim ([Section 8.2](#82-verbatim-recording-requirement))
- Marking a task Completed before the Simplify and Review Loop has converged, or without documenting each loop iteration in the Work Log (the TDD Workflow section of the standard task file template, [Section 5.2](#52-task-file-template)), is a conformance failure.
- Failure to immediately and thoroughly update associated task file for any work done related to the task (by any agent, manager, engineer, or reviewer, in any role) is a critical conformance failure with zero tolerance for exceptions.
- Deleting or overwriting previously written task file content ([Section 8.5](#85-content-preservation)) is a critical conformance failure with zero tolerance for exceptions.
- Performing implementation work directly within a coordination task file, rather than dispatching it to child tasks ([Section 9.1](#91-definition-and-purpose), [Section 9.2](#92-operating-mode)), is a conformance failure.
- Fabricating an answer to a Significant question to avoid interrupting the user ([`delegation.md` Section 6.4](delegation.md#64-question-batching-discipline)), or silently dropping a queued question ([Section 9.8.4](#984-question-log-and-queue-format)), is a conformance failure.
- Marking a coordination task file Completed while child tasks remain or the Question Queue is non-empty ([Section 9.11](#911-lifecycle-and-completion)) is a conformance failure.
- Closing a task while identified deferred, follow-up, "nice-to-have", or out-of-scope work remains uncaptured as new task files ([Section 8.6](#86-deferred-work-capture-at-closure)) is a conformance failure.

---

*This specification defines task documentation requirements for all OpenCode implementations.*
