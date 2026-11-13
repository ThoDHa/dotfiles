#!/usr/bin/env bash
#
# Tier-B fixture harness skeleton suite (ORCH-4-9-1). Validates the per-role
# fixture dispatch configs under tests/fixtures/task-access/tier-b/ with an
# ordered-rule evaluator implementing opencode's documented semantics (rules
# evaluated in order, the last matching rule wins, glob-style resource
# matching), proves every role's fixture denies the direct .tasks routes
# (the denial demonstration), cross-checks each role's authorized command
# set from the executable verb map against its config, and proves the
# transcript audit red on planted direct-access transcripts and green on a
# clean one.
#
# The representative executions themselves are ORCH-4-9-4's; this suite
# proves the skeleton they will run under.
#
# Fixture boundary: sufficiency and discipline, not enforcement. The
# evaluator models the configs' verdicts; the audit detects direct access;
# nothing here is a filesystem boundary (ORCH-4-10's work).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TIERB="$REPO_ROOT/tests/fixtures/task-access/tier-b"
AUDIT="$REPO_ROOT/tests/task-access/audit-transcript.sh"
VERB_MAP="$REPO_ROOT/tests/fixtures/task-access/verb-map.md"

source "$REPO_ROOT/tests/lib/harness.sh"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# shellcheck source=/dev/null
source "$REPO_ROOT/tests/fixtures/task-access/role-verbs.sh"

RULE_RE='\{[[:space:]]*action:[[:space:]]*([^,]+),[[:space:]]*resource:[[:space:]]*("[^"]*"|[^,]+),[[:space:]]*effect:[[:space:]]*([^}]+)\}$'
eval_perm() { # config action probe -> verdict on stdout (allow|deny|ask|default)
	local config="$1" action="$2" probe="$3"
	local rule act res eff verdict="default" lead trail
	while IFS= read -r rule; do
		# Parse one opencode rule line: { action: A, resource: R, effect: E }
		if [[ "$rule" =~ $RULE_RE ]]; then
			act="${BASH_REMATCH[1]}"; act="${act//[[:space:]]/}"
			res="${BASH_REMATCH[2]}"
			lead="${res%%[![:space:]]*}"; trail="${res##*[![:space:]]}"
			res="${res#"$lead"}"; res="${res%"$trail"}"
			eff="${BASH_REMATCH[3]}"; eff="${eff//[[:space:]]/}"
			# strip surrounding quotes from the resource pattern
			res="${res%\"}"; res="${res#\"}"
			[[ "$act" == "$action" ]] || continue
			# opencode glob semantics: * crosses any characters, so a
			# bash pattern match models it directly
			if [[ "$probe" == $res ]]; then
				verdict="$eff"
			fi
		fi
	done < "$config"
	printf '%s' "$verdict"
}

expect_verdict() { # label expected-verdict config action probe
	local label="$1" want="$2" config="$3" action="$4" probe="$5" got
	got="$(eval_perm "$config" "$action" "$probe")"
	if [[ "$got" == "$want" ]]; then ok "$label"; else bad "$label (want $want, got $got: $action [$probe])"; fi
}

echo "== configs exist and parse =="
declare -A RULE_COUNT
for role in "${TASK_ACCESS_ROLES[@]}"; do
	config="$TIERB/$role.yaml"
	if [[ ! -f "$config" ]]; then
		bad "config exists for $role"
		continue
	fi
	RULE_COUNT[$role]="$(grep -cE '\{[[:space:]]*action:' "$config")"
	if ((RULE_COUNT[$role] >= 10)); then
		ok "config exists for $role (${RULE_COUNT[$role]} rules)"
	else
		bad "config exists for $role (only ${RULE_COUNT[$role]} rules)"
	fi
done

echo "== fixture denials bite per role (the denial demonstration) =="
for role in "${TASK_ACCESS_ROLES[@]}"; do
	config="$TIERB/$role.yaml"
	expect_verdict "$role: edit on .tasks/dashboard.md denied" "deny" "$config" edit ".tasks/dashboard.md"
	expect_verdict "$role: edit on .tasks/current/seed.md denied" "deny" "$config" edit ".tasks/current/seed.md"
	for probe in \
		"cat .tasks/dashboard.md" \
		"cat /abs/repo/.tasks/dashboard.md" \
		"grep PROVEMARK .tasks/current/seed.md" \
		"ls .tasks" \
		"ls -la .tasks/current" \
		"wc -l .tasks/dashboard.md" \
		"sed -n 1,5p .tasks/current/seed.md" \
		"awk 1 .tasks/dashboard.md" \
		"head .tasks/dashboard.md" \
		"tail -5 .tasks/dashboard.md" \
		"find .tasks -name dashboard.md" \
		"printf x | cat .tasks/dashboard.md" \
		"tasks show x && cat .tasks/dashboard.md"; do
		expect_verdict "$role: shell route denied [$probe]" "deny" "$config" shell "$probe"
	done
done

echo "== target map deltas realized per role =="
expect_verdict "planner: tasks show allowed (read-verb delta)" "allow" "$TIERB/planner.yaml" shell "tasks show /tmp/board/current/x.md --json"
expect_verdict "planner: tasks list allowed (read-verb delta)" "allow" "$TIERB/planner.yaml" shell "tasks list --json"
expect_verdict "planner: tasks reports allowed (read-verb delta)" "allow" "$TIERB/planner.yaml" shell "tasks reports /tmp/board/current/x.md --include-body --json"
expect_verdict "planner: tasks edit allowed (widened write channel)" "allow" "$TIERB/planner.yaml" shell "tasks edit /tmp/board/current/x.md --section Technical Approach --append"
expect_verdict "planner: territory cat stays allowed" "allow" "$TIERB/planner.yaml" shell "cat README.md"
expect_verdict "advisor: tasks show allowed byte-identically with planner" "allow" "$TIERB/advisor.yaml" shell "tasks show /tmp/board/current/x.md --json"
expect_verdict "advisor: territory cat stays allowed" "allow" "$TIERB/advisor.yaml" shell "cat README.md"
expect_verdict "reviewer: tasks reports allowed (read-verb delta)" "allow" "$TIERB/reviewer.yaml" shell "tasks reports /tmp/board/current/x.md --include-body --json"
expect_verdict "reviewer: tasks report write stays allowed" "allow" "$TIERB/reviewer.yaml" shell "tasks report /tmp/board/current/x.md --slug review --digest d"
expect_verdict "worker: territory edit stays allowed under the allow-first map" "allow" "$TIERB/worker.yaml" edit "src/main.ts"
expect_verdict "worker: tasks verbs flow through the blanket shell allow" "allow" "$TIERB/worker.yaml" shell "tasks log /tmp/board/current/x.md --from worker m"
expect_verdict "manager: retained .tasks edit allow overridden by the fixture deny" "deny" "$TIERB/manager.yaml" edit ".tasks/dashboard.md"
expect_verdict "manager: shell allow overridden by the fixture shell deny" "deny" "$TIERB/manager.yaml" shell "cat /abs/.tasks/dashboard.md"

echo "== allow-first denial tails: write tools and interpreters (DC3) =="
# The allow-first roles (worker, manager) carry blanket shell allows, so
# their catch-all closes nothing: the write tools and interpreters are
# denied explicitly in their fixture denial tails. Pinned here because the
# blanket allow makes these the exact routes a missing stem would leave
# open under both configs.
for role in worker manager; do
	config="$TIERB/$role.yaml"
	for probe in \
		"rm .tasks/dashboard.md" \
		"cp .tasks/current/seed.md /tmp/x.md" \
		"mv .tasks/dashboard.md /tmp/x.md" \
		"tee .tasks/dashboard.md <<< x" \
		"touch .tasks/dashboard.md" \
		"mkdir .tasks/current" \
		"python3 -c open('.tasks/dashboard.md').read()" \
		"python -c open('.tasks/dashboard.md').read()" \
		"perl -e print .tasks/dashboard.md" \
		"node -e require('.tasks/dashboard.md')" \
		"ruby -e File.read('.tasks/dashboard.md')" \
		"dd if=.tasks/dashboard.md of=/tmp/x"; do
		expect_verdict "$role: write-tool/interpreter route denied [$probe]" "deny" "$config" shell "$probe"
	done
	expect_verdict "$role: territory rm stays allowed under the allow-first map" "allow" "$config" shell "rm /tmp/scratch.md"
done
expect_verdict "verifier: tasks render stays allowed" "allow" "$TIERB/verifier.yaml" shell "tasks render"
expect_verdict "scout: no tasks allow rule exists (zero-diff role)" "default" "$TIERB/scout.yaml" shell "tasks show /tmp/board/current/x.md"

echo "== sanctioned exceptions are realizable under their fixture configs =="
# The drift check validates a sanctioned exception's text; this validates
# its mechanism. An exception that yields deny under its own fixture
# config is a contract lie: the verb map promises a route the map denies.
# One assertion per sanctioned exception; today that is exactly the
# planner research-deposit exception (verb-map.md, planner entry).
expect_verdict "planner: the sanctioned research-deposit exception yields allow" "allow" "$TIERB/planner.yaml" edit ".tasks/reports/research/01-recon.md"
expect_verdict "planner: the research allow stays narrow (sibling report paths deny)" "deny" "$TIERB/planner.yaml" edit ".tasks/reports/01-x.md"
expect_verdict "planner: the research allow stays narrow (non-report .tasks edits deny)" "deny" "$TIERB/planner.yaml" edit ".tasks/current/x.md"

echo "== configs allow exactly each role's authorized command set =="
cross_check_role() { # role
	local role="$1" config="$TIERB/$1.yaml"
	local -n cmds_ref="ROLE_COMMANDS_${role}"
	local template probe got
	for template in "${cmds_ref[@]}"; do
		CROSS_TOTAL=$((CROSS_TOTAL + 1))
		# piped templates carry a prelude; the shell verdict is evaluated
		# against the tasks invocation the role actually runs
		probe="$template"
		if [[ "$probe" == *"| tasks "* ]]; then probe="${probe#*| }"; fi
		got="$(eval_perm "$config" shell "$probe")"
		if [[ "$got" == "allow" ]]; then
			ok "$role: authorized command allowed by config [$probe]"
		else
			bad "$role: authorized command allowed by config [$probe] (got $got)"
		fi
	done
}
CROSS_TOTAL=0
for role in "${TASK_ACCESS_ROLES[@]}"; do
	cross_check_role "$role"
done
if ((CROSS_TOTAL >= 40)); then
	ok "cross-check covered the full executable verb map ($CROSS_TOTAL commands)"
else
	bad "cross-check covered the full executable verb map (only $CROSS_TOTAL commands)"
fi

echo "== verb-map rows and the executable sets stay in sync (bidirectional) =="
# The verb map claims its rows and role-verbs.sh describe the same command
# sets; that claim is pinned here, not taken on faith. Both sides extract
# the same way: the verb token of every literal `tasks <verb>` spelling.
# Direction one: a verb replayed for a role but uncited in its row means
# the row promises less than the replay proved. Direction two: a verb
# cited in the row but never replayed means the row promises a command
# no suite has proven sufficient (the drift that motivated this pin).
map_verbs() { # role -> newline-separated verbs cited in the row's section
	local role="$1"
	awk -v want="$role" '
		/^## / { inrole = 0 }
		/^### / { inrole = (tolower(substr($0, 5)) == want) }
		inrole { print }
	' "$VERB_MAP" | grep -oE 'tasks +[a-z]+' | awk '{print $NF}' | sort -u
}
set_verbs() { # role -> newline-separated verbs replayed from role-verbs.sh
	local role="$1" template
	local -n cmds_ref="ROLE_COMMANDS_${role}"
	for template in "${cmds_ref[@]}"; do
		grep -oE 'tasks +[a-z]+' <<<"$template" || true
	done | awk '{print $NF}' | sort -u
}
SYNC_ROLES=0
for role in "${TASK_ACCESS_ROLES[@]}"; do
	cited="$(map_verbs "$role")"
	replayed="$(set_verbs "$role")"
	only_replayed="$(comm -23 <(printf '%s\n' "$replayed") <(printf '%s\n' "$cited"))"
	only_cited="$(comm -13 <(printf '%s\n' "$replayed") <(printf '%s\n' "$cited"))"
	if [[ -z "$only_replayed" && -z "$only_cited" ]]; then
		ok "$role: row and executable set cite the same verbs ($(printf '%s\n' "$replayed" | grep -c .))"
	else
		bad "$role: verb drift (replayed but uncited: [${only_replayed//$'\n'/ }]; cited but not replayed: [${only_cited//$'\n'/ }])"
	fi
	SYNC_ROLES=$((SYNC_ROLES + 1))
done
if ((SYNC_ROLES == ${#TASK_ACCESS_ROLES[@]})); then
	ok "sync check covered every role ($SYNC_ROLES)"
else
	bad "sync check covered every role ($SYNC_ROLES of ${#TASK_ACCESS_ROLES[@]})"
fi

echo "== transcript audit: red on planted direct access =="
AUDIT_OUT="$(bash "$AUDIT" "$ROOT/no-such-transcript.log" 2>&1)"; AUDIT_RC=$?
if ((AUDIT_RC == 2)); then ok "audit rejects a missing transcript"; else bad "audit rejects a missing transcript (exit $AUDIT_RC)"; fi

{
	printf '{"tool":"bash","command":"tasks show /tmp/board/current/x.md --json"}\n'
	printf 'The board lives under .tasks/; reads go through tasks show.\n'
	printf '{"tool":"bash","command":"tasks list --json"}\n'
} > "$ROOT/clean-transcript.log"
AUDIT_OUT="$(bash "$AUDIT" "$ROOT/clean-transcript.log" 2>&1)"; AUDIT_RC=$?
if ((AUDIT_RC == 0)); then ok "audit passes a clean transcript (CLI verbs and prose only)"; else bad "audit passes a clean transcript (exit $AUDIT_RC)"; fi

{
	printf '{"tool":"bash","command":"cat .tasks/current/seed.md"}\n'
	printf '{"tool":"edit","file_path":"/repo/.tasks/dashboard.md","new_string":"x"}\n'
	printf '{"tool":"bash","command":"tasks show /tmp/x --json && cat /repo/.tasks/current/y.md"}\n'
	printf 'file_path = /abs/.tasks/reports/task/01-recon.md\n'
	printf '{"tool":"bash","command":"grep PROVEMARK .tasks/dashboard.md"}\n'
} > "$ROOT/dirty-transcript.log"
AUDIT_OUT="$(bash "$AUDIT" "$ROOT/dirty-transcript.log" 2>&1)"; AUDIT_RC=$?
if ((AUDIT_RC == 1)); then ok "audit fails a transcript with planted direct access"; else bad "audit fails a transcript with planted direct access (exit $AUDIT_RC)"; fi
assert_contains "audit flags the shell adjacency (V1)" "$AUDIT_OUT" "V1"
assert_contains "audit flags the edit file_path field (V2)" "$AUDIT_OUT" "V2"
assert_contains "audit flags the chained post-CLI direct cat" "$AUDIT_OUT" "tasks show /tmp/x --json && cat"
assert_contains "audit flags the key=value file_path form (V2)" "$AUDIT_OUT" "file_path = /abs/.tasks"
violation_lines="$(grep -c '^VIOLATION:' <<<"$AUDIT_OUT")"
assert_eq "audit reports one line per violation" "5" "$violation_lines"

echo "== transcript audit: reads through the sanctioned surface stay clean =="
{
	printf 'read the seeded parent via tasks show; the section body came back through --json\n'
	printf '{"tool":"bash","command":"tasks reports /tmp/board/current/x.md --include-body --json"}\n'
} > "$ROOT/sanctioned-transcript.log"
AUDIT_OUT="$(bash "$AUDIT" "$ROOT/sanctioned-transcript.log" 2>&1)"; AUDIT_RC=$?
if ((AUDIT_RC == 0)); then ok "audit passes reads routed through the CLI"; else bad "audit passes reads routed through the CLI (exit $AUDIT_RC)"; fi

echo "== transcript audit: interpreter and write-tool routes are V1 violations (DC3) =="
# The audit's V1 list grew the interpreter and write-tool stems in the same
# change that added the allow-first denial tails; this pins the routes the
# reviewer showed escaping V1 before, including under the allow-first
# configs whose catch-all deny never fires.
{
	cat <<'EOF'
{"tool":"bash","command":"python3 -c open('.tasks/dashboard.md').read()"}
{"tool":"bash","command":"dd if=.tasks/current/seed.md of=/tmp/x"}
{"tool":"bash","command":"rm .tasks/dashboard.md"}
EOF
} > "$ROOT/interpreter-transcript.log"
AUDIT_OUT="$(bash "$AUDIT" "$ROOT/interpreter-transcript.log" 2>&1)"; AUDIT_RC=$?
if ((AUDIT_RC == 1)); then ok "audit fails a transcript with interpreter and write-tool routes"; else bad "audit fails a transcript with interpreter and write-tool routes (exit $AUDIT_RC)"; fi
assert_contains "audit flags the interpreter route (V1)" "$AUDIT_OUT" "python3 -c open"
assert_contains "audit flags the dd raw-write route (V1)" "$AUDIT_OUT" "dd if="
assert_contains "audit flags the rm write-tool route (V1)" "$AUDIT_OUT" "rm .tasks"
violation_lines="$(grep -c '^VIOLATION:' <<<"$AUDIT_OUT")"
assert_eq "interpreter transcript reports one violation per line" "3" "$violation_lines"

echo "== transcript audit: an unterminated final line is still scanned =="
printf '{"tool":"bash","command":"tasks show /tmp/x --json"}\ncat .tasks/final-line.md' > "$ROOT/nonl-transcript.log"
AUDIT_OUT="$(bash "$AUDIT" "$ROOT/nonl-transcript.log" 2>&1)"; AUDIT_RC=$?
if ((AUDIT_RC == 1)); then ok "audit catches a violation on an unterminated final line"; else bad "audit catches a violation on an unterminated final line (exit $AUDIT_RC)"; fi

print_result
((fail == 0)) || exit 1
exit 0
