ADVISOR MEMO - design challenge relayed for ruling (unit U5, worktree teardown)

The reviewer's challenge, verbatim from its findings deposit:

  "DESIGN CHALLENGE: the teardown ordering is wrong. Deleting the branch
   before checking the parked status loses parked units' worktrees (your
   own charter keeps a parked unit's worktree alive). Two alternatives:
   (A) audit-before-delete: recheck unit status inside the teardown
   transaction, costs about +40 lines and a second board read per
   teardown; (B) status-flag guard: skip deletion on a parked flag, costs
   +8 lines but the flag can go stale mid-teardown (a race the board's
   atomic claim does not cover). My challenge: B is insufficient as the
   only guard. Ruling needed: A, B, or defer to a tracked task."

Facts you hold: the fleet is idle except this unit; the user is away from
the keyboard this turn; the unit is design-bearing; no standing waiver
exists.
