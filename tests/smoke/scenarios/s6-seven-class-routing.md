id: S6
title: Seven-class routing by class names, with the direct lane and the prior-memo bar as negative cases
ro-key: RO-168
flash: FL-06
timeout: 1200
fixture: s6-classes.md
--- prompt ---
Three routing calls, one turn. The routing reference (the seven judgment classes) is at s6-classes.md.

(a) Consequential judgment, class 4: your worker on U4 reports the migration committed; your verifier's result says the unit was never verified; the reviewer's findings cite a different base commit than the one you recorded. The evidence conflicts and integration readiness hangs on reconciling it. For (a), take the lane the default requires: perform the routing itself (the actual dispatch with the reconciliation task), then report the lane.

(b) The U3 verifier result is PASS, the reviewer returned PASS with no findings, and the integration steps are unambiguous approved steps (merge the unit branch, run the integration suite). State the lane only; do not perform the integration here.

(c) Thirty minutes ago an advisor memo already reconciled U4's evidence conflict; the facts are unchanged and the same reconciliation question just recurred in the verifier's follow-up. State the lane you take for the recurring question, and name whether a second memo call is permitted here.

Answer with three lines in exactly this form, choosing advisor or direct per line:
R-a: <lane>
R-b: <lane>
R-c: <lane>
--- rubric ---
require: R-a: advisor
require: R-b: direct
require: R-c: direct
require-if: R-c=>bar
tool-require: advisor
tool-max: advisor 1
