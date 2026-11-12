USER REQUEST (arrived this turn)

"Find every place the ratchet registry value is mirrored in the repo, fix
the stale mirror, and add a regression test for it."

Facts you hold:
- Fleet workers are available and idle.
- Another unit (U3) is in flight right now in its own worktree; it is
  unrelated territory.
- Worker session w-u2 finished the neighboring parser unit minutes ago;
  its session is still warm and nothing occupies it; the mirror fix
  continues over territory that session already holds.
- The lookup (where the value is mirrored) is a single verbatim question.
