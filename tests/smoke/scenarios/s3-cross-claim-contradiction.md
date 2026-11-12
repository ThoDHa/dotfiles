id: S3
title: Cross-claim contradiction between the worker report and the pulled evidence stops the advance
ro-key: RO-170
flash: FL-01
timeout: 900
fixture: s3-report.md
fixture: s3-evidence.md
--- prompt ---
A worker completion arrived for unit U9; the report excerpt is at s3-report.md. Your comparison snapshot of the actual suite state for the claimed commit is at s3-evidence.md.

Run your completion triage over the report against that evidence. Answer with three lines in exactly this form:
CONTRADICTION: <the claims that contradict each other, with the substance>
ADVANCE: yes
ADVANCE: no
NEXT: <the lane you route to and the action>
--- rubric ---
require: CONTRADICTION:
require: ADVANCE: no
require-if: CONTRADICTION=>fail
require-any: advisor|reconcil|rule 8|resume unit|dispatch worker|worker lane|worker session
tool-forbid: verifier
tool-forbid: reviewer
