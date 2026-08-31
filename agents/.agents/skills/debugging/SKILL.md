---
name: debugging
description: Debugging protocol covering systematic defect investigation: reliable reproduction, isolation and minimization, evidence-based hypothesis testing, root-cause diagnosis, minimal targeted fixes with mandatory regression tests, instrumentation cleanup, and escalation after failed hypotheses. Use when investigating bugs, errors, crashes, unexpected behavior, test or build failures, flaky tests, or when the user reports something not working.
---

# Debugging Protocol

## Scope

This specification defines requirements for investigating and fixing defects: reported bugs, runtime errors, crashes, test failures, build failures, and intermittent (flaky) behavior.

### Related Specifications

- The `core` rule (always loaded): failure as information; prohibited failure responses
- The `coding-standards` rule (always loaded): error handling and test standards
- The `simplify-review` skill: final verification failures load this skill; completed fixes pass through its loop
- The `git-protocol` skill: a fix commits together with its regression test; root-cause history belongs in the commit message

---

## Investigation Phases

Investigation MUST proceed through the phases below in order. Isolation and diagnosis iterate together; every other phase MUST meet its exit criteria before the next begins.

### Phase 1: Reproduce

Before proposing or applying any fix, implementations MUST establish a reliable reproduction: a command, test, or sequence that triggers the failure at will.

- Where the failure cannot be reproduced, implementations MUST gather conditions instead (logs, environment, exact steps, observed frequency), MUST state explicitly that no reproduction exists, and MUST label every hypothesis tentative until one does
- For intermittent behavior, implementations MUST attempt the trigger repeatedly to determine whether the failure is deterministic or flaky before investigating further

### Phase 2: Isolate

Implementations MUST narrow the failure to the smallest scope that still reproduces it: minimal input, single test, single code path.

Applicable techniques include binary-searching the change history (`git bisect`) for regressions, minimizing the triggering input, bisecting the code path by disabling sections, and instrumentation: temporary logging, breakpoints, debuggers, system-call tracing. Instrumentation added during investigation MUST be removed before the work is reported complete.

### Phase 3: Diagnose

Implementations MUST identify the root cause through evidence, where the root cause is why the failure occurs rather than where it surfaces.

- Every hypothesis MUST be testable against the reproduction, and tested; guesses do not count as hypotheses
- Implementations MUST NOT apply fixes without an identified root cause
- Symptom-level mitigations (swallowing the error, blind retries, disabling the failing check) MUST NOT be presented as fixes; they are permitted ONLY when the user explicitly accepts them after being told the root cause is unknown
- Once the root cause is known, implementations MUST check the same defect pattern in adjacent code paths and call sites

### Phase 4: Fix

- The fix MUST be minimal and targeted at the root cause; one change at a time
- Where the bug is reproducible in a test, implementations MUST write a regression test that reproduces it, confirm the test fails before the fix, and confirm it passes after
- Where the bug is not testable, implementations MUST document manual reproduction steps and the verification performed in their place
- Unrelated changes MUST NOT be mixed into the fix (per the `git-protocol` skill's logical unit separation)

### Phase 5: Verify

- Confirm the reproduction no longer triggers
- Re-run the full test suite to confirm no regressions
- Verify the adjacent paths identified during diagnosis
- The task then completes through the `simplify-review` skill's loop

---

## Escalation Requirement

After 3 failed hypotheses (tested and disproven, not merely untried), implementations MUST stop and report: reproduction status, evidence gathered, each failed hypothesis with its disproof, and remaining theories. The user's direction then governs further investigation.

Implementations MUST NOT continue past the escalation threshold without user direction.

---

## Conformance

Violations of MUST requirements constitute conformance failures, notably: proposing or applying fixes without a reproduction (outside documented non-reproducible cases), presenting symptom mitigation as a root-cause fix, skipping the regression test when the bug is testable, leaving instrumentation in place, or continuing past the escalation threshold without user direction.
