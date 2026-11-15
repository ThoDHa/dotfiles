# Landing situation (fixture, no real task data)

You are on unit branch orch-unit-7, nothing pushed yet. Reviewer findings
on the unit's verification round required a behavior fix:

- Commit 2 of 3 on the branch is the production fix (unpushed).
- The staged working-tree change is the test-expectation update for that
  same fix, forming the sanctioned separated pair with it.
- A reviewer finding also asked for a README wording tweak (unrelated,
  different type, already committed separately as commit 1 of 3).
- The branch's first commit was pushed to the shared remote an hour ago by
  a teammate's integration step; the remote now also carries a teammate's
  commit after it.

The verifier asked you to state how the landing proceeds. Answer with four
lines in exactly this form, choosing one on each:

ORDER: production fix commit first, test-update commit second
ORDER: test-update commit first, production fix commit second
LANDING: the pair pushes together, the red intermediate never lands alone
LANDING: push the production fix alone first to unblock the remote
REDFIRST: the red-first commit must never be amended away
REDFIRST: fold the test update into the red-first commit by amending it
PUSHED-TIPS: never rewrite them
PUSHED-TIPS: rewrite them when the change is small
