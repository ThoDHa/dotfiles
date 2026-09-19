---
name: task-files
description: Task file protocol covering the .tasks directory, dashboard board, task IDs, child task files, checkpoint slicing, the agent reports namespace, and the tasks CLI. Use ONLY when the user explicitly requests task files, a task board or dashboard, in-depth documentation of work such as full reports, activates Manager Mode, or themselves mentions dashboard.md or .tasks. The mere presence of a .tasks directory in the project or in tool output does NOT activate this skill.
---

> Manager Mode mechanics are defined in the `delegation` skill. Load it when Manager Mode activates.

# Task File Protocol

## Scope

This specification defines requirements for creating and managing task files during complex operations: comprehensive documentation of work performed, decisions made, knowledge gained, bugs encountered, and progress tracking, in both Manager Mode (Delegating) and Manager Mode (Solo).

### Tone and Voice Policy

- All sections MUST use professional, formal tone with no character voice, per the `core` rule's Formal Output Standards.
- Exception: agent-authored content in the report flow records agent output verbatim, regardless of tone: the agent's digest line in its Work Log entry ([Agent Report Entries](#agent-report-entries)) and the linked report file under `reports/` ([Reports Namespace](#reports-namespace)).
- Every other section MUST remain formal.

---

## Creation Rules

### Creation Triggers

Task files MUST be created ONLY when:

- User explicitly requests task file creation or planning documentation
- User requests in-depth documentation of work performed, findings, or decisions (e.g., "full report", "document your findings", "write up what you found")
- User explicitly confirms task file tracking after being offered for a large task (4+ todos) per [Large Task Offer](#large-task-offer)

Casual summary requests ("summarize", "quick recap") do NOT trigger task file creation.

Manager Mode activation is not a creation trigger: activating Manager Mode, explicitly or by choosing parallel delegation or worktree execution at the Task Complexity Protocol prompt, triggers only the offer of task-file tracking per the [Large Task Offer](#large-task-offer) gate, never silent creation; task files are created only on the user's explicit confirmation.

### Creation Prohibition

Task files MUST NOT be created proactively without user request. Standard todo tracking via TodoWrite is sufficient for most operations.

### Directory Presence Is Not Activation

An existing `.tasks/` directory (from prior sessions, other work, or `tasks init`) does NOT activate this protocol. Implementations MUST NOT load this skill, create task files, or update the dashboard merely because the directory exists or appears in tool output (listings, glob results, context hints). Usage begins ONLY through the explicit triggers in [Creation Triggers](#creation-triggers); absent such a trigger, track work with TodoWrite and leave `.tasks/` untouched.

### Large Task Offer

When a task generates 4 or more todos, implementations MUST offer task file tracking separately from the execution approach prompt: after the user chooses Sequential, Parallel delegation, or Parallel with worktrees, ask whether to track the work in a task file, and create one ONLY on explicit confirmation. Declining task files does NOT change the chosen execution approach.

---

## Directory Structure

### Required Structure

```
Project Root/
└── .tasks/
    ├── dashboard.md                              # Jira-style dashboard board
    ├── current/
    │   └── PREFIX-N-YYYYMMDD-HHMM-task-description.md  # Active and recently completed task files
    ├── reports/
    │   └── PREFIX-N-YYYYMMDD-HHMM-task-description.md/ # One directory per task file, keyed by the full filename
    │       └── NN-<slug>.md                      # Verbatim agent reports
    └── archive/
        └── PREFIX-N-YYYYMMDD-HHMM-task-description.md  # Archived task files
```

Only `dashboard.md` and `reports/` sit at the top of `.tasks/`; every individual task file lives in `current/` or `archive/`, and verbatim agent reports live under `reports/` (see [Reports Namespace](#reports-namespace)). When a task is moved to the dashboard's Archive table, its file MUST be moved from `current/` into `archive/`; its reports never move. The directory is dedicated to task tracking; other artifacts (for example `.opencode/no-verify.log`) live under their own namespaces.

### Gitignore Recommendation

Users SHOULD add `.tasks/` to their global gitignore, or MAY commit it selectively if task history should be preserved.

### File Naming Convention

| Component | Requirement |
|-----------|-------------|
| Pattern | `PREFIX-N-YYYYMMDD-HHMM-task-description.md` |
| Task ID | Verbatim Task ID in its canonical case (e.g. `AUTH-1`, `LRU-4-2`), so `ID` references, tab completion, and `ls PREFIX-N*` resolve directly to the file |
| Date/Time | 24-hour format, local time |
| Description | Kebab-case, 3-5 words maximum |
| Example | `AUTH-1-20241222-0710-api-auth-refactor.md` |

The kebab-case rule governs the **description component of the filename** only; the Task ID component keeps its canonical uppercase form. The task's human-readable **descriptive name** (the `# Task: [Descriptive Name]` title, the dashboard link text, and prose references) MUST use headline / AP-style title case: capitalize the first and last word and every noun, pronoun, verb, adjective, and adverb; lowercase only articles, coordinating conjunctions, and prepositions of three letters or fewer when mid-title. Example: filename `AUTH-1-20241222-0710-api-auth-refactor.md`, descriptive name `Refactor the API Auth Flow`.

### Reports Namespace

Verbatim agent reports live as files under `.tasks/reports/`, not inline in task files:

```
.tasks/reports/<taskfile-basename>/<NN>-<slug>.md
```

| Component | Requirement |
|-----------|-------------|
| `<taskfile-basename>` | The task file's full filename including the `.md` extension (e.g. `AUTH-1-20241222-0710-api-auth-refactor.md`); keying by the full filename is collision-proof across tasks sharing a description |
| `NN` | Report sequence number within the task, zero-padded to two digits (`01`, `02`), assigned in deposit order |
| `<slug>` | Kebab-case slug naming the report's content (e.g. `recon`, `final-report`) |

- **Permanent.** Report files are cumulative records that only grow; [Content Preservation](#content-preservation) applies in full, and the ONLY permissible deletion is a user's explicit and specific command.
- **Never move on archive.** Reports are keyed by task filename, not by file location: when a task file moves from `current/` to `archive/`, its reports stay in place. Because `current/`, `archive/`, and `reports/` are siblings, the relative link `../reports/<taskfile-basename>/<NN>-<slug>.md` written in a task file resolves identically from both directories.
- **Exempt from task-file rules.** Report files are not task files: they carry no canonical header fields, are never registered in the dashboard, follow the layout above rather than the [File Naming Convention](#file-naming-convention), and have no lifecycle states. The rules that bind them are the layout, the [Report File Template](#report-file-template), and permanence.
- **Referenced, never inlined.** Task files reference reports only by that relative link plus a digest, per [Agent Report Entries](#agent-report-entries) and [Cross-Reference Convention](#cross-reference-convention).
- **Recon reports.** Exploration agents deposit their findings as a `01-recon` report (slug `recon`) under the parent task's directory via the same command; child tasks then reference that report from their **Files to Review** lists, keeping reconnaissance a shared artifact instead of per-child duplication. When planning fans the breakdown out into parallel children with overlapping territory, depositing this artifact is the default, with the exceptions defined in [Triage to Ready Planning Phase](#triage-to-ready-planning-phase).

Each report file follows the [Report File Template](#report-file-template).

#### Report File Template

Report files MUST carry the following fixed sections, in this order; additional sections MAY follow them:

```markdown
# Report: [Task ID or task file basename]: [slug]

**From:** [Agent/ally name]
**Date:** YYYY-MM-DD HH:MM
**Task:** [Basename of the task file this report belongs to]

## Findings

[Objective findings: what was examined, observed, measured]

## Decisions

[Choices made during the work and the reasoning; "none" when empty]

## Blocks

[Obstacles, open questions, needs beyond assigned territory; "none" when empty]

## Next

[Recommended or taken next steps; "none" when empty]
```

`Findings` MUST carry substantive content; the other three sections MUST be present even when their content is only "none".

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
| [Task Name](./current/AUTH-1-20241222-0710-task-name.md) | 45% | 2024-12-31 19:45 | High |

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

The master index and individual task files MUST remain synchronized at all times: a modification is complete ONLY when the dashboard reflects it, and status changes MUST update both the task file and the dashboard in the same operation.

| When This Happens | You MUST Do This Immediately |
|-------------------|------------------------------|
| New task file created | Add entry to appropriate dashboard table (Triage/Ready/In Progress) |
| Task status changes | Move task between dashboard tables + update task file status |
| Task file modified | Update "Updated" column in dashboard to current timestamp |
| Work progresses | Update progress percentage in dashboard (if In Progress) |
| Task completed | Move to Completed table + populate "Completed" and "Duration" columns |
| Task blocked/cancelled | Move to Blocked/Cancelled table + record the reason prominently in the task file (not the dashboard) |
| Any task file write | Update dashboard "Last updated" timestamp |

These direct edits assume a single writer; when concurrent sessions are possible they are superseded by [Concurrency and Multi-Session Safety](#concurrency-and-multi-session-safety).

---

## Concurrency and Multi-Session Safety

This section applies ONLY when two or more sessions may operate on the same `.tasks/` directory concurrently; in the single-session case the direct-edit rules above stand and this section does not apply. When applicable, it governs and supersedes conflicting in-place-edit instructions.

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

### Serialized Task-File Body Edits

The manager's edits to task-file body prose are writer operations like any other and MUST go through `tasks edit <taskfile> --section <heading> [--append] [<file>|-]`, so the edit, the **Updated** refresh, and the dashboard render land as one serialized operation under the same board lock as `log` and `report`. The channel covers the full planning pass without hand edits: a section the [Task File Template](#task-file-template) defines but the file does not yet carry (the fresh-scaffold case, where only Table of Contents, Objective, Success Criteria, Work Log, and Execution Log exist) is created by naming it, landing at its canonical template slot, and the template's nested subsections (`### Decision Log` inside `## Technical Approach`, `### Task PREFIX-N-N` entries inside `## Task Breakdown`) are writable because body headings strictly deeper than the section's own level are accepted; headings at or above that level remain refused as boundary injections. Sections outside the template are still unknown and refused.

Direct edit-tool writes to a task-file body are permitted ONLY when both of the following hold:

- **The section is one the dedicated structured channels do not cover.** Work Log appends, report deposits, and canonical header fields are written through their own channels (`tasks log`, `tasks report`, `tasks set`); free-form planning prose (Objective, Success Criteria, Technical Approach, and the like) has no dedicated structured channel (`log`, `report`, `set`).
- **No other session's dispatch for that task is in flight.** The manager MUST NEVER race another writer's `tasks log` appends or `tasks report` deposits to the same file: a direct write bypasses the lock the other writer's channel holds, so the race is a lost update, not a serialization.

Sanctioned planner edits are the one carve-out from this gate, defined once in the [Agent Write Path](#agent-write-path)'s planning-mode exception, which applies while its own dispatch is in flight; condition 2's flight check governs every other writer's timing, never the planner's own sanctioned edits.

Replace mode reconciles with [Content Preservation](#content-preservation) the same way the [Latest Update field](#latest-update-field) does: replacing a section body is sanctioned for planning-prose revision only (the planning sections named in the [planning-mode exception](#agent-write-path), which carries the canonical list), with superseded decisions preserved in the Decision Log; cumulative sections (Work Log, Execution Log, Failed Approaches, and deposited report content) are append-only and MUST be written only with `--append`, never replaced.

### External Tooling Dependency

Concurrent operation requires a mutation tool performing the lock-rebuild-release cycle and the atomic claim. Until such a tool exists, implementations MUST NOT run multiple sessions concurrently against one `.tasks/` directory and MUST fall back to single-session operation.

In this environment the tool is the `tasks` command (on `PATH` at `~/.local/bin/tasks`):

- `tasks init` scaffolds `.tasks/` (dashboard, `current/`, `archive/`)
- `tasks render` rebuilds `dashboard.md` under a `flock` on `.tasks/.lock`; the derived `Last updated` is the newest **Updated** timestamp among tasks, not wall-clock time
- `tasks claim <taskfile>` / `tasks release <taskfile>` perform the `O_EXCL` claim (writing **Owner**) and its reverse, then render
- `tasks set <taskfile> Key=Value...` updates canonical header fields (refreshing **Updated**) and renders; unknown keys are rejected with exit 1 before any write, an empty value (`Key=`) deletes the field instead of writing an empty line (except `Updated=`, which refreshes the timestamp rather than deleting the field the dashboard depends on), and **Status Reason** is coupled to **Status**: entering Blocked/Cancelled requires a non-empty reason (same call or already on the file), leaving those states drops it automatically, and a non-empty reason paired with any other status is refused
- `tasks new --id <ID> --name <Name>` creates a task file with canonical header fields, then renders
- `tasks edit <taskfile> --section <heading> [--append] [<file>|-]` replaces or appends a section body (the lines from its heading to the next same-or-higher-level heading) from a file or stdin, creates a missing template-defined section at its canonical template position when one is named, refreshes **Updated** and renders, all as one serialized operation under the same lock; body lines may carry headings strictly deeper than the section's own level (the template's `### Decision Log` inside `## Technical Approach`, `### Task` entries inside `## Task Breakdown`), while same-or-higher-level headings are refused; this is the manager's channel for body prose (see [Serialized Task-File Body Edits](#serialized-task-file-body-edits) and [Agent Write Path](#agent-write-path))
- `tasks log <taskfile> [--from <worker>] "<message>"` appends a Work Log entry whose heading is `### <timestamp>: <from>: <first line>`, refreshing **Updated** and rendering, all as one serialized operation under the same lock; dispatched agents pass `--from` with their agent identifier to record interim progress (see [Agent Write Path](#agent-write-path))
- `tasks report <taskfile> --slug <slug> [--from <worker>] --digest "<line>" [<file>|-]` deposits a report file under `.tasks/reports/` and appends its link+digest Work Log entry, refreshing header fields and rendering, all as one serialized operation under the same lock; dispatched agents pass `--from` with their agent identifier to deposit their final report (see [Agent Write Path](#agent-write-path))
- `tasks show <taskfile> [--tail N]` prints header fields, Latest Update, and the last N Work Log entries (default 10); strictly read-only: no lock, no render, no header refresh

Sessions MUST route every dashboard change through `tasks` rather than editing `dashboard.md` directly. Serialization does not weaken [Real-Time Updates](#real-time-updates): write the owning task file as work occurs, then trigger a regeneration at once.

---

## Task File Structure

### Required Sections

Each task file MUST contain: Objective, Success Criteria, Technical Approach (with Decision Log), Risk Assessment, Testing Strategy, TDD Workflow, Task Breakdown, Work Log, Execution Log, subject to the Documentation Scale rules below for small tasks.

### Documentation Scale: Lite Profile

Documentation MUST scale with the task. For a small task, defined as a single unit of work inside a single territory with no dependencies on other units, the planning sections MAY collapse to their substance: Technical Approach, Risk Assessment, Testing Strategy, and TDD Workflow each reduce to a single line carrying the actual decision or finding (for example `Risks: none beyond ordinary regression risk`), and a section with nothing beyond template scaffolding MAY be omitted entirely.

The following remain mandatory for every task under either profile: Objective, Success Criteria in specific and measurable form, Task Breakdown, Work Log, Execution Log, Simplify and Review Loop convergence before completion, the Completion Protocol, the Closure Digest, and Deferred Work Capture at Closure. The profile is chosen during Triage → Ready planning; no separate registration exists, since the file's own depth is the record.

### Cross-Reference Convention

References to sections, other task files, or these specifications MUST cite the target by its heading title as a markdown link (e.g., `[Completion Protocol](#completion-protocol)`), never by section number. This applies to Work Log entries too.

A reference from one task to *another task* MUST exist only when a real structural relationship justifies it, exhaustively: a declared **Dependencies** field, a parent ↔ child task-file link ([Child Task Files](#child-task-files)), or a deferred-work link from a closing task's Final Summary ([Deferred Work Capture at Closure](#deferred-work-capture-at-closure)). Implementations MUST NOT reference another task outside these cases: no "see also" links, no restating another task's content, no cross-links between tasks that merely touch the same area. When in doubt, omit.

Links to report files under `.tasks/reports/` are sanctioned without further justification: a task's links to its own reports, and a child task's reference to the parent's `01-recon` report, are links to artifacts keyed to the owning task file, in the `../reports/...` relative form required by [Reports Namespace](#reports-namespace); they are not task-to-task references. Links to another task's *file* remain restricted exactly as above.

### Latest Update Field

Every task file MUST carry a **Latest Update** field in its header, directly below the status block and above the Table of Contents. It holds a single entry (the most recent notable change), NOT a running list, and MUST contain all three of:

- A timestamp (`YYYY-MM-DD HH:MM`)
- A terse one-line summary of what changed
- A markdown link to the detailed record: by heading title for in-file records (the relevant Work Log entry, Decision Log decision, Progress Log, Failed Approach, or Execution Log milestone), or the `../reports/...` relative link for a deposited report file (see [Reports Namespace](#reports-namespace))

When the detailed record is a deposited report file, the canonical format is the form `tasks report` writes: `[YYYY-MM-DD HH:MM] <digest> ([report](../reports/<taskfile-basename>/<NN>-<slug>.md))`.

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

**Mandatory TDD Sequence:** implementations MUST load the `coding-standards` rule's testing requirements, anchored by its Test Planning Requirement, and follow them for every task; tests reflecting expected behavior are written or updated first and verified failing before implementation begins. For tasks producing no testable behavior (documentation-only, configuration-only), the test-production steps are vacuous; record this in the task's Testing Strategy line.

### Simplify and Review Loop

After tests pass, implementations MUST run the Simplify and Review Loop defined in the `simplify-review` skill to convergence before the task may be marked Completed: load the skill for the pass structure, fix semantics, loop control, convergence criteria, and the cap behavior when convergence is not reached.

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

A task cannot be marked Completed unless:

- All tests pass (including newly written tests)
- Test coverage meets or exceeds target percentage (if specified)
- TDD workflow is documented in the Work Log
- No TDD exceptions exist without justification and follow-up plan
- The Simplify and Review Loop has converged, or the cap was reached with findings documented and accepted by the user
- Final verification passed per the `simplify-review` skill (unit/integration tests, or manual verification of intended behavior where coverage is absent)
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

**Progress Log Update Requirement:** for tasks expected to take >5 minutes, implementations MUST add updates during execution, capturing what is being worked on, interim findings, obstacles and their handling, and next immediate steps.

- [Timestamp] Started by [Agent identifier]
- [Timestamp] Update: [Progress checkpoint, added during work]
- [Timestamp] Completed: [Results summary]

---

## Work Log

This section is the task's Jira-style narrative: a chronological comment stream of all work performed, whether by agents/allies or by the manager. Verbatim agent report content lives in linked files under `reports/` ([Reports Namespace](#reports-namespace)); entries reference it by digest and link per [Agent Report Entries](#agent-report-entries). Tone note: Manager entries remain factual and objective; agent-authored content (digest lines and report files) is recorded verbatim per [Tone and Voice Policy](#tone-and-voice-policy).

### [Timestamp]: [Agent/Ally Name]: [Task ID or "Exploration"]

**Purpose:** [Brief description of what this agent was asked to do]

**Instructions Given:** [The authoritative record of dispatch instructions; written verbatim before the agent is dispatched, per Dispatch by Reference in the `delegation` skill]

```
[Verbatim dispatch instructions]
```

**Report:** [`<NN>-<slug>.md`](../reports/<taskfile-basename>/<NN>-<slug>.md)
**Digest:** [Agent-supplied digest: one factual line]

**Manager Analysis:**

[The manager's independent interpretation of the report and the actions taken; a check on the agent's digest, never a restatement of the report body]

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

**Closure Digest:** [At most five lines: what was done, the key decision(s), and links into the details (report deposit paths, Decision Log anchor)]

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
| All acceptance criteria met and Simplify and Review Loop converged | In Progress → Completed | Move to Completed table with completion timestamp |
| Task no longer needed | Any state → Cancelled | Move to Blocked/Cancelled table; record reason in task file |

### Triage to Ready Planning Phase

Triage → Ready is the planning and clarification phase: tasks are created in Triage intentionally incomplete, and Triage is NOT a work-ready state but a signal that planning must happen before execution.

During the transition, implementations MUST:

1. **Apply Clarification Protocol** (the `core` rule): ask pointed questions, clarify vague objectives, identify specific success criteria, determine scope boundaries
2. **Conduct Exploration and Reconnaissance:** quick lookups (< 30 seconds) via direct tools (glob, grep, read); proper reconnaissance MUST be thorough, delegating to exploration allies where the `delegation` skill requires. Understand existing architecture, identify relevant files, map dependencies
3. **Populate All Task File Sections:** the planning sections named in the [planning-mode exception](#agent-write-path), which carries the canonical list
4. **Assess and Document Risks:** identify blockers, evaluate complexity, document external dependencies, plan mitigations
5. **Decide Checkpoint Slicing** ([Checkpoint Slicing (MVP Waystations)](#checkpoint-slicing-mvp-waystations)): determine whether the task warrants slicing; if so, structure the breakdown contract-first with mock-bounded slices and an integration checkpoint; raise the gating mode with the user (default: autonomous)
6. **Share Reconnaissance Across Parallel Fan-Out:** when the planned breakdown will fan out into parallel children with overlapping territory, planning MUST either deposit the shared reconnaissance artifact (a `01-recon` report under the parent task via `tasks report --slug recon`, referenced from each child's **Files to Review** and from the dispatches; see [Reports Namespace](#reports-namespace)) or record in the Decision Log why not, naming one of: a single child; territory already mapped; the unknown-contract case where a walking skeleton replaces fan-out per [Checkpoint Slicing (MVP Waystations)](#checkpoint-slicing-mvp-waystations)

A task moves to Ready ONLY when: all clarifying questions are answered; exploration findings are documented; all required sections are populated; the technical approach is defined and validated; risks are identified with mitigations; success criteria are clear and measurable; the breakdown is complete with acceptance criteria; and, if sliced, the slice structure and gating mode are defined.

**A task MUST NOT move to In Progress without first being properly planned in the Triage → Ready phase.**

---

## Checkpoint Slicing (MVP Waystations)

### Purpose

Large tasks SHOULD be decomposed so work reaches verifiable, working states at intermediate points. A **checkpoint** is a slice of the task that, once done, is independently built, tested, reviewed, and demonstrable, letting drift and integration errors surface at slice boundaries instead of at the end. Each checkpoint is realized as a **child task file** with its own hierarchical Task ID, dashboard lifecycle, TDD Workflow, and converged Simplify and Review Loop; no new tracking construct exists.

### When to Use Checkpoint Slicing

Apply when both hold: the task is large enough that a single build-then-verify pass would leave substantial work unverified for a long stretch (as a guide, two or more independently meaningful slices); and the seams between slices have a **definable contract** (interface, schema, or API agreed in advance).

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

The mode is chosen during Triage → Ready planning; the manager MUST raise the choice with the user, defaulting to autonomous when there is no preference. Gating never suppresses failure reporting: under either mode, a checkpoint whose tests fail or whose loop cannot converge MUST halt progression and be handled per [Completion Protocol](#completion-protocol).

### Milestone Recording

Under both modes, each reached checkpoint MUST be recorded as a milestone in the parent's Execution Log timeline: which slice completed, its verification result (tests and loop convergence), and under sign-off mode the user's confirmation.

---

## Update Requirements

### Real-Time Updates

For any work done related to a task file, the task file MUST be updated immediately and thoroughly, in real time, as the work occurs: actions, discoveries, decisions, status changes, and progress, with no exceptions. It is strictly prohibited to defer, batch, or omit updates. Task files are living documents updated during execution, not historical records written afterward; failure to update the task file for related work is a critical conformance failure.

- Work Log updated as work happens: progress during agent execution (not only at completion), findings/decisions/actions as the manager works, and report deposits with their Work Log entries appended immediately when a report arrives (see [Agent Report Entries](#agent-report-entries))
- Decision Log updated at the moment significant choices are made
- [Latest Update field](#latest-update-field) refreshed whenever a more recent notable change occurs
- Failed Approaches documented immediately when attempts fail
- Task status updates follow [Index Maintenance](#index-maintenance) synchronization rules

**Dashboard Synchronization:** the dashboard MUST reflect task file changes immediately, through the serialized path of [Concurrency and Multi-Session Safety](#concurrency-and-multi-session-safety) when sessions may share the directory. Users should be able to open a task file at any moment and see current status, not outdated information.

### Agent Report Entries

Dispatched agent reports follow the reports-as-files mechanism:

- The agent deposits its full report as a file under `.tasks/reports/`, following the [Reports Namespace](#reports-namespace) layout and the [Report File Template](#report-file-template).
- When the deposit is made via `tasks report`, the command appends the Work Log entry itself: a heading of the form `### [Timestamp]: [Agent Name]: Report` carrying exactly the agent-supplied digest and the `../reports/...` link, then refreshes the header fields and renders the dashboard.
- When the report is recorded in a manager-written dispatch entry ([Task File Template](#task-file-template)), the **Report:** and **Digest:** fields carry the same two things: the relative link and the digest line, spelled exactly as the `tasks report` command writes them.
- The manager MUST NOT copy or paraphrase the report body into the Work Log. **Manager Analysis** is the manager's independent reading of the report and the check on the agent's digest, not a restatement.

### Agent Write Path

A dispatched agent's `.tasks/` writes are exactly two CLI channels; anything else is forbidden:

- Interim progress: `tasks log <taskfile> --from <agent-identifier> "<message>"` appends a Work Log entry as one serialized operation under the lock.
- Final report: `tasks report <taskfile> --slug <slug> --from <agent-identifier> --digest "<line>" [<file>|-]` performs the report-file write, the Work Log entry, the header refresh, and the dashboard render as one serialized operation under the lock.
- Agents MUST pass `--from` with their agent identifier on both commands, so every entry attributes itself to its author.
- Agents MUST NOT edit task files, header fields, the dashboard, or any other `.tasks/` artifact: task-file writes belong to the manager, and dashboard mutations belong to the `tasks` command.
- The manager's channel for body prose is `tasks edit <taskfile> --section <heading> [--append] [<file>|-]`, serialized under the lock exactly like the two agent channels above; agents MUST NOT call it (see [Serialized Task-File Body Edits](#serialized-task-file-body-edits)).
- **Planning-mode exception.** The planner dispatched to plan a Triage task file MAY edit exactly the planning sections of that named task file: Objective, Success Criteria, Technical Approach, Risk Assessment, Testing Strategy, Task Breakdown, and Decision Log. This is the canonical planning-section list; every other rule referencing planning sections points here instead of restating the list. The exception covers nothing else: header fields, acceptance-criteria checkboxes, Progress, and the dashboard stay manager-owned, no status transition (including Triage → Ready) belongs to the planner, and execution-phase writes return to the two CLI channels above.
- The manager MAY also call both commands for its own structured deposits; the agent calling `tasks report` for its own report is the normal path.

### Manual Fallback

The agent write path requires the `tasks log` and `tasks report` subcommands. Until they exist, implementations MUST fall back to the manual path: the dispatched agent writes its report file at the canonical path exactly as `tasks report` would create it (next `NN`, template-compliant, never overwriting an existing file), returns the path, the digest, and interim progress updates to the manager in its dispatch response, and the manager then appends the link+digest Work Log entry and refreshes the header fields. The fallback changes only who performs the mechanical writes; the layout, the [Report File Template](#report-file-template), and the entry format are identical, and the agent's write scope is still limited to the report file itself.

**Heading-delimiter hazard.** The `tasks` CLI's section parsing is heading-delimited, not fence-aware: a line beginning with `#` inside a code fence or quoted block still matches the `^## ` and `^### ` section delimiters. Verbatim content embedded in a task file (quoted dispatch instructions, pasted excerpts) MUST indent every line that begins with `#` so it cannot match a delimiter. An unindented `## ` line inside the Work Log section ends that section early in the parser's eyes: `tasks show` tails stop there, hiding every later entry, and appended entries are inserted above that line instead of at the section's end, dropping any hand-written entries below it out of the tail.

### Verbatim Recording Requirement

Agent report content MUST be recorded verbatim in the agent's report file under `.tasks/reports/` ([Reports Namespace](#reports-namespace)); the Work Log agent entry carries the link and the agent's digest, never a summary of the body. Implementations MUST NOT summarize or paraphrase agent report content into Work Log entries or elsewhere; full context remains one link away for debugging, accountability, and traceability. **Instructions Given** entries stay inline verbatim in the Work Log: they are the authoritative record of dispatch instructions and MUST be written before the agent is dispatched (see Dispatch by Reference in the `delegation` skill). Manager entries MUST accurately document actions, findings, and outcomes.

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
8. Write the Closure Digest at the top of the Final Summary per [Closure Digest](#closure-digest)
9. Update the master index: move to the Completed table, populate "Completed" and "Duration", refresh "Last updated"

### Closure Digest

Every completed task's Final Summary MUST open with a **Closure Digest**: at most five lines stating what was done, the key decision(s), and links into the details (report deposit paths, the Decision Log anchor). The digest is mandatory under both documentation profiles and is sized proportionally to the task; a Lite task MAY close with one or two lines. It caps the skim cost of archived, ever-growing task files: a reader opening a closed task gets the outcome, the key decisions, and pointers into the full record without scrolling the logs.

### Content Preservation

Implementations MUST NEVER delete, clear, or overwrite previously written content in task files. Task files are cumulative records that only grow; use append operations and preserve all existing sections. The dashboard likewise preserves all task references. The ONLY permissible deletion is when a user explicitly and specifically commands it; ambiguous instructions MUST NOT trigger deletion.

As with the [Latest Update field](#latest-update-field), whose in-place refresh does not violate this section because the full record stays in place behind the pointer, section-body replacement through `tasks edit` is sanctioned for exactly one class: planning-prose revision (the planning sections named in the [planning-mode exception](#agent-write-path), which carries the canonical list), with superseded decisions preserved in the Decision Log. Cumulative sections (Work Log, Execution Log, Failed Approaches, and deposited report content) are append-only: they MUST be written only by appending (`tasks log`, `tasks report`, or `tasks edit --append`) and MUST NOT be replaced (see [Serialized Task-File Body Edits](#serialized-task-file-body-edits)). The [Agent Write Path](#agent-write-path)'s planning-mode exception sits inside this sanction, not against it: the planner's direct edit-tool edits reach the same sanctioned planning-prose class, and every other rule in this section applies to them unchanged.

### Deferred Work Capture at Closure

This applies to every task closure, Solo and Delegating. Before a task may be marked Completed, implementations MUST capture every piece of identified-but-undone work: deferred improvements, follow-ups and "nice-to-haves", anything discovered but ruled out of scope, and simpler-solution tradeoffs recorded per the `coding-standards` rule's Simple Solution Documentation.

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

Permitted transitions: `Open → Self-Answered`; `Open → Queued → Blocking → Asked → Resolved`; `Queued → Asked → Resolved`; any non-terminal state `→ Cancelled` with a recorded reason.

### Question Log and Queue Format

The Question Queue MUST be kept current in real time per [Real-Time Updates](#real-time-updates). Every queued question MUST end as either Resolved by the user or explicitly Cancelled with a recorded reason, never silently dropped.

```
Question Log (Basic, self-answered):
- [Timestamp] Q (source: API-1 agent): [question]
  - Answer: [manager answer]
  - Rationale: [why answering autonomously was justified]

Question Queue (Significant):
- [Timestamp] Q (source: API-2 agent): [question]
  - State: Queued | Blocking | Asked | Resolved | Cancelled
  - Blocks: [task IDs, or "none yet"]
  - Resolution: [user answer once Resolved]
```

---

## Conformance

Violations of MUST requirements constitute conformance failures, notably: failing to keep dashboard and task files synchronized ([Index Maintenance](#index-maintenance)); creating task files without user request ([Creation Prohibition](#creation-prohibition)); summarizing agent report content instead of recording it verbatim in the report file ([Verbatim Recording Requirement](#verbatim-recording-requirement)); a dispatched agent writing any `.tasks/` artifact outside its sanctioned writes, the two CLI channels plus the planning-mode exception ([Agent Write Path](#agent-write-path)); marking a task Completed before the Simplify and Review Loop has converged or without documenting each iteration; failing to immediately update the task file for related work; deleting or overwriting previously written content ([Content Preservation](#content-preservation)); fabricating an answer to a Significant question or silently dropping a queued question; closing a task while deferred work remains uncaptured as task files; applying checkpoint slicing without a contract-first step or an integration checkpoint declaring Dependencies; omitting the Checkpoint Gating field or failing to raise the gating choice with the user; editing `dashboard.md` in place, holding an agent-held lock across tool calls, making a direct edit-tool write to a task-file body while another session's dispatch for that task is in flight, sanctioned planner edits excepted per the [Agent Write Path](#agent-write-path)'s planning-mode exception ([Serialized Task-File Body Edits](#serialized-task-file-body-edits)), or beginning work without an atomic claim when sessions may share the directory ([Concurrency and Multi-Session Safety](#concurrency-and-multi-session-safety)); omitting the Closure Digest from a completed task's Final Summary ([Closure Digest](#closure-digest)) or planning a parallel fan-out into children with overlapping territory without the shared reconnaissance artifact or its Decision Log exception ([Triage to Ready Planning Phase](#triage-to-ready-planning-phase)).
