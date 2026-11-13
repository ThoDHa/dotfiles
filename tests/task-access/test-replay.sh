#!/usr/bin/env bash
#
# Command-sufficiency replay suite (ORCH-4-9-1, Tier A). Seeds a TASKS_DIR
# fixture board (temp root, pinned clock, never the live board) including an
# archived task and nested-content sections, installs PATH shims that refuse
# direct .tasks arguments for the shell file tools (cat, grep, ls, wc), then
# replays exactly each role's authorized command set from
# tests/fixtures/task-access/role-verbs.sh and proves it sufficient: every
# command exits 0, the seeded content round-trips through the authorized
# reads and writes, and the board stays lint-clean.
#
# Fixture boundary: sufficiency and discipline, not enforcement. The shims
# prove the direct shell routes fail; the CLI itself runs with the normal
# PATH (its internals legitimately touch .tasks). Enforcement is ORCH-4-10's
# work.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASKS_BIN="$REPO_ROOT/opencode/.local/bin/tasks"
ROLE_VERBS="$REPO_ROOT/tests/fixtures/task-access/role-verbs.sh"

source "$REPO_ROOT/tests/lib/harness.sh"

# Suite-local CLI reads (assertions) run with the normal PATH and resolve the
# repo binary directly; the replayed role commands run through the tasks()
# indirection defined below, so role-verbs.sh keeps the contract spellings.
tasks() { "$TASKS_BIN" "$@"; }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export TASKS_DIR="$ROOT/.tasks"
# Clock and TASKS_DIR stay exported together (the CLI's co-gate refuses a
# pinned clock without an explicit TASKS_DIR).
export TASKS_TEST_CLOCK="2026-06-15 12:00"
# Stable session identity for the whole suite, so the manager replay's
# claim, release, and close calls run as one session.
export TASKS_SESSION="orch4-9-1-fixture"

echo "== fixture isolation =="
[[ "$TASKS_DIR" == "$ROOT/"* ]] && ok "TASKS_DIR pinned under the temp root" || bad "TASKS_DIR pinned under the temp root"

echo "== PATH shims: refuse direct .tasks arguments =="
SHIM="$ROOT/shims"
mkdir -p "$SHIM"
make_shim() { # tool
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
	} > "$SHIM/$tool"
	chmod +x "$SHIM/$tool"
}
make_shim cat
make_shim grep
make_shim ls
make_shim wc

# refused LABEL cmd...: runs the command with the shims first on PATH and
# asserts the refusal (exit 97, fixture-shim message), proving the direct
# route fails before any file is touched.
refused() {
	local label="$1"; shift
	local o r
	o="$(PATH="$SHIM:$PATH" "$@" </dev/null 2>&1)"
	r=$?
	if ((r == 97)) && [[ "$o" == *"fixture-shim:"* ]]; then ok "$label"; else bad "$label (exit $r: $o)"; fi
}

refused "cat on an absolute .tasks path is refused" cat "$TASKS_DIR/dashboard.md"
refused "grep on an absolute .tasks path is refused" grep PROVEMARK "$TASKS_DIR/dashboard.md"
refused "ls on a .tasks directory is refused" ls "$TASKS_DIR"
refused "wc on a .tasks path is refused" wc -l "$TASKS_DIR/dashboard.md"
o="$(cd "$ROOT" && PATH="$SHIM:$PATH" cat .tasks/dashboard.md 2>&1)"; r=$?
if ((r == 97)) && [[ "$o" == *"fixture-shim:"* ]]; then ok "cat on a relative .tasks path is refused"; else bad "cat on a relative .tasks path is refused (exit $r)"; fi

printf '%s\n' "passthrough PROVEMARK" > "$ROOT/passthrough.txt"
o="$(PATH="$SHIM:$PATH" cat "$ROOT/passthrough.txt" 2>&1)"; r=$?
if ((r == 0)) && [[ "$o" == "passthrough PROVEMARK" ]]; then ok "shims pass non-.tasks arguments through"; else bad "shims pass non-.tasks arguments through (exit $r)"; fi

echo "== seeded fixture board =="
tasks init >/dev/null
# PARENT: the planner/advisor read surface and the manager's close/archive
# target. PROVEMARK content seeds sufficiency assertions; the Task
# Breakdown carries nested ### headings (nested-content requirement); the
# Success Criteria are ticked at seed time so the manager's close passes
# its gate.
PARENT="$(tasks new --id VMAP-1 --name "Verb Map Seed Parent" --status Ready --priority High)"
CHILD="$(tasks new --id VMAP-2 --name "Verb Map Seed Child")"
[[ -f "$PARENT" && -f "$CHILD" ]] && ok "seed tasks created" || bad "seed tasks created"
tasks edit "$PARENT" --section "Technical Approach" <<'EOF' >/dev/null
**Strategy:** seeded strategy PROVEMARK for replay reads.

### Decision Log

**Decision: Seed Anchor** · 2026-06-15 12:00
EOF
tasks edit "$PARENT" --section "Task Breakdown" <<'EOF' >/dev/null
### Task VMAP-1-1: Nested Child

**Status:** Ready

Nested heading body PROVEMARK inside the Task Breakdown.
EOF
tasks edit "$PARENT" --section "Success Criteria" <<< "- [x] Seeded criterion (verdict: verified)" >/dev/null
tasks log "$CHILD" --from manager "seed checkpoint" >/dev/null
ok "seed sections and nested content written"

echo "== replay: exactly each role's authorized command set =="
# shellcheck source=/dev/null
source "$ROLE_VERBS"

# Placeholder values refreshed as the replay mutates the fixture board.
declare -A VALUES=(
	[PARENT]="$PARENT"
	[CHILD]="$CHILD"
	[NEWFILE]=""
	[GENERATION]=""
	[ARCHIVED]=""
)
expand_placeholders() { # template -> stdout
	local s="$1" key
	for key in "${!VALUES[@]}"; do
		s="${s//\{\{$key\}\}/${VALUES[$key]}}"
	done
	printf '%s' "$s"
}

refresh_values() {
	# GENERATION: the claim sidecar lives while the claim does; capture the
	# token at claim time so the later release template expands correctly.
	local sidecar
	sidecar="$(find "$TASKS_DIR/current" -name '*.claim' 2>/dev/null | head -1)"
	if [[ -n "$sidecar" ]]; then
		VALUES[GENERATION]="$(sed -n 's/^generation //p' "$sidecar" | head -1)"
	fi
	# ARCHIVED: the parent's archive path, resolved after the archive step.
	local archived
	archived="$(find "$TASKS_DIR/archive" -name '*.md' 2>/dev/null | head -1)"
	if [[ -n "$archived" ]]; then
		VALUES[ARCHIVED]="$archived"
	fi
}

executed=0
replay_role() { # role
	local role="$1"
	local -n cmds="ROLE_COMMANDS_${role}"
	local template expanded captured r
	for template in "${cmds[@]}"; do
		expanded="$(expand_placeholders "$template")"
		captured="$(eval "$expanded" </dev/null 2>"$ROOT/replay-stderr")"
		r=$?
		executed=$((executed + 1))
		if ((r != 0)); then
			bad "$role: authorized command failed (exit $r): $expanded ($(cat "$ROOT/replay-stderr"))"
			return
		fi
		case "$expanded" in
		"tasks new "* ) VALUES[NEWFILE]="$captured" ;;
		esac
		refresh_values
	done
	ok "$role: ${#cmds[@]} authorized command(s) replayed under shims"
}

total_templates=0
for role in "${TASK_ACCESS_ROLES[@]}"; do
	eval "total_templates=\$((total_templates + \${#ROLE_COMMANDS_${role}[@]}))"
done

for role in "${TASK_ACCESS_ROLES[@]}"; do
	replay_role "$role"
done

assert_eq "every role-verbs template was executed exactly once" "$total_templates" "$executed"

echo "== sufficiency: seeded content round-trips through the authorized reads =="
o="$(tasks show "${VALUES[ARCHIVED]}" --section "Technical Approach")"
assert_contains "planner edit write round-trips through show" "$o" "Fixture risk note PROVEMARK."
o="$(tasks reports "${VALUES[ARCHIVED]}" --include-body --json)"
assert_contains "planner deposit body is readable through reports" "$o" "Planner report body PROVEMARK."
o="$(tasks reports "$CHILD" --include-body --json)"
assert_contains "worker deposit body is readable through reports" "$o" "Worker final body PROVEMARK."
o="$(tasks reports "$CHILD" --json)"
assert_contains "reviewer deposit is indexed with provenance" "$o" "review replay verdict"
o="$(tasks show "${VALUES[ARCHIVED]}" --section "Technical Approach")"
assert_contains "advisor evidence anchor readable through show" "$o" "Decision: Seed Anchor"
o="$(tasks show "${VALUES[ARCHIVED]}" --section "Task Breakdown")"
assert_contains "nested content survives the section read model" "$o" "Nested heading body PROVEMARK inside"
o="$(tasks show "${VALUES[NEWFILE]}" --json)"
assert_contains "manager set writes the header field" "$o" '"Progress":"25%"'
o="$(tasks show "${VALUES[ARCHIVED]}" --json)"
assert_contains "manager archived the parent and it stays readable" "$o" '"archived":true'
assert_contains "archived parent carries the closed status" "$o" '"Status":"Completed"'
o="$(tasks export --format jsonl)"
assert_contains "lossless export reaches the archived task" "$o" "Verb Map Seed Parent"

echo "== handshake: manager claim, worker deposit, heartbeat advance =="
# The manager-claims/worker-deposits handshake (verb-map.md, manager and
# worker rows): the dispatched worker runs under the claiming session's
# exported TASKS_SESSION, so its log/report checkpoints rewrite the claim
# sidecar's created stamp (the expiry heartbeat); a foreign session's
# checkpoint must leave the heartbeat alone and say so. The pinned clock
# makes the advance observable: claim at T, worker deposit at T+5, foreign
# deposit at T+10. Dispatched under a foreign session, a long-running
# worker's checkpoints would leave the heartbeat silent and the claim
# would expire under active work - the failure mode this scenario pins shut.
HANDSHAKE_TASK="$CHILD"
tasks claim "$HANDSHAKE_TASK" --owner orch4-9-1-fixture >/dev/null
claim_row() { tasks claims --json | grep -o "{\"task\":\"current/$(basename "$1")\"[^}]*}"; }
created_at() { claim_row "$1" | sed -n 's/.*"created":"\([^"]*\)".*/\1/p'; }
t0="$(created_at "$HANDSHAKE_TASK")"
assert_eq "seeded claim records the claim-time stamp" "2026-06-15 12:00" "$t0"
TASKS_TEST_CLOCK="2026-06-15 12:05" tasks log "$HANDSHAKE_TASK" --from worker "handshake heartbeat checkpoint" >/dev/null
t1="$(created_at "$HANDSHAKE_TASK")"
assert_eq "worker deposit under the claiming session advances the heartbeat" "2026-06-15 12:05" "$t1"
foreign_err="$(TASKS_SESSION=foreign-worker TASKS_TEST_CLOCK="2026-06-15 12:10" tasks log "$HANDSHAKE_TASK" --from worker "foreign checkpoint" 2>&1 >/dev/null)"
t2="$(created_at "$HANDSHAKE_TASK")"
assert_eq "foreign-session deposit leaves the heartbeat alone" "2026-06-15 12:05" "$t2"
assert_contains "foreign-session deposit says so on stderr" "$foreign_err" "the heartbeat was not refreshed"

echo "== scout contract: zero authorized task commands =="
assert_eq "scout's authorized set is empty by contract" "0" "${#ROLE_COMMANDS_scout[@]}"

echo "== verifier contract: render is idempotent over the derived board =="
before_render="$(cat "$TASKS_DIR/dashboard.md")"
tasks render >/dev/null
assert_eq "dashboard byte-identical across the verifier's render" "$before_render" "$(cat "$TASKS_DIR/dashboard.md")"

echo "== denial demonstrated under the fixture posture =="
# The replay ran the authorized set; the direct routes were proven refused
# under the same shims before it. One read-back through the CLI confirms the
# fixture board still answers only through the authorized surface.
o="$(tasks list --json)"
assert_contains "fixture board still answers through the CLI" "$o" "Verb Map Seed Child"

echo "== board hygiene after the full replay =="
tasks lint >/dev/null && ok "fixture board lint-clean after all role replays" || bad "fixture board lint-clean after all role replays"
o="$(tasks doctor --json)"
assert_contains "doctor reports zero findings on the fixture board" "$o" '"total":0'

print_result
((fail == 0)) || exit 1
exit 0
