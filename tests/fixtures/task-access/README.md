# Task-Access Fixture Harness

The ORCH-4-9 test harness proving the seven fleet roles' migration from direct
`.tasks/` access to CLI-only access. The contract artifact is `verb-map.md` in this
directory (its executable form is `role-verbs.sh`); the suites live in
`tests/task-access/` and are wired into `make verify-inner` through the
`test-task-access-drift`, `test-task-access-replay`, and `test-task-access-tierb` targets.

## Layout

- `verb-map.md`: the per-role contract (authorized reads, write channels, map deltas, replaced direct-access patterns, parity proof), reconciled against the landed CLI with deviations recorded.
- `role-verbs.sh`: the machine-readable per-role command sets the suites consume; byte-faithful to `verb-map.md`.
- `migrated-surfaces.txt`: the drift check's list; EMPTY at this landing, extended per stage by ORCH-4-9-2 and ORCH-4-9-3.
- `failures/`: red-capability fixtures covering the drift-check pattern classes (the uncited-mention class carries several, including the verb-less and deposit-stem corpus phrasings); the drift suite plants each in a temp tree and proves the check goes red.
- `tier-b/`: per-role fixture dispatch configs (edit and shell denies) for the ORCH-4-9-4 representative executions.

## Fixture Boundary

Sufficiency and discipline, not enforcement. The replay suite proves each role's authorized command set returns everything the role needs without direct task-file access; the shims, the fixture configs, and the transcript audit prove the direct routes are refused and detect any direct access. Nothing here is a filesystem boundary: opencode maps have no read action, so the native read tool is audit-covered only, and deny-first roles close interpreter and write-tool routes through their catch-all deny while the allow-first roles (worker, manager) deny them explicitly in their fixture denial tails, with the audit's V1 class detecting the same routes in transcripts; hard enforcement with bypass tests is ORCH-4-10's work. Every suite pins `TASKS_DIR` to a temp root and never writes the live board.

Two drift-check mechanisms serve the migrated-surfaces list. Text patterns scan listed prose: any non-fenced line naming `.tasks` must cite a `tasks <verb>` on the same line or carry the `task-access-sanctioned` marker, and an odd fence count at EOF is itself a finding. Permission-map-bearing surfaces are listed as `<path> @<role>` instead: their frontmatter is machine data, so the check map-diffs the live frontmatter's `.tasks` edit rules against `tier-b/<role>.yaml` above that config's fixture-denial-tail marker (`# fixture denial tail (fixture-only rules; not part of the target map)`), which keeps the manager's retained interim allow green while its target map retains it and turns any live rule the target does not carry into a finding. The Tier-B suite separately pins realizability: every sanctioned exception must yield ALLOW under its role's fixture config.
