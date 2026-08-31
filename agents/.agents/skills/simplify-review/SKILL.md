---
name: simplify-review
description: Simplify and Review Loop covering the post-implementation convergence cycle: a simplify pass (reuse, dead code, redundancy, efficiency) followed by a review pass (correctness bugs, logic errors, edge cases, security), with fix semantics, loop control, and convergence criteria. Use when any task, todo, or user request reaches completion, before reporting work complete, after implementation finishes, or when the user asks to simplify, clean up, or review completed changes.
---

# Simplify and Review Loop

## Scope

This specification defines the convergence cycle that MUST run after a task's implementation work ends and before that task is reported complete. It applies to every completed unit of work: TodoWrite todos, task-file tasks (per the `task-files` skill), and standalone user requests, whenever the task modified files. Research-only tasks that produced no changes skip the loop.

### Related Specifications

- The `execution-standards` rule (always loaded): wires this loop into all task completion
- The `task-files` skill: Work Log documentation of each iteration when working under task files

---

## The Loop

After implementation ends and tests pass (where tests exist), implementations MUST iterate a simplify-then-review cycle before the task may be reported complete. Each iteration performs both passes in order:

1. **Simplify Pass (cleanup):** review the changed code for reuse, simplification, dead code, redundancy, and efficiency. Use `/simplify` where provided, otherwise equivalent manual cleanup. Apply every accepted improvement.
2. **Review Pass (bug hunt):** review for correctness bugs, logic errors, missing error handling, edge cases, and security issues. Use `/code-review` where provided, otherwise equivalent manual review. Fix every confirmed finding.

A "fix" is any change applied during the iteration, from either pass.

---

## Loop Control

- After applying any fix, re-run the test suite (where tests exist) to confirm no regressions
- The loop repeats as long as an iteration produced at least one fix
- The loop **converges** when one complete iteration produces **no fixes**
- Cap at a reasonable iteration count (default: 5). If not converged at the cap, stop, document outstanding findings, and consult the user before reporting the task complete

---

## Final Verification

Convergence proves no further fixes were found; it does not prove the work functions as intended. Before reporting the task complete, implementations MUST verify the task's changes end to end:

- Where unit or integration tests cover the changed behavior, run them and confirm they pass
- Where automated coverage is absent or insufficient for the change, perform manual verification: run the affected functionality and exercise the changed paths (invoke the command, call the API, start the app, render the view) to confirm intended behavior
- A verification failure counts as a fix: load the `debugging` skill, correct the failure through its investigation phases, then resume the loop until a complete iteration converges AND final verification passes

The verification method and result (command run, approach used, outcome) MUST be reported when reporting the task complete, and recorded in the Work Log under task files.

---

## Review Scope

The loop reviews the changes the task produced (its diff), not the entire codebase. Pre-existing issues outside the changed code are findings only when the changed code interacts with them; otherwise capture them as deferred work rather than expanding task scope. Under task files, deferred work capture follows the `task-files` skill's Deferred Work Capture at Closure.

---

## Reporting

When working under task files, each iteration MUST be recorded in the Work Log using the template in the `task-files` skill. Outside task files, report the iteration count, convergence result, and significant findings when reporting the task complete.

---

## Conformance

Violations of MUST requirements constitute conformance failures, notably: reporting a task complete without running the loop, reporting complete before convergence without documented findings and user acceptance of the cap, skipping test re-runs after applied fixes, or reporting complete without final verification of intended behavior.
