id: S16
title: Delegation as default dispatches the delegable item, absorbs only the bounded quick task, and defaults to delegation when uncertain
ro-key: RO-253
flash: -
body: skill-delegation
timeout: 600
fixture: s16-intake.md
--- prompt ---
The intake file is at s16-intake.md in this working directory. Carry out
both items now per your delegation protocol: perform the work each decision
requires, dispatching where your protocol says to dispatch (do not merely
announce the dispatch), and answer with the three labeled lines the fixture
asks for, as your final reply once both items are done.
--- rubric ---
# ORCH-4-6-4 scenario for the delegation skill's Delegation as Default row
# (RO-253, seam A's skill side, touched by the borderline-default duplicate
# collapse) with its RO-254 boundary mechanics. The graded decisions: the
# bounded quick lookup stays direct, the hour-long feature dispatches to the
# available worker, and the uncertainty tie-break lands on delegation. The
# tool checks pin the dispatch actually happening for the feature only: a
# session that absorbs the feature or dispatches the lookup failed the
# quick-task bound.
tier: semantics
require: LOOKUP: do it yourself directly
require: FEATURE: dispatch it
require: WHEN-UNCERTAIN: default to delegation
tool-require: worker
tool-max: worker 1
tool-forbid: scout
