# Plan input (fixture, no real task data)

The user asked for this work; the approach is already settled and the user
said "go ahead and present the plan". Three units make up the work:

- u-rename: rename the internal helper `fetch_data` to `load_records`
  across one module; mechanical, no behavior change.
- u-feature: add a CSV export endpoint with tests; straightforward feature
  work on an existing service.
- u-protocol: redesign the service's client authentication protocol; new
  architecture whose shape embeds design decisions, touching auth.

Present the plan per your sign-off gate. Answer with four lines in exactly
this form, choosing one on each:

TIERS: every unit carries its tier in the presentation
TIERS: tiers omitted from the presentation
MEMO: design-bearing adds the second adversarial memo
MEMO: no memo beyond the standard review anywhere
FLOORS: no tier drops or relaxes a floor
FLOORS: the mechanical tier skips verification
DISPATCH: no dispatch in this turn
DISPATCH: dispatch the first worker in this turn

Then list each unit with its tier in at most three further lines.
