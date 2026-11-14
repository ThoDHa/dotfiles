# Machine-readable per-role authorized task-access command sets.
#
# The executable form of tests/fixtures/task-access/verb-map.md: the replay
# suite (tests/task-access/test-replay.sh) expands and runs exactly these
# commands against a seeded TASKS_DIR fixture board, and the Tier-B suite
# (tests/task-access/test-tier-b.sh) derives each role's allowed `tasks <verb>`
# tokens from them to cross-check the fixture configs. verb-map.md must stay
# in sync with this file, and the Tier-B suite pins the coupling
# bidirectionally: every `tasks <verb>` citation in a role's row appears in
# its executable set, and every executable verb is cited in its row.
#
# Each entry is a shell command line the replay executor evals after
# substituting {{PLACEHOLDER}} tokens:
#
#   {{PARENT}}      seeded parent task file (planner/advisor reads, manager close/archive)
#   {{CHILD}}       seeded child task file (worker writes, reviewer reads)
#   {{NEWFILE}}     task file the manager replay creates via `tasks new`
#   {{GENERATION}}  claim generation token (suite refreshes it after `tasks claim`)
#   {{ARCHIVED}}    the parent's path under archive/ (suite refreshes after `tasks archive`)
#
# The consuming suite defines tasks() { "$TASKS_BIN" "$@"; } before eval, so the
# leading `tasks` token resolves to the repo binary regardless of PATH. Role
# order in TASK_ACCESS_ROLES is the replay order: the worker runs before the
# reviewer so the reviewer scenario reads the worker scenario's deposited
# report, and the manager set runs last among the task-consuming roles so its
# archive step does not race earlier reads of the parent. Scout's set is empty
# by contract (zero-diff role).

TASK_ACCESS_ROLES=(planner worker reviewer advisor manager scout verifier)

ROLE_COMMANDS_planner=(
	'tasks list --json'
	'tasks show {{PARENT}}'
	'tasks show {{PARENT}} --json'
	'tasks show {{PARENT}} --raw'
	'tasks show {{PARENT}} --section "Technical Approach"'
	'tasks reports {{PARENT}} --json'
	'tasks reports {{PARENT}} --include-body --json'
	'printf "%s\n" "Fixture risk note PROVEMARK." | tasks edit {{PARENT}} --section "Technical Approach" --append'
	'tasks log {{PARENT}} --from planner "planner replay checkpoint"'
	'tasks report {{PARENT}} --slug replay --from planner --digest "planner replay deposit" <<< "Planner report body PROVEMARK."'
)

ROLE_COMMANDS_reviewer=(
	'tasks show {{CHILD}} --json'
	'tasks show {{CHILD}} --raw'
	'tasks show {{CHILD}} --section "Work Log"'
	'tasks reports {{CHILD}} --json'
	'tasks reports {{CHILD}} --include-body --json'
	'tasks list --json'
	'tasks report {{CHILD}} --slug review --from reviewer --digest "review replay verdict" <<< "Review body PROVEMARK."'
)

ROLE_COMMANDS_worker=(
	'tasks show {{CHILD}} --json'
	'tasks show {{CHILD}} --raw'
	'tasks log {{CHILD}} --from worker "worker replay interim"'
	'tasks report {{CHILD}} --slug final --from worker --digest "worker replay final" <<< "Worker final body PROVEMARK."'
)

ROLE_COMMANDS_advisor=(
	'tasks show {{PARENT}} --section "Technical Approach"'
	'tasks show {{PARENT}} --json'
	'tasks show {{PARENT}} --raw'
	'tasks reports {{PARENT}} --json'
	'tasks reports {{PARENT}} --include-body --json'
	'tasks list --json'
	'tasks log {{PARENT}} --from advisor "advisor replay note"'
	'tasks report {{PARENT}} --slug memo --from advisor --digest "advisor replay memo" <<< "Advisor memo body PROVEMARK."'
)

ROLE_COMMANDS_manager=(
	'tasks init'
	'tasks new --id MANAGER-1 --name "Manager Lifecycle Seed" --status Ready'
	'tasks claim {{NEWFILE}} --owner orch4-9-1-fixture'
	'tasks edit {{NEWFILE}} --section "Success Criteria" <<< "- [x] Lifecycle criterion (verdict: verified)"'
	'tasks set {{NEWFILE}} Progress=25%'
	'tasks log {{NEWFILE}} --from manager "manager replay checkpoint"'
	'tasks report {{NEWFILE}} --slug lifecycle --from manager --digest "manager lifecycle deposit" <<< "Manager lifecycle body PROVEMARK."'
	'tasks show {{NEWFILE}} --json'
	'tasks list --json --lane "In Progress"'
	'tasks show {{PARENT}} --section "Technical Approach"'
	'tasks show {{PARENT}} --raw'
	'tasks reports {{CHILD}} --include-body --json'
	'tasks frontier --json'
	'tasks doctor --json'
	'tasks claims --json'
	'tasks events --json'
	'tasks lint'
	'tasks release {{NEWFILE}} --generation {{GENERATION}}'
	'tasks close {{PARENT}}'
	'tasks stamp {{PARENT}}'
	'tasks archive {{PARENT}}'
	'tasks show {{ARCHIVED}} --json'
	'tasks export --format jsonl --include-reports'
	'tasks reclaim {{NEWFILE}} --owner orch4-9-1-fixture'
	'tasks render'
)

# Empty by contract: the scout names no task-file access and gains none
# (verb-map.md, scout entry). The replay asserts the emptiness instead of
# running commands.
ROLE_COMMANDS_scout=()

ROLE_COMMANDS_verifier=(
	'tasks render'
)
