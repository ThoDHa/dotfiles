# Task Board Dashboard

*Jira-style task management board. Auto-updated when task statuses change.*

## Task System Priority

**When receiving task execution commands** (e.g., "work on the next task", "handle the high priority task"), the following priority order MUST be used:

1. **TodoWrite (Primary)**: Check for active todos using the todoread tool first
2. **Task Files (Secondary)**: Consult this dashboard ONLY when:
   - TodoWrite is empty, OR
   - User explicitly references "task files"

**Rationale:** TodoWrite is the lightweight, primary system for standard work tracking. This task file system is reserved for complex operations requiring comprehensive documentation.

**When in doubt:** Check TodoWrite first.

---

## Triage
*No tasks in triage*

## Ready
*No tasks ready*

## In Progress
*No tasks in progress*

## Blocked/Cancelled
*No blocked or cancelled tasks*

## Completed
*No completed tasks*

---

## Task Management

**CRITICAL: Task File Updates**
- **If task file exists:** MUST use Edit tool to update sections - NEVER recreate the file
- **If task file does NOT exist:** Create new file using Write tool
- **Preserving history is mandatory:** Recreating existing files destroys context and violates protocol

**Task Creation:** Quick task files created in Triage, requires exploration and fleshing out
**Triage → Ready:** Task fully fleshed out, all information collected
**Ready → In Progress:** Work begins on task
**In Progress → Completed:** Acceptance criteria met, work finished
**State Recovery:** Blocked/Cancelled tasks can return to Ready/In Progress
**Automatic Promotion:** Tasks auto-promote through lifecycle as work progresses

---

*Last updated: 2025-12-31 20:00 - Auto-updated when task status changes*
