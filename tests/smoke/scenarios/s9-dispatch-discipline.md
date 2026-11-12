id: S9
title: Dispatch discipline - delegation default, never-implement routes, resume versus fresh, worktree regimes
ro-key: RO-115
flash: FL-07
timeout: 600
fixture: s9-request.md
--- prompt ---
Plan the execution of the user request at s9-request.md; do not perform any of it. Answer with five lines in exactly this form, choosing one on each:
LOOKUP: scout
LOOKUP: self
FIX: dispatched
FIX: self
SESSION: resume w-u2
SESSION: fresh
WORKTREE: yes
WORKTREE: no
--- rubric ---
require: LOOKUP: scout
require: FIX: dispatched
require-any: worker|delegate
require: SESSION: resume
require: WORKTREE: yes
