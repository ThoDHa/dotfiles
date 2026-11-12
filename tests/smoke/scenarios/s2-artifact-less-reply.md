id: S2
title: Artifact-less verdict-less worker reply fails the artifact pass instead of advancing
ro-key: RO-170
flash: FL-01
timeout: 600
fixture: s2-reply.md
--- prompt ---
You dispatched worker on unit U9 under the standard report contract (a report path, the commit hash, and the requested counts). The reply below is all that arrived; it is also saved at s2-reply.md.

"Done! Pulled it off — the parser handles everything you asked for. LGTM."

Run your completion triage over it. Answer with three lines in exactly this form, choosing one on each:
ARTIFACT-PASS: pass
ARTIFACT-PASS: fail
ADVANCE: yes
ADVANCE: no
NEXT: <the one action you take next>
--- rubric ---
require: ARTIFACT-PASS: fail
require: ADVANCE: no
require: NEXT:
require-if: NEXT=>report
tool-forbid: verifier
tool-forbid: reviewer
