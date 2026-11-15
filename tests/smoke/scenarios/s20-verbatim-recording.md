id: S20
title: The report body lives verbatim in the deposited report file and the Work Log carries only the link and the digest
ro-key: RO-236
flash: -
body: skill-task-files
timeout: 600
fixture: s20-report.md
--- prompt ---
Your dispatched reviewer just returned from reviewing AUTH-7. Its full
report body is in s20-report.md, and the deposit went through
tasks report already. Record the report per your protocol and answer
with three labeled lines, as your entire reply:
ENTRY: <what the Work Log entry for this report carries>
BODY: <where the full report content lives and in what form>
ANALYSIS: <what your own Work Log analysis adds>
--- rubric ---
# ORCH-4-6-4 task-files pass scenario for RO-236 (verbatim recording;
# the Agent-Report-Entries no-copy restatement collapsed to the Verbatim
# Recording Requirement owner, which retains the rule byte-identical).
# The graded decisions: the Work Log entry carries the link and the
# agent-supplied digest only, the full body lives verbatim in the
# deposited report file under the reports namespace, and the manager's
# own analysis is an independent reading and a check on the digest,
# never a copy or paraphrase of the body into the log. Reply-stated
# decisions; no dispatches.
tier: semantics
require: ENTRY:
require: BODY:
require: ANALYSIS:
require-any: digest|link
require-any: reports/|report file|verbatim|deposited
require-any: independent|not a restatement|not a copy|own reading|my own|check on
tool-forbid: worker
tool-forbid: reviewer
tool-forbid: verifier
tool-forbid: advisor
tool-forbid: scout
tool-forbid: planner
tier: literal
require: verbatim
