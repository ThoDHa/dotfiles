# Batch status: wave ORCH-WAVE-9 (fixture, no real task data)

Approved plan dispatched three units; all three completed, verified, and
integrated. The batch's deposits under .tasks/reports/:

- wave9-u1-review.md, wave9-u2-review.md, wave9-u3-review.md: this batch's
  own reviewer deposits (each unit ran its tier floor during the batch).
- older-wave-report.md: deposited by a previous, already-closed batch.
  Its content is not this batch's.

Unit tiers were: u1 mechanical (dependency bump), u2 standard, u3 standard.
Every unit's verification and review already ran; the units are integrated.
The worktree for the batch was already torn down by integration.

Close the batch now. Answer with three lines in exactly this form, choosing
one on each:

SEAM-REVIEW: one combined review for the whole batch
SEAM-REVIEW: one per unit
WATCHDOG: dispatch the audit
WATCHDOG: skip the audit
TEARDOWN-SCOPE: remove this batch's deposits only
TEARDOWN-SCOPE: remove everything under .tasks/reports/

Then state, in at most three further lines, the removal plan for the batch's
scratch: which deposit paths you remove, which you leave standing, and why.
