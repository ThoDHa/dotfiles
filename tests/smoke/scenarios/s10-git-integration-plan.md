id: S10
title: Git integration plan preserves the ordered pair, pushed tips, staging scope, and teardown
ro-key: RO-063
flash: -
timeout: 600
fixture: s10-integration.md
--- prompt ---
Unit U7 passed verification and review; the facts are at s10-integration.md. The user asked you to integrate and push U7. State your integration plan (do not execute it), answering with five lines in exactly this form:
SQUASH: <what squashes with what, or nothing>
SEPARATE: <what stays a separate commit and why>
AMEND: <whether anything is amended, and what the pushed-tip rule says>
SUGGESTION: <how the docstring suggestion lands>
TEARDOWN: <what happens to the unit worktree after integration>
--- rubric ---
require: SQUASH:
require: SEPARATE:
require-if: SQUASH=>separate
require: AMEND:
forbid: amend c0
require-if: AMEND=>pushed
require: SUGGESTION:
require: TEARDOWN:
require-if: TEARDOWN=>tear
