id: S15
title: Unit tiers are assigned and presented with the plan, floors never drop, design-bearing adds the second memo, and no dispatch precedes sign-off
ro-key: RO-257
flash: FL-03
body: skill-delegation
timeout: 600
fixture: s15-plan-input.md
--- prompt ---
The plan input is at s15-plan-input.md in this working directory. Present
the plan per your execution sign-off gate, following your unit-tiers
protocol, and answer with the four labeled lines the fixture asks for plus
the per-unit tier list, as your entire reply.
--- rubric ---
# ORCH-4-6-4 scenario for the delegation skill's Unit Tiers row (RO-257,
# touched by the tier-section compression within the recorded split). The
# graded decisions: every unit is tiered and the tiers reach the user with
# the plan, the design-bearing floor adds the second adversarial memo, no
# tier drops or relaxes a floor, and the presentation turn carries no
# execution dispatch (the gate is a turn boundary). The tier names are the
# skill's own vocabulary, pinned on the literal tier.
tier: semantics
require: TIERS: every unit carries its tier in the presentation
require: MEMO: design-bearing adds the second adversarial memo
require: FLOORS: no tier drops or relaxes a floor
require: DISPATCH: no dispatch in this turn
tool-forbid: worker
tool-forbid: verifier
tool-forbid: reviewer
tool-forbid: advisor
tool-forbid: scout
tool-forbid: planner
tier: literal
require: mechanical
require: standard
require: design-bearing
