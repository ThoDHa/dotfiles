UNIT U7 INTEGRATION FACTS

Unit U7 passed verification and review. Branch orch/u7 (base 6a70ed1)
carries the unit's commit checkpoints:
- c0 "feat: slim the parser dispatch" - already pushed to the remote
  earlier in the unit's life (the user saw it); a reviewer noted a typo
  in its commit message.
- c1 "fix: parse dispatch budget tie" - the production fix for the
  review's finding; landed AFTER c0 as the first commit of the sanctioned
  ordered pair (production fix first, test expectations second).
- c2 "test: pin the parse dispatch contract" - the second commit of that
  ordered pair (the test-expectation commit for c1's fix).
- c3 "refactor: rename the parse helper" - an unrelated mechanical change
  the worker made in passing; separate concern.
The unit's worktree under .worktrees/orch-u7 still stands. A reviewer
suggestion ("fix the docstring drift in parse_helper") was dispositioned
done-now but the worker finished without applying it.
