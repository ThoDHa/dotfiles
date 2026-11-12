REVIEWER DEPOSIT (unit U7 review, adversarial pass)

Verdict: FAIL - the worktree teardown step deletes in-use branches when a unit
is parked; reproduces on 3 of 3 trials with a parked unit.

Findings:
  F1 (major): teardown removes the branch before checking the parked status;
      a parked unit's worktree persists by charter, so the deletion path must
      exclude parked units.
  F2 (minor): the teardown log line prints "removed" even when the branch
      delete is skipped.

Deposited at .tasks/reports/r9-review.md; transcript linked there.
