# Representative Tier-B executions (ORCH-4-9-4): one scripted minimal
# scenario per fleet role, run against a seeded fixture board under the
# role's tier-b fixture config with direct .tasks access denied.
#
# Sourced by tests/task-access/test-tier-b.sh, which owns the harness
# counters (ok/bad/print_result), the ROOT temp dir, TIERB, AUDIT, and
# eval_perm; this module adds the execution environment and calls back
# into those counters, so everything here must run in the suite's parent
# shell (never inside $( ) or a pipeline).
#
# Scenario order is the real-workflow order: planner and worker prepare
# artifacts, reviewer reads the worker's deposit, advisor reads the
# parent, manager runs the claim/edit/close cycle over the worker's task
# and archives it, verifier renders the settled board, scout closes with
# zero task access. Every scenario command is gated against the role's
# fixture config first (a non-allow verdict refuses the command), records
# one transcript line per tool invocation, and retries a failure exactly
# once before it is investigated (a second failure lands in the failures
# log and fails the suite; it is never waived). Separate refusal demos
# prove the PATH shims reject direct .tasks arguments in this environment.
#
# Fixture boundary: sufficiency and discipline, not enforcement. The
# config gate models the dispatch environment's verdicts; the shims prove
# the direct shell routes fail; the native read tool has no modeled
# action, so the transcript audit covers that gap (V2 file_path class).
# The suite's own assertions may read the seeded fixture board directly
# (test-replay.sh's precedent); the audited transcripts are the roles',
# and none of them touches .tasks.
#
# The fixture board lives under TASKS_DIR="$ROOT/.tasks" with a pinned
# clock and one stable TASKS_SESSION, so the suite never writes the live
# board and every derived timestamp is deterministic.

EXEC_DIR="$ROOT/executions"
EXEC_TRANSCRIPTS="$EXEC_DIR/transcripts"
EXEC_SHIM="$EXEC_DIR/shims"
EXEC_TASKS="$REPO_ROOT/shell/.local/bin/tasks"
# The scenario commands spell the contract surface ("tasks <verb>"); this
# indirection resolves the leading token to the repo binary regardless of
# PATH (role-verbs.sh's consuming-suite contract; the verify container has
# no stowed tasks).
tasks() { "$EXEC_TASKS" "$@"; }
mkdir -p "$EXEC_TRANSCRIPTS" "$EXEC_SHIM" "$EXEC_DIR/territory"
: > "$EXEC_DIR/failures.log"
: > "$EXEC_DIR/retries.log"
export TASKS_DIR="$ROOT/.tasks"
export TASKS_TEST_CLOCK="2026-06-15 12:00"
export TASKS_SESSION="orch4-9-4-fixture"
EXEC_CMDS=0
EXEC_PARENT=""
EXEC_CHILD=""
EXEC_ARCHIVED=""

exec_make_shim() { # tool
	local tool="$1" real
	real="$(command -v "$tool")"
	{
		printf '#!/usr/bin/env bash\n'
		printf '# Fixture shim: refuses direct .tasks arguments, else execs the real tool.\n'
		printf 'for arg in "$@"; do\n'
		printf '\tcase "$arg" in\n'
		printf '\t*.tasks*)\n'
		printf '\t\tprintf "fixture-shim: %s refuses direct .tasks arguments\\n" "$(basename "$0")" >&2\n'
		printf '\t\texit 97\n'
		printf '\t\t;;\n'
		printf '\tesac\n'
		printf 'done\n'
		printf 'exec %q "$@"\n' "$real"
	} > "$EXEC_SHIM/$tool"
	chmod +x "$EXEC_SHIM/$tool"
}

# attempt_exec_cmd CMD...: one execution attempt under the normal PATH;
# prints combined output and returns the exit code. The single-attempt
# unit the retry loop (and its self-test) drive. The shims stay off the
# scenario PATH (the replay suite's precedent): the tasks CLI legitimately
# resolves .tasks internally through shell file tools, so a shimmed PATH
# would break the sanctioned surface itself; the refusal demo below proves
# the shims bite, and the config gate plus the transcript audit carry the
# denial.
attempt_exec_cmd() {
	eval "$*" </dev/null 2>&1
}

# exec_refused LABEL CMD...: run a command with the shims first on PATH
# and assert the refusal (exit 97, fixture-shim message), proving the
# direct routes fail in this execution environment before any role runs.
exec_refused() {
	local label="$1"; shift
	local o r
	o="$(PATH="$EXEC_SHIM:$PATH" "$@" </dev/null 2>&1)"
	r=$?
	if ((r == 97)) && [[ "$o" == *"fixture-shim:"* ]]; then ok "$label"; else bad "$label (exit $r: $o)"; fi
}

# retry_exec_cmd LABEL CMD...: run a scenario command, retrying a failure
# exactly once. A rescued failure is noted in retries.log; a command that
# fails twice is recorded in failures.log with its diagnostics and
# returns nonzero, where the caller reports it (never waived).
retry_exec_cmd() { # label cmd...
	local label="$1"; shift
	local out rc try
	for try in 0 1; do
		out="$(attempt_exec_cmd "$*")"
		rc=$?
		EXEC_CMDS=$((EXEC_CMDS + 1))
		((rc == 0)) && break
		if ((try == 0)); then
			printf 'RETRY[%s]: %s\n' "$label" "$out" >> "$EXEC_DIR/retries.log"
		else
			printf 'FAILED[%s]: %s\n' "$label" "$out" >> "$EXEC_DIR/failures.log"
		fi
	done
	return "$rc"
}

# role_run ROLE TRANSCRIPT LABEL CMD...: gate the command against the
# role's fixture config, record the transcript line, run it with one
# retry, and report a twice-failed command as an investigated failure.
# Piped commands are verdict-checked against the tasks invocation they
# carry (the cross-check's pipe-stripping rule).
role_run() { # role transcript label cmd...
	local role="$1" transcript="$2" label="$3"; shift 3
	local probe verdict
	probe="$*"
	if [[ "$probe" == *"| tasks "* ]]; then probe="${probe#*| }"; fi
	verdict="$(eval_perm "$TIERB/$role.yaml" shell "$probe")"
	if [[ "$verdict" != "allow" ]]; then
		bad "$role: fixture config blocks a scenario command [$*] (verdict: $verdict)"
		return 1
	fi
	printf '{"tool":"bash","command":"%s"}\n' "$*" >> "$transcript"
	if ! retry_exec_cmd "$label" "$@"; then
		bad "$role: scenario command failed after one retry [$*] (diagnostics: $EXEC_DIR/failures.log)"
		return 1
	fi
}

# role_read_tool ROLE TRANSCRIPT PATH: the native read tool on a
# territory path. opencode maps have no read action, so no config gate
# exists; the transcript audit's V2 class is the detection layer for the
# .tasks case, and this scenario line is the live demonstration that
# territory reads ride the gap-free path.
role_read_tool() { # role transcript path
	local role="$1" transcript="$2" path="$3"
	if [[ ! -f "$path" ]]; then
		bad "$role: read-tool target missing: $path"
		return 1
	fi
	printf '{"tool":"read","file_path":"%s"}\n' "$path" >> "$transcript"
	cat "$path" >/dev/null
	EXEC_CMDS=$((EXEC_CMDS + 1))
}

# role_write_tool ROLE TRANSCRIPT PATH: the write tool on a territory
# path, gated through the configs' edit action (the action opencode
# maps model for file writes).
role_write_tool() { # role transcript path content
	local role="$1" transcript="$2" path="$3" content="$4" verdict
	verdict="$(eval_perm "$TIERB/$role.yaml" edit "$path")"
	if [[ "$verdict" != "allow" ]]; then
		bad "$role: fixture config blocks a territory write [$path] (verdict: $verdict)"
		return 1
	fi
	printf '{"tool":"write","file_path":"%s"}\n' "$path" >> "$transcript"
	printf '%s\n' "$content" > "$path"
	EXEC_CMDS=$((EXEC_CMDS + 1))
}

exec_claim_generation() { # taskfile -> the claim's generation token on stdout
	sed -n 's/^generation //p' "$TASKS_DIR/current/$(basename "$1").claim" | head -1
}

# Seed: the parent the planner and advisor read (and the planner writes
# a plan note into), the worker's child with a seeded recon report the
# planner reads back, and a first Work Log checkpoint on the child.
exec_seed_board() {
	"$EXEC_TASKS" init >/dev/null
	EXEC_PARENT="$("$EXEC_TASKS" new --id EXEC-1 --name "Execution Seed Parent" --status Ready --priority High)"
	EXEC_CHILD="$("$EXEC_TASKS" new --id EXEC-2 --name "Execution Seed Child" --status Ready)"
	"$EXEC_TASKS" edit "$EXEC_PARENT" --section "Technical Approach" >/dev/null <<'EOF'
**Strategy:** seeded strategy PROVEMARK for the executions.

### Decision Log

**Decision: Seed Anchor** · 2026-06-15 12:00
EOF
	"$EXEC_TASKS" edit "$EXEC_PARENT" --section "Task Breakdown" >/dev/null <<'EOF'
### Task EXEC-1-1: Nested Child

**Status:** Ready

Nested heading body PROVEMARK inside the Task Breakdown.
EOF
	"$EXEC_TASKS" edit "$EXEC_PARENT" --section "Success Criteria" <<< "- [x] Seeded execution criterion (verdict: verified)" >/dev/null
	"$EXEC_TASKS" report "$EXEC_PARENT" --slug seed-recon --digest "seeded recon artifact" <<< "Seed recon body PROVEMARK for the planner execution read." >/dev/null
	"$EXEC_TASKS" log "$EXEC_CHILD" --from manager "seed checkpoint" >/dev/null
}

scenario_planner() {
	local role="planner" transcript="$EXEC_TRANSCRIPTS/planner.log"
	role_run "$role" "$transcript" planner-1 'tasks list --json' &&
	role_run "$role" "$transcript" planner-2 "tasks show $EXEC_PARENT" &&
	role_run "$role" "$transcript" planner-3 "tasks show $EXEC_PARENT --json" &&
	role_run "$role" "$transcript" planner-4 "tasks show $EXEC_PARENT --section \"Technical Approach\"" &&
	role_run "$role" "$transcript" planner-5 "tasks reports $EXEC_PARENT --include-body --json" &&
	role_run "$role" "$transcript" planner-6 "printf \"%s\\n\" \"Execution plan note PROVEMARK: fixture execution.\" | tasks edit $EXEC_PARENT --section \"Technical Approach\" --append" &&
	role_read_tool "$role" "$transcript" "$REPO_ROOT/tests/fixtures/task-access/verb-map.md" &&
	role_run "$role" "$transcript" planner-7 "tasks log $EXEC_PARENT --from planner \"planner execution checkpoint\"" &&
	role_run "$role" "$transcript" planner-8 "tasks report $EXEC_PARENT --slug fixture --from planner --digest \"planner execution deposit\" <<< \"Planner execution body PROVEMARK.\""
}

scenario_worker() {
	local role="worker" transcript="$EXEC_TRANSCRIPTS/worker.log"
	role_run "$role" "$transcript" worker-1 "tasks show $EXEC_CHILD --json" &&
	role_run "$role" "$transcript" worker-2 "tasks log $EXEC_CHILD --from worker \"worker execution interim\"" &&
	role_write_tool "$role" "$transcript" "$EXEC_DIR/territory/worker-artifact.md" "Worker territory artifact PROVEMARK." &&
	role_run "$role" "$transcript" worker-3 "tasks log $EXEC_CHILD --from worker \"worker execution complete\"" &&
	role_run "$role" "$transcript" worker-4 "tasks report $EXEC_CHILD --slug final --from worker --digest \"worker execution final\" <<< \"Worker execution body PROVEMARK.\""
}

scenario_reviewer() {
	local role="reviewer" transcript="$EXEC_TRANSCRIPTS/reviewer.log"
	role_run "$role" "$transcript" reviewer-1 "tasks show $EXEC_CHILD --json" &&
	role_run "$role" "$transcript" reviewer-2 "tasks show $EXEC_CHILD --section \"Work Log\"" &&
	role_run "$role" "$transcript" reviewer-3 "tasks reports $EXEC_CHILD --include-body --json" &&
	role_read_tool "$role" "$transcript" "$EXEC_DIR/territory/worker-artifact.md" &&
	role_run "$role" "$transcript" reviewer-4 "tasks report $EXEC_CHILD --slug review --from reviewer --digest \"reviewer execution findings\" <<< \"Review findings PROVEMARK.\""
}

scenario_advisor() {
	local role="advisor" transcript="$EXEC_TRANSCRIPTS/advisor.log"
	role_run "$role" "$transcript" advisor-1 "tasks show $EXEC_PARENT --section \"Technical Approach\"" &&
	role_run "$role" "$transcript" advisor-2 "tasks reports $EXEC_PARENT --include-body --json" &&
	role_run "$role" "$transcript" advisor-3 "tasks log $EXEC_PARENT --from advisor \"advisor execution note\"" &&
	role_run "$role" "$transcript" advisor-4 "tasks report $EXEC_PARENT --slug memo --from advisor --digest \"advisor execution memo\" <<< \"Advisor memo body PROVEMARK.\""
}

scenario_manager() {
	local role="manager" transcript="$EXEC_TRANSCRIPTS/manager.log" generation
	role_run "$role" "$transcript" manager-1 "tasks claim $EXEC_CHILD --owner orch4-9-4-fixture" &&
	role_run "$role" "$transcript" manager-2 "tasks show $EXEC_CHILD --json" &&
	role_run "$role" "$transcript" manager-3 "tasks edit $EXEC_CHILD --section \"Success Criteria\" <<< \"- [x] Execution criterion satisfied (verdict: verified)\"" &&
	role_run "$role" "$transcript" manager-4 "tasks set $EXEC_CHILD Progress=50%" &&
	role_run "$role" "$transcript" manager-5 "tasks log $EXEC_CHILD --from manager \"manager execution checkpoint\"" &&
	role_run "$role" "$transcript" manager-6 "tasks report $EXEC_CHILD --slug lifecycle --from manager --digest \"manager lifecycle deposit\" <<< \"Manager lifecycle body PROVEMARK.\"" &&
	role_run "$role" "$transcript" manager-7 "tasks list --json --lane \"In Progress\"" &&
	role_run "$role" "$transcript" manager-8 "tasks frontier --json" &&
	role_run "$role" "$transcript" manager-9 "tasks doctor --json" &&
	role_run "$role" "$transcript" manager-10 "tasks claims --json" &&
	role_run "$role" "$transcript" manager-11 "tasks events --json" &&
	role_run "$role" "$transcript" manager-12 "tasks lint" &&
	generation="$(exec_claim_generation "$EXEC_CHILD")" &&
	role_run "$role" "$transcript" manager-13 "tasks release $EXEC_CHILD --generation $generation" &&
	role_run "$role" "$transcript" manager-14 "tasks close $EXEC_CHILD" &&
	role_run "$role" "$transcript" manager-15 "tasks archive $EXEC_CHILD" &&
	EXEC_ARCHIVED="$(find "$TASKS_DIR/archive" -name "$(basename "$EXEC_CHILD")" | head -1)" &&
	[[ -n "$EXEC_ARCHIVED" ]] &&
	role_run "$role" "$transcript" manager-16 "tasks show $EXEC_ARCHIVED --json" &&
	role_run "$role" "$transcript" manager-17 "tasks render"
}

scenario_verifier() {
	local role="verifier" transcript="$EXEC_TRANSCRIPTS/verifier.log"
	role_run "$role" "$transcript" verifier-1 "git status --porcelain" &&
	role_run "$role" "$transcript" verifier-2 "make test-task-access-drift" &&
	role_run "$role" "$transcript" verifier-3 "tasks show $EXEC_ARCHIVED --json" &&
	role_run "$role" "$transcript" verifier-4 "tasks reports $EXEC_ARCHIVED --json" &&
	role_run "$role" "$transcript" verifier-5 "tasks render" &&
	role_run "$role" "$transcript" verifier-6 "tasks render"
}

scenario_scout() {
	local role="scout" transcript="$EXEC_TRANSCRIPTS/scout.log"
	role_read_tool "$role" "$transcript" "$REPO_ROOT/tests/fixtures/task-access/README.md"
}

run_representative_executions() {
	local role transcript o audit_rc before_dashboard
	echo "== representative executions: seeded fixture board =="
	for role in cat grep ls wc find sed awk head tail; do
		exec_make_shim "$role"
	done
	exec_seed_board
	[[ -f "$EXEC_PARENT" && -f "$EXEC_CHILD" ]] &&
		ok "fixture board seeded (parent, child, recon report)" ||
		{ bad "fixture board seeded (parent, child, recon report)"; return; }
	echo "== fixture boundary =="
	echo "  Sufficiency and discipline, not enforcement: the tier-b configs' edit"
	echo "  and shell denies are modeled by the config gate, PATH shims refuse the"
	echo "  direct shell routes, and the transcript audit covers the read-tool gap"
	echo "  (opencode maps have no read action). Hard enforcement is ORCH-4-10's."

	echo "== scenario order: planner, worker, reviewer, advisor, manager, verifier, scout =="
	exec_refused "direct cat of a fixture task path is refused" cat "$EXEC_PARENT"
	exec_refused "direct grep of the fixture board is refused" grep PROVEMARK "$TASKS_DIR/dashboard.md"
	exec_refused "direct ls of the fixture board is refused" ls "$TASKS_DIR"
	scenario_planner || bad "planner: representative execution aborted"
	scenario_worker || bad "worker: representative execution aborted"
	scenario_reviewer || bad "reviewer: representative execution aborted"
	scenario_advisor || bad "advisor: representative execution aborted"
	scenario_manager || bad "manager: representative execution aborted"
	before_dashboard="$(cat "$TASKS_DIR/dashboard.md")"
	scenario_verifier || bad "verifier: representative execution aborted"
	assert_eq "verifier: render idempotent over the settled board" "$before_dashboard" "$(cat "$TASKS_DIR/dashboard.md")"
	scenario_scout || bad "scout: representative execution aborted"

	echo "== transcript audit: zero direct .tasks access per role =="
	for role in "${TASK_ACCESS_ROLES[@]}"; do
		transcript="$EXEC_TRANSCRIPTS/$role.log"
		if [[ ! -s "$transcript" ]]; then
			bad "$role: execution transcript exists and is nonempty"
			continue
		fi
		AUDIT_OUT="$(bash "$AUDIT" "$transcript" 2>&1)"
		AUDIT_RC=$?
		if ((AUDIT_RC == 0)); then
			ok "$role: transcript audits clean (zero direct .tasks access)"
		else
			bad "$role: transcript audits clean (audit exit $AUDIT_RC: $AUDIT_OUT)"
		fi
	done
	AUDIT_OUT="$(bash "$AUDIT" "$EXEC_TRANSCRIPTS"/*.log 2>&1)"
	AUDIT_RC=$?
	((AUDIT_RC == 0)) && ok "all ${#TASK_ACCESS_ROLES[@]} transcripts audit clean together" ||
		bad "all ${#TASK_ACCESS_ROLES[@]} transcripts audit clean together (audit exit $AUDIT_RC)"
	assert_eq "every scenario command retried at most once" "0" "$(wc -l < "$EXEC_DIR/failures.log")"
	if (( $(wc -l < "$EXEC_DIR/retries.log") > 0 )); then
		echo "  retried-once commands (rescued, never waived):"
		sed 's/^/    /' "$EXEC_DIR/retries.log"
	fi

	echo "== retry runner self-test (fail once rescued, fail twice investigated) =="
	printf '#!/usr/bin/env bash\n(( $(cat "'"$EXEC_DIR"'/selftest.count" 2>/dev/null || echo 0) >= 1 )) && exit 0\necho 1 > "'"$EXEC_DIR"'/selftest.count"\nexit 1\n' > "$EXEC_SHIM/fail-once"
	printf '#!/usr/bin/env bash\nexit 3\n' > "$EXEC_SHIM/fail-always"
	chmod +x "$EXEC_SHIM/fail-once" "$EXEC_SHIM/fail-always"
	rm -f "$EXEC_DIR/selftest.count"
	retry_exec_cmd selftest-once "bash $EXEC_SHIM/fail-once" &&
		ok "retry runner: a fail-once command is rescued by its single retry" ||
		bad "retry runner: a fail-once command is rescued by its single retry"
	retry_exec_cmd selftest-always "bash $EXEC_SHIM/fail-always" &&
		bad "retry runner: a fail-twice command is investigated, not waived" ||
		ok "retry runner: a fail-twice command is investigated, not waived"
	assert_contains "rescued retry noted in the retries log" "$(cat "$EXEC_DIR/retries.log")" "RETRY[selftest-once]"
	assert_contains "investigated failure recorded with diagnostics" "$(cat "$EXEC_DIR/failures.log")" "FAILED[selftest-always]"
	: > "$EXEC_DIR/failures.log"
	: > "$EXEC_DIR/retries.log"

	echo "== execution outcomes round-trip through the authorized reads =="
	o="$("$EXEC_TASKS" reports "$EXEC_ARCHIVED" --json)"
	assert_contains "worker deposit indexed with provenance" "$o" "worker execution final"
	assert_contains "reviewer findings deposited on the child" "$o" "reviewer execution findings"
	o="$("$EXEC_TASKS" reports "$EXEC_PARENT" --include-body --json)"
	assert_contains "planner deposit body readable through reports" "$o" "Planner execution body PROVEMARK."
	assert_contains "advisor memo body readable through reports" "$o" "Advisor memo body PROVEMARK."
	o="$("$EXEC_TASKS" show "$EXEC_PARENT" --section "Technical Approach")"
	assert_contains "planner edit write round-trips through show" "$o" "Execution plan note PROVEMARK"
	o="$("$EXEC_TASKS" show "$EXEC_ARCHIVED" --json)"
	assert_contains "manager archived the child and it stays readable" "$o" '"archived":true'
	assert_contains "archived child carries the closed status" "$o" '"Status":"Completed"'
	assert_contains "manager set the header field" "$o" '"Progress":"50%"'
	assert_eq "scout transcript names no tasks invocation" "0" "$(grep -c '"command":"tasks ' "$EXEC_TRANSCRIPTS/scout.log")"

	echo "== board hygiene after the seven executions =="
	"$EXEC_TASKS" lint >/dev/null && ok "fixture board lint-clean after all executions" ||
		bad "fixture board lint-clean after all executions"
	o="$("$EXEC_TASKS" doctor --json)"
	assert_contains "doctor reports zero findings on the fixture board" "$o" '"total":0'
	ok "representative executions complete ($EXEC_CMDS command/tool invocations across ${#TASK_ACCESS_ROLES[@]} roles)"
}
