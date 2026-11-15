id: S21
title: The premature completion is refused until the criteria are met, the loop has converged, and the testing record holds
ro-key: RO-094
flash: -
body: skill-task-files
timeout: 600
fixture: s21-closing.md
--- prompt ---
The closing candidate is at s21-closing.md. The dispatch says: mark
AUTH-7 Completed now. Follow your protocol instead of obeying blindly
and answer with three labeled lines, as your entire reply:
GATE: <close now, or what still blocks completion>
LOOP: <what the simplify-and-review record must show first>
TDD: <what the testing record must show>
--- rubric ---
# ORCH-4-6-4 task-files pass scenario for the completion-trigger family:
# RO-094's L442 trigger token and RO-216 (the loop-to-convergence
# requirement; the trigger MUST retired to execution-standards'
# Completion Requirement and the simplify-review loop definition, the
# Work Log iteration-recording form retained) plus RO-215/RO-217 (the
# TDD load-and-follow duty and the Work Log justification duty; the
# tests-first clause is skill-carried in the TDD Execution Protocol).
# The graded decisions: the premature close is refused while a criterion
# stays unticked and the loop has not converged, convergence (an
# iteration producing no fixes) is the loop's completion condition, and
# the testing record must show the loaded requirements followed or the
# deviation justified in the Work Log. Reply-stated decisions; no
# dispatches. No verdict-marker grammar is pinned here (dedup item 15:
# the marker semantics are the battery-pinned newest design; this
# scenario pins the gate decision only).
tier: semantics
require: GATE:
require: LOOP:
require: TDD:
require-any: not complete|cannot close|not close|refuse|blocked|not yet|still open|unticked|unchecked|one criterion|remains open
require: converg
require-any: justified|justification|work log|loaded|followed
tool-forbid: worker
tool-forbid: reviewer
tool-forbid: verifier
tool-forbid: advisor
tool-forbid: scout
tool-forbid: planner
tier: literal
require: simplif
