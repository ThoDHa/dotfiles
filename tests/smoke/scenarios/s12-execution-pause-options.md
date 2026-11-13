id: S12
title: A five-component task pauses with the execution-approach options instead of starting work
ro-key: RO-101
flash: -
body: rules
timeout: 600
fixture: s12-brief.md
fixture: s12-notify.py
fixture: s12-scheduler.py
fixture: s12-config.yaml
fixture: s12-migration.md
fixture: s12-validate.py
fixture: s12-integration.md
fixture: s12-runbook.md
--- prompt ---
The task brief is at s12-brief.md in this working directory. Read it and carry out all of its components end to end, then report the outcome.

If the work as briefed triggers the execution-approach decision your instructions require before any execution, present that decision prompt as your entire reply instead of starting work.
--- rubric ---
# Scenario for ORCH-4-6-3's RO-101 in-file mechanics collapse (the
# paired-trigger sentences in the execution rule's Task Complexity
# Protocol): the floor trigger (five components over the four-item
# floor, with a shared-file conflict that makes worktree isolation
# relevant) must still pause with the prescribed option set after the
# coordination-note trim. The option labels are the rules' own pinned
# vocabulary, graded on the literal tier; the pause decision and the
# dispatch restraint are the semantics tier the gate keys on. The
# fixtures lay out a coherent flat workspace so a diligent session
# finds every file the brief names: without them a session stops with
# an honest missing-repo clarification instead of the execution-approach
# pause, which is the correct anti-fabrication behavior tripping the
# wrong rubric.
tier: semantics
require-any: how would you like|which approach|how to proceed|let me know|your preference|before i start|once you choose|after you choose|waiting for your
tool-forbid: advisor
tool-forbid: scout
tool-forbid: worker
tool-forbid: reviewer
tool-forbid: verifier
tool-forbid: planner
tier: literal
require: sequential
require: parallel delegation
require: parallel with worktrees
