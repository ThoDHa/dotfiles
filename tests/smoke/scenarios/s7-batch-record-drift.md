id: S7
title: Batch record-drift watchdog audit fires before closure, with the proportionality carve stated
ro-key: RO-267
flash: FL-05
timeout: 1200
fixture: s7-board.md
fixture: s7-reality.md
--- prompt ---
All three units report complete and the board shows every closure surface recorded; you are at batch close. The batch's tracking records are at s7-board.md; the reality snapshot pulled for the close is at s7-reality.md.

Run your batch-closure duty over records versus reality before you accept the board's closure state. Then answer with three lines in exactly this form, choosing one on the first two:
AUDIT: dispatched
AUDIT: skipped
AUDIT: blocked
CLOSED: yes
CLOSED: no
PROPORTION: <name the closure surfaces (seam review, watchdog audit, or both) that a single-mechanical-unit batch whose records match reality would get>
--- rubric ---
tool-require: advisor
require: AUDIT: dispatched
require: disposition
require-if: PROPORTION=>seam review
require-any: no watchdog|without a watchdog|no watchdog audit|alone|only the seam review
