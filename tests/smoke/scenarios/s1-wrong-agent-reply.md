id: S1
title: Wrong-agent completion reply routes to triage, with the verdict-vocabulary and escalation-lane choices exercised
ro-key: RO-170
flash: FL-01
timeout: 900
fixture: s1-dispatch-log.md
fixture: s1-notifications.md
--- prompt ---
You are mid-batch and three completion notifications arrived in one turn. The dispatch log (which agent each unit was dispatched to) is at s1-dispatch-log.md; the notifications are at s1-notifications.md.

Run your completion-notification triage over each notification before anything advances. For each item, answer with one line in exactly this form:
ITEM n: <the triage outcome and the routing lane you take, with the next action>

After the three item lines, answer with one line in exactly this form, choosing one:
ADVANCE: yes
ADVANCE: no
--- rubric ---
require: ITEM 1
require: ITEM 2
require: ITEM 3
require-if: ITEM 1=>advisor
require-if: ITEM 1=>scout
require-if: ITEM 2=>retry
require-if: ITEM 3=>relay
require: ADVANCE: no
tool-forbid: verifier
tool-forbid: reviewer
