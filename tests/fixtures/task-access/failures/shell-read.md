# Planted failure fixture: direct shell reads of .tasks paths (P2 tool-path)

Read the seeded task with `cat .tasks/current/seeded-task.md`, then run
`grep PROVEMARK .tasks/current/seeded-task.md` and page it with
`sed -n 1,20p .tasks/current/seeded-task.md`.
