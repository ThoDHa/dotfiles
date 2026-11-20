#!/usr/bin/env bash
#
# Adversarial bypass suite and integration gate (ORCH-4-10-4).
#
# Drives the eight bypass classes from the parent's Testing Strategy plus
# the compound-composition class added by the design-bearing reviews,
# through the REAL dispatch path of each harness, with a characterization
# twin per class that succeeds WITHOUT enforcement (proving the denial
# comes from the enforcement, never from the fixture):
#
#   pi column       - the production wrap argv (the bwrap invocation the
#                     activated vendored-extension seam spawns, built by
#                     the suite's parity-pinned mirror in lib/
#                     isolation_common.py; run-suite.sh pins mirror ==
#                     installed block, so deny evidence here cannot drift
#                     from the production mechanism), against the real
#                     escape-channel service so sanctioned shapes stay
#                     reachable inside the same namespaces
#   opencode column - the landed BrokerService through the real bridge
#                     client (lib/oc-broker-client.py), the same path the
#                     guard plugin's rewritten shell calls take
#
# Classes: symlink, relative-path, worktree, alternate-command,
# child-process, inherited-fd, git-history smuggling (write and read),
# write side (redirect/tee/sed -i/mv/rm against storage paths including
# the claim sidecar and lock), compound-composition shapes. The
# transcript-copy-store class (10-2's deferred DC2), the routed findings
# (registered-pair replay, output cap, argv element cap, socket-dir
# verification), recovery/concurrency, and the end-to-end integration
# pass land in their own sections alongside the fixes they mandate.
#
# Degradation contract: with ISOLATION_ALLOW_DEGRADED=1 (set by the
# container verify chain, which has no bwrap and no model gateway) the
# machine-probe columns and LLM-dependent sections are announced as
# skipped and the suite gates on what ran; without the flag a missing
# tool fails the suite loudly. Enforced labels are decided by full-mode
# host runs only.
#
# Exit contract: non-zero unless every check passed; on failure the run
# directory is kept and its path printed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_DIR="$REPO_ROOT/tests/task-storage-isolation"
LIB="$SUITE_DIR/lib"
SERVICE_PY="$REPO_ROOT/pi/extensions/task-storage-isolation-service.py"
CLIENT_PY="$REPO_ROOT/pi/extensions/task-storage-isolation-client.py"
RUN="$(mktemp -d /tmp/adversarial-suite.XXXXXX)"
DC2_XDG=""
SERVICE_PID=""
status=0

trap '{
	status=$?
	if [[ -n "$SERVICE_PID" ]]; then
		kill "$SERVICE_PID" 2>/dev/null || true
	fi
	if [[ "$status" -eq 0 ]]; then
		rm -rf "$RUN"
		if [[ -n "$DC2_XDG" ]]; then
			rm -rf "$DC2_XDG"
		fi
	else
		echo "adversarial suite artifacts kept for inspection: $RUN"
		if [[ -n "$DC2_XDG" ]]; then
			echo "dc2 store seed kept for inspection: $DC2_XDG"
		fi
	fi
}' EXIT

fail_fast() {
	echo "ADVERSARIAL-FAIL: $*" >&2
	exit 1
}

# shellcheck source=/dev/null
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck disable=SC2034
pass=0
# shellcheck disable=SC2034
fail=0
# shellcheck disable=SC2034
skip=0

absorb_results() { # <label> <output> <rc>
	local label="$1" output="$2" rc="$3"
	local line
	while IFS= read -r line; do
		case "$line" in
			"ok "*) ok "${line#"ok "}";;
			"bad "*) bad "${line#"bad "}";;
			"skip "*) skip_test "${line#"skip "}";;
			*) printf '    runner: %s\n' "$line" ;;
		esac
	done <<<"$output"
	if [[ "$rc" -ne 0 ]]; then
		bad "$label (runner exited $rc)"
	fi
}

DEGRADED="${ISOLATION_ALLOW_DEGRADED:-0}"

# Imports of repo-source modules (the lib service under test) must not
# drop __pycache__ into the repo tree; the pi-extensions
# deploy-completeness gate fails on untracked litter there.
export PYTHONDONTWRITEBYTECODE=1

command -v python3 >/dev/null || fail_fast "python3 not installed"
command -v tasks >/dev/null || fail_fast "tasks CLI not on PATH"
if command -v shellcheck >/dev/null; then
	if shellcheck "$SUITE_DIR/run-adversarial.sh"; then
		ok "shellcheck clean on run-adversarial.sh"
	else
		bad "shellcheck clean on run-adversarial.sh"
	fi
else
	if [[ "$DEGRADED" == "1" ]]; then
		skip_test "shellcheck clean on run-adversarial.sh (shellcheck not installed; degraded mode)"
	else
		fail_fast "shellcheck not installed"
	fi
fi
HAVE_BWRAP=0
if command -v bwrap >/dev/null; then
	HAVE_BWRAP=1
	ok "bwrap available for the machine columns"
else
	if [[ "$DEGRADED" == "1" ]]; then
		skip_test "bwrap available for the machine columns (bwrap not installed; degraded mode)"
	else
		fail_fast "bwrap not installed (machine probes cannot run)"
	fi
fi

echo "== 1. hermetic fixtures =="
FIX="$RUN/fixtures"
AGENT_DIR="$FIX/agent"
REPO_FIX="$FIX/repo"
WORKTREE_FIX="$FIX/worktree"
TWIN="$RUN/twin-repo"
TWIN_SECRET="ADV-TWIN-SECRET-6c41"
ESCAPE_DIR="$RUN/escape"
SOCKET="$ESCAPE_DIR/service.sock"
TRUST_FILE="$ESCAPE_DIR/trust.json"
python3 - "$FIX" "$LIB" <<'EOF' || fail_fast "fixture build failed"
import os
import sys

fix, lib = sys.argv[1], sys.argv[2]
sys.path.insert(0, lib)
import isolation_common as ic

os.makedirs(fix, exist_ok=True)
ic.make_fixture_agent_dir(fix)
repo_fix, _ = ic.make_fixture_repo(fix)
ic.add_fixture_worktree(repo_fix, os.path.join(fix, "worktree"))
EOF
if [[ ! -d "$REPO_FIX/.tasks" || ! -d "$WORKTREE_FIX/.tasks" ]]; then
	fail_fast "fixtures incomplete"
fi

export TASKS_SESSION=adversarial-suite
(cd "$REPO_FIX" && tasks init >/dev/null) || fail_fast "tasks init failed on fixture"
(cd "$REPO_FIX" && tasks new --id ADV-1 --name "Adversarial Target" >/dev/null) || fail_fast "tasks new failed on fixture"
TASKFILE_BASE="$(cd "$REPO_FIX" && find .tasks/current -maxdepth 1 -name 'ADV-1-*.md' -printf '%f\n' | head -1)"
[[ -n "$TASKFILE_BASE" ]] || fail_fast "fixture task file was not created"
mkdir -p "$REPO_FIX/.tasks/reports"
printf 'secret: SUITE-SECRET-2d97-masked\n' >"$REPO_FIX/.tasks/reports/secret.md"
ok "fixture board ready (task file $TASKFILE_BASE)"

SECRET_MARKER="SUITE-SECRET-2d97-masked"
SIBLING_MARKER="SIBLING-SECRET-71ce-masked"

# Twin fixture: a second repo with the identical board shape so
# characterization twins that MUTATE storage never corrupt the
# enforcement fixture's board state.
mkdir -p "$TWIN/.tasks/current" "$TWIN/.tasks/reports"
git -C "$TWIN" init -q
git -C "$TWIN" config user.email adv@fixture
git -C "$TWIN" config user.name adv
echo ".tasks/" >"$TWIN/.gitignore"
printf 'fixture readme\n' >"$TWIN/README.md"
printf 'secret: %s\n' "$TWIN_SECRET" >"$TWIN/.tasks/current/secret.md"
printf 'secret: %s\n' "$TWIN_SECRET" >"$TWIN/.tasks/reports/secret.md"
git -C "$TWIN" add -A
git -C "$TWIN" commit -qm "twin fixture"
(cd "$TWIN" && tasks init >/dev/null) || fail_fast "tasks init failed on twin"
(cd "$TWIN" && tasks new --id ADV-1 --name "Adversarial Twin" >/dev/null) || fail_fast "tasks new failed on twin"
TWIN_TASKFILE="$(cd "$TWIN" && find .tasks/current -maxdepth 1 -name 'ADV-1-*.md' -printf '%f\n' | head -1)"
[[ -n "$TWIN_TASKFILE" ]] || fail_fast "twin task file was not created"
ok "twin fixture ready (task file $TWIN_TASKFILE)"

board_hash() { # fixture dir -> stable hash of the seeded board content
	( cd "$1" && find .tasks -type f -not -name "*.claim" -print0 | sort -z \
		| xargs -0 sha256sum | sha256sum | cut -d' ' -f1 )
}
BASE_HASH="$(board_hash "$REPO_FIX")"

echo "== 2. pi escape-channel service (real wiring for the wrap namespaces) =="
if [[ "$HAVE_BWRAP" == "1" ]]; then
	mkdir -p "$ESCAPE_DIR"
	chmod 700 "$ESCAPE_DIR"
	printf '{}\n' >"$TRUST_FILE"
	PI_TASK_STORAGE_TOKEN="adv-suite-token" python3 "$SERVICE_PY" "$SOCKET" "$REPO_FIX" "$RUN/service.log" &
	SERVICE_PID=$!
	for _ in $(seq 1 50); do
		[[ -S "$SOCKET" ]] && break
		sleep 0.1
	done
	if [[ -S "$SOCKET" ]]; then
		ok "pi escape-channel service listening on the 0700 escape dir"
	else
		fail_fast "pi service socket never appeared"
	fi
else
	skip_test "pi escape-channel service (bwrap not installed; degraded mode)"
fi

echo "== 3. pi machine column (production wrap argv, parity-pinned mirror) =="
run_pi_probe() { # <payload-shell-text> [repo-root-for-mask] -> JSON result on stdout
	local payload="$1" mask_repo="${2:-$REPO_FIX}"
	ISOLATION_LIB="$LIB" ISOLATION_FIX="$REPO_FIX" ISOLATION_MASK_REPO="$mask_repo" \
		ISOLATION_AGENT_DIR="$AGENT_DIR" ISOLATION_WORKTREE="$WORKTREE_FIX" \
		ISOLATION_SOCKET="$SOCKET" ISOLATION_TRUST="$TRUST_FILE" \
		PI_TASK_STORAGE_ISOLATION=1 PI_TASK_STORAGE_TOKEN="adv-suite-token" \
		TASKS_SESSION="adversarial-child" \
		python3 - "$payload" <<'PYEOF'
import json
import os
import subprocess
import sys

payload = sys.argv[1]
fix = os.environ["ISOLATION_FIX"]
lib = os.environ["ISOLATION_LIB"]
sys.path.insert(0, lib)
import isolation_common as ic

env = dict(os.environ)
env["PI_TASK_STORAGE_MASK_PATHS"] = "\n".join([
	os.path.realpath(os.path.join(os.environ["ISOLATION_MASK_REPO"], ".tasks")),
	os.path.realpath(os.path.join(os.environ["ISOLATION_WORKTREE"], ".tasks")),
])
env["PI_TASK_STORAGE_SOCKET"] = os.environ["ISOLATION_SOCKET"]
env["PI_TASK_STORAGE_TRUST_FILE"] = os.environ["ISOLATION_TRUST"]
argv = ic.build_isolation_argv("/bin/bash", ["-c", payload], env,
                               agent_dir=os.environ["ISOLATION_AGENT_DIR"])
# The composed wiring env rides the child too: the wrap's parent hands
# the mask, socket, and trust wiring to the spawned child, and the
# escape-channel client inside reads it from there.
completed = subprocess.run(argv, capture_output=True, text=True, timeout=120,
                           cwd=fix, env=env)
print(json.dumps({"rc": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}))
PYEOF
}

run_pi_twin() { # <payload-shell-text> -> JSON result (no enforcement: plain sh -c)
	ISOLATION_TWIN="$TWIN" TASKS_SESSION="adversarial-twin" \
		python3 - "$1" <<'PYEOF'
import json
import os
import subprocess
import sys

payload = sys.argv[1]
completed = subprocess.run(["/bin/sh", "-c", payload], capture_output=True,
                           text=True, timeout=120, cwd=os.environ["ISOLATION_TWIN"])
print(json.dumps({"rc": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}))
PYEOF
}

verify_json() { # <name> <probe-json> <python-assert-script> [args...]
	# A probe-runner crash surfaces here too: its stdout stops being valid
	# JSON, the assert script dies on the parse, and the check flips bad.
	local name="$1" probe_json="$2"
	shift 2
	local verdict rc=0
	verdict="$(python3 - "$probe_json" "$@" 2>&1)" || rc=$?
	if [[ "$rc" -eq 0 ]]; then
		ok "$name"
	else
		bad "$name: ${verdict:0:300}"
	fi
}

if [[ "$HAVE_BWRAP" == "1" ]]; then
	# -- Classes 1-3: symlink, relative path, worktree.
	pi_payload="cat ./.tasks/current/secret.md
cat .tasks/../.tasks/current/secret.md
cat sub/deeper/../../.tasks/current/secret.md
cat sub/deeper/link-updown
(cd /tmp && cat '$REPO_FIX/.tasks/current/secret.md')
cat link-rel; cat link-abs
cat '$WORKTREE_FIX/.tasks/current/sibling.md'
python3 '$CLIENT_PY' tasks show '$TASKFILE_BASE' --json >/dev/null && echo CHANNEL-OK
true"
	probe_json="$(run_pi_probe "$pi_payload")"
	verify_json "pi deny: symlink, relative-path, and worktree classes all denied while the sanctioned channel stays reachable" \
		"$probe_json" "$SECRET_MARKER" "$SIBLING_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
secret, sibling = sys.argv[2], sys.argv[3]
combined = result["stdout"] + result["stderr"]
assert secret not in combined, "SECRET MARKER LEAKED through the path classes"
assert sibling not in combined, "SIBLING MARKER LEAKED through the worktree class"
assert combined.count("No such file or directory") >= 7, \
	f"expected seven path denials, got: {combined}"
assert "CHANNEL-OK" in result["stdout"], \
	f"sanctioned channel unreachable inside the same namespace: {result['stdout'][-300:]}"
PYEOF

	twin_json="$(run_pi_twin "cat ./.tasks/current/secret.md; cat '$REPO_FIX/link-rel' 2>/dev/null; cat '$WORKTREE_FIX/.tasks/current/sibling.md'; true")"
	verify_json "pi twin: the same read shapes succeed without enforcement (characterization)" \
		"$twin_json" "$TWIN_SECRET" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
combined = result["stdout"] + result["stderr"]
assert result["rc"] == 0, f"twin failed: {combined[:300]}"
assert sys.argv[2] in combined, f"twin could not read its own board (fixture broken): {combined[:300]}"
PYEOF

	# -- Class 4: alternate commands against storage paths.
	pi_payload="rg -a SUITE '$REPO_FIX/.tasks'
sed -n 1p '$REPO_FIX/.tasks/current/secret.md'
awk '1' '$REPO_FIX/.tasks/current/secret.md'
head -1 '$REPO_FIX/.tasks/current/secret.md'
tail -1 '$REPO_FIX/.tasks/current/secret.md'
dd if='$REPO_FIX/.tasks/current/secret.md' bs=1 count=8 2>/dev/null
tar -C '$REPO_FIX' -cf - .tasks 2>/dev/null | head -c 64
cp '$REPO_FIX/.tasks/current/secret.md' /tmp/adv-copied 2>/dev/null && head -1 /tmp/adv-copied
find '$REPO_FIX/.tasks' -name '*.md' -exec head -1 {} \;
stat '$REPO_FIX/.tasks/current/secret.md'
git -C '$REPO_FIX' diff --no-index /dev/null '$REPO_FIX/.tasks/current/secret.md'
git -C '$REPO_FIX' hash-object '$REPO_FIX/.tasks/current/secret.md'
python3 -c \"open('$REPO_FIX/.tasks/current/secret.md').read()\"
node -e \"require('fs').readFileSync('$REPO_FIX/.tasks/current/secret.md','utf8')\"
perl -e \"open my \$h,'<','$REPO_FIX/.tasks/current/secret.md'; print <\$h>\"
iconv -f utf8 -t utf8 '$REPO_FIX/.tasks/current/secret.md'
sort '$REPO_FIX/.tasks/current/secret.md'
uniq '$REPO_FIX/.tasks/current/secret.md'
md5sum '$REPO_FIX/.tasks/current/secret.md'
true"
	probe_json="$(run_pi_probe "$pi_payload")"
	verify_json "pi deny: alternate-command class (rg/sed/awk/head/tail/dd/tar/cp/find/stat/git/python/node/perl/iconv/sort/uniq/md5sum) leaks no board bytes" \
		"$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
secret = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert secret not in combined, "SECRET MARKER LEAKED through the alternate-command class"
PYEOF

	twin_json="$(run_pi_twin "head -1 .tasks/current/secret.md; md5sum .tasks/current/secret.md; git diff --no-index /dev/null .tasks/reports/secret.md; true")"
	verify_json "pi twin: alternate commands read the twin board without enforcement (characterization)" \
		"$twin_json" "$TWIN_SECRET" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
assert sys.argv[2] in result["stdout"], \
	f"twin alternate commands did not recover the marker: {result['stdout'][:300]} {result['stderr'][:200]}"
PYEOF

	# -- Class 5: child-process wrappers.
	pi_payload="bash -c \"cat '$REPO_FIX/.tasks/current/secret.md'\"
sh -c \"cat '$REPO_FIX/.tasks/current/secret.md'\"
echo \"\$(cat '$REPO_FIX/.tasks/current/secret.md')\"
env cat '$REPO_FIX/.tasks/current/secret.md'
timeout 5 cat '$REPO_FIX/.tasks/current/secret.md'
nohup cat '$REPO_FIX/.tasks/current/secret.md' 2>/dev/null
python3 -c \"print(open('$REPO_FIX/.tasks/current/secret.md').read())\"
perl -0777 -ne 'print' '$REPO_FIX/.tasks/current/secret.md'
node -e \"console.log(require('fs').readFileSync('$REPO_FIX/.tasks/current/secret.md','utf8'))\"
true"
	probe_json="$(run_pi_probe "$pi_payload")"
	verify_json "pi deny: child-process class (bash -c/sh -c/substitution/env/timeout/nohup/interpreters) leaks no board bytes" \
		"$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
secret = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert secret not in combined, "SECRET MARKER LEAKED through the child-process class"
PYEOF

	# -- Class 6: inherited descriptors.
	pi_payload="exec 3< '$REPO_FIX/.tasks/current/secret.md' 2>/dev/null || echo OPEN-REFUSED
cat <&3 2>/dev/null || echo FD-READ-REFUSED
cat 0< '$REPO_FIX/.tasks/current/secret.md' 2>/dev/null || echo STDIN-REDIR-REFUSED
echo FD-LIST-BEGIN
ls -l /proc/self/fd 2>/dev/null
echo FD-LIST-END
true"
	probe_json="$(run_pi_probe "$pi_payload")"
	verify_json "pi deny: inherited-fd class (exec 3<, cat <&3, cat 0<) cannot open storage and leaks no descriptors" \
		"$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
secret = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert secret not in combined, "SECRET MARKER LEAKED through the inherited-fd class"
assert "OPEN-REFUSED" in combined, f"fd open unexpectedly succeeded: {combined[:300]}"
listing = combined.split("FD-LIST-BEGIN")[-1].split("FD-LIST-END")[0]
assert ".tasks" not in listing, \
	f"storage descriptors present in /proc/self/fd: {listing[-400:]}"
PYEOF

	twin_json="$(run_pi_twin "exec 3< .tasks/current/secret.md && cat <&3")"
	verify_json "pi twin: inherited-fd read recovers the marker without enforcement (characterization)" \
		"$twin_json" "$TWIN_SECRET" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
assert sys.argv[2] in result["stdout"], \
	f"twin fd read did not recover the marker: {result['stdout'][:300]} {result['stderr'][:200]}"
PYEOF

	# -- Class 7: git-history smuggling (write and read), against the
	# twin's identical mask shape (the -f add mutates git state, so the
	# enforcement fixture board must stay untouched).
	pi_smuggle_out="$(run_pi_probe "git add -f .tasks/reports/secret.md 2>&1
git -c user.email=adv@fixture -c user.name=adv commit -qm smuggle 2>&1
git show HEAD:.tasks/reports/secret.md 2>&1
git hash-object .tasks/reports/secret.md 2>&1
true" "$TWIN")"
	verify_json "pi deny: git-history smuggling (add -f, commit, show, hash-object) closed under the mask" \
		"$pi_smuggle_out" "$SECRET_MARKER" "$TWIN_SECRET" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
secret = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert secret not in combined, "SECRET MARKER LEAKED through the git-smuggling class"
assert "No such file" in combined or "did not match" in combined or "bad revision" in combined, \
	f"smuggling shapes did not surface file-level denials: {combined[:400]}"
PYEOF

	twin_json="$(run_pi_twin "git add -f .tasks/reports/secret.md && git -c user.email=adv@fixture -c user.name=adv commit -qm twin-smuggle && git show HEAD:.tasks/reports/secret.md")"
	verify_json "pi twin: git-history smuggling recovers the marker without enforcement (characterization)" \
		"$twin_json" "$TWIN_SECRET" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
assert sys.argv[2] in result["stdout"], \
	f"twin smuggling did not recover the marker: {result['stdout'][:300]} {result['stderr'][:200]}"
PYEOF

	# -- Class 8: write side (redirect, tee, sed -i, mv, rm against
	# storage paths including the claim sidecar and lock), against the
	# twin; in-namespace writes land in the empty tmpfs mask only, and
	# the twin board hash must not move.
	twin_hash_before="$(board_hash "$TWIN")"
	pi_write_out="$(run_pi_probe "echo ADV-WRITEPIN > .tasks/current/secret.md && cat .tasks/current/secret.md
echo tee-pin | tee .tasks/reports/secret.md
sed -i 's/secret/REPLACED/' .tasks/reports/secret.md
mv .tasks/reports/secret.md .tasks/reports/moved.md
rm -f .tasks/reports/moved.md
rm -rf .tasks
touch .tasks/.lock
ls .tasks
true" "$TWIN")"
	twin_hash_after="$(board_hash "$TWIN")"
	verify_json "pi deny: write side (redirect/tee/sed -i/mv/rm/lock) lands only in the empty tmpfs mask" \
		"$pi_write_out" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
secret = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert secret not in combined, "SECRET MARKER LEAKED through the write-side class"
PYEOF
	verify_json "pi deny: write-side class leaves the twin board byte-identical" \
		"{}" <<PYEOF
import sys
assert "${twin_hash_before}" == "${twin_hash_after}", "twin board mutated under the mask"
PYEOF

	twin_json="$(run_pi_twin "echo ADV-WRITEPIN > .tasks/current/secret.md; cat .tasks/current/secret.md")"
	verify_json "pi twin: the write class mutates the twin board without enforcement (characterization)" \
		"$twin_json" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
assert "ADV-WRITEPIN" in result["stdout"], \
	f"twin write did not mutate the twin board: {result['stdout'][:200]} {result['stderr'][:200]}"
PYEOF

	# -- Class 9 (review-added): compound-composition shapes.
	# SC2016/SC2140: the payload intentionally carries payload-level
	# quoting (single-quoted paths, split-quoted words) for the masked
	# bash to parse; suppressing the outer script's expansion lint is the
	# targeted form of expressing that intent.
	# shellcheck disable=SC2016,SC2140
	pi_payload="cat '$REPO_FIX/.tasks/current/secret.md' && echo AND-RAN
cat '$REPO_FIX/.tasks/current/secret.md' || echo OR-RAN
cat '$REPO_FIX/.tasks/current/secret.md' ; echo SEQ-RAN
cat '$REPO_FIX/.tasks/current/secret.md' | grep -a SUITE
echo \"subst=\$(cat '$REPO_FIX/.tasks/current/secret.md')\"
echo \"backtick=\`cat '$REPO_FIX/.tasks/current/secret.md'\`\"
grep -a SUITE <(cat '$REPO_FIX/.tasks/current/secret.md')
echo brace-{a,b}; head -c 3 '$REPO_FIX/.tasks/current/secret.md'
cat <<EOF
heredoc-$(cat '$REPO_FIX/.tasks/current/secret.md')
EOF
cat '$REPO_FIX/.tasks'"/current/secret.md"
true"
	probe_json="$(run_pi_probe "$pi_payload")"
	verify_json "pi deny: compound-composition class (&&/||/;/pipe/substitution/backtick/process-sub/brace/heredoc/continuation) leaks no board bytes" \
		"$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
secret = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert secret not in combined, "SECRET MARKER LEAKED through the compound-composition class"
PYEOF

	twin_json="$(run_pi_twin "echo TWIN-COMPOSE-9a11 > .tasks/current/secret.md; grep -a TWIN-COMPOSE .tasks/current/secret.md; echo \"s=\$(cat .tasks/current/secret.md)\"; true")"
	verify_json "pi twin: compound compositions read the twin board without enforcement (characterization)" \
		"$twin_json" "TWIN-COMPOSE-9a11" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
assert sys.argv[2] in result["stdout"], \
	f"twin compositions did not recover the marker: {result['stdout'][:300]}"
PYEOF

	# -- DC2 (10-2's deferred class): the other harness's transcript-copy
	# store. The seed lives under /var/tmp because the wrap replaces /tmp
	# with an empty tmpfs, which would hide the seed for the wrong reason.
	DC2_XDG="$(mktemp -d /var/tmp/adversarial-dc2.XXXXXX)"
	chmod 700 "$DC2_XDG"
	mkdir -p "$DC2_XDG/opencode/storage/session/default"
	printf '{"content":"DC2-PI-SEED-MARKER-9d41"}\n' > "$DC2_XDG/opencode/storage/session/default/transcript.jsonl"
	dc2_probe_out="$(XDG_DATA_HOME="$DC2_XDG" run_pi_probe "cat '$DC2_XDG/opencode/storage/session/default/transcript.jsonl'
true")"
	verify_json "pi deny: DC2 transcript-copy store masked from the namespace" \
		"$dc2_probe_out" "DC2-PI-SEED-MARKER-9d41" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
marker = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert marker not in combined, "DC2 TRANSCRIPT MARKER LEAKED under the wrap"
assert result["rc"] != 0 or "No such file" in combined or "not a directory" in combined, \
	f"store read unexpectedly succeeded: {combined[:300]}"
PYEOF
	twin_json="$(run_pi_twin "cat '$DC2_XDG/opencode/storage/session/default/transcript.jsonl'")"
	verify_json "pi twin: DC2 store seed reads back without enforcement (characterization)" \
		"$twin_json" "DC2-PI-SEED-MARKER-9d41" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
assert sys.argv[2] in result["stdout"], \
	f"twin could not read the DC2 seed: {result['stdout'][:300]} {result['stderr'][:200]}"
PYEOF
else
	for section in "symlink/relative/worktree" "alternate-command" "child-process" \
		"inherited-fd" "git-history smuggling" "write side" "compound-composition" \
		"DC2 transcript-copy store"; do
		skip_test "pi deny + twin: $section class (bwrap not installed; degraded mode)"
	done
fi

if [[ "$(board_hash "$REPO_FIX")" == "$BASE_HASH" ]]; then
	ok "pi column leaves the enforcement fixture board byte-identical"
else
	bad "pi column leaves the enforcement fixture board byte-identical"
fi

echo "== 4. opencode machine column (BrokerService through the real client) =="
oc_rc=0
OC_XDG="$RUN/oc-xdg-data"
mkdir -p "$OC_XDG/opencode/storage/session/default"
printf '{"content":"DC2-OC-SEED-MARKER-4d18"}\n' > "$OC_XDG/opencode/storage/session/default/transcript.jsonl"
OC_OUT="$(REPO_ROOT="$REPO_ROOT" \
	ISOLATION_LIB="$LIB" ISOLATION_FIX="$REPO_FIX" ISOLATION_WORKTREE="$WORKTREE_FIX" \
	ISOLATION_TASKFILE="$TASKFILE_BASE" ISOLATION_TWIN="$TWIN" ISOLATION_TWIN_TASKFILE="$TWIN_TASKFILE" \
	ISOLATION_SECRET="$SECRET_MARKER" ISOLATION_SIBLING="$SIBLING_MARKER" \
	ISOLATION_TWIN_SECRET="$TWIN_SECRET" \
	ISOLATION_OC_XDG="$OC_XDG" \
	XDG_DATA_HOME="$OC_XDG" \
	ISOLATION_HAVE_BWRAP="$HAVE_BWRAP" ISOLATION_DEGRADED="$DEGRADED" \
	python3 - <<'PYEOF'
import atexit
import hashlib
import importlib.util
import json
import os
import socket
import subprocess
import sys
import threading
import time

LIB = os.environ["ISOLATION_LIB"]
FIX = os.environ["ISOLATION_FIX"]
WORKTREE = os.environ["ISOLATION_WORKTREE"]
ENTRY = os.environ["ISOLATION_TASKFILE"]
TWIN = os.environ["ISOLATION_TWIN"]
TWIN_TASKFILE = os.environ["ISOLATION_TWIN_TASKFILE"]
SECRET = os.environ["ISOLATION_SECRET"]
SIBLING = os.environ["ISOLATION_SIBLING"]
TWIN_SECRET = os.environ["ISOLATION_TWIN_SECRET"]
HAVE_BWRAP = os.environ["ISOLATION_HAVE_BWRAP"] == "1"
RUN = os.path.join(os.path.dirname(FIX), "oc-state")
os.makedirs(RUN, exist_ok=True)
os.chmod(RUN, 0o700)

TASKS_BIN_DIR = os.path.join(os.environ["REPO_ROOT"], "shell/.local/bin")
os.environ["PATH"] = TASKS_BIN_DIR + os.pathsep + os.environ.get("PATH", "")

spec = importlib.util.spec_from_file_location(
	"oc_task_service_adversarial", os.path.join(LIB, "oc-task-service.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

token = "tok-adversarial"
fd = os.open(os.path.join(RUN, "token"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as f:
	f.write(token)
svc = mod.BrokerService(os.path.join(RUN, "broker.sock"), FIX, token,
                        os.path.join(RUN, "service.log"))
svc.state["registry"].add(("adv-sess", "worker"))
svc.state["registry"].add(("adv-plan", "planner"))
svc.state["registry"].add(("adv-verif", "verifier"))
threading.Thread(target=svc.serve_forever, kwargs={"poll_interval": 0.2}, daemon=True).start()
time.sleep(0.2)

env_full = dict(os.environ)


def run_client(session, agent, command, stdin_body=None, cwd=None):
	return subprocess.run(
		[sys.executable, os.path.join(LIB, "oc-broker-client.py"), "--registry", RUN,
		 "--session", session, "--agent", agent, "exec", command],
		capture_output=True, text=True, cwd=cwd or FIX, input=stdin_body, env=env_full,
		timeout=180)


def run_plain(command, cwd=None):
	return subprocess.run(["/bin/bash", "-c", command], capture_output=True,
	                      text=True, cwd=cwd or FIX, env=env_full, timeout=120)


def expect(label, cond, detail=""):
	# Result-line prefixes match the suite's absorb_results grammar
	# ("ok "/"bad "/"skip ") so the oc column feeds the same counters.
	print(("ok " if cond else "bad ") + label + (f" [{detail}]" if detail and not cond else ""))


def expect_skip(label):
	print(f"skip {label}")


def terminate_host(proc):
	"""Backstop so a crash between Popen and the explicit teardown

cannot leave the gated R1 host service serving past the driver's
	lifetime."""
	if proc.poll() is None:
		proc.terminate()
		proc.wait()


def expect_denied(label, out, marker):
	cond = marker not in out.stdout and marker not in out.stderr
	expect(label, cond, f"rc={out.returncode} out={out.stdout[:160]!r} err={out.stderr[:160]!r}")


def twin_hash(repo):
	return subprocess.run(
		["bash", "-c",
		 f"cd '{repo}' && find .tasks -type f -not -name '*.claim' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1"],
		capture_output=True, text=True).stdout.strip()


def board_snapshot(repo):
	# Entries carry their find %y type, so sockets and fifos that the
	# -type f hash walk never sees still count as residue.
	return subprocess.run(
		["bash", "-c",
		 f"cd '{repo}' && find .tasks -printf '%y %p\\n' | LC_ALL=C sort"],
		capture_output=True, text=True).stdout


print("== oc classes 1-3: relative path, symlink, worktree ==")
if HAVE_BWRAP:
	out = run_client("adv-sess", "worker", "cat ./.tasks/reports/secret.md")
	expect_denied("oc deny: relative storage read masked", out, SECRET)
	out = run_client("adv-sess", "worker", "cat .tasks/../.tasks/reports/secret.md")
	expect_denied("oc deny: dot-dot storage read masked", out, SECRET)
	link = os.path.join(RUN, "adv-link")
	if os.path.islink(link) or os.path.exists(link):
		os.unlink(link)
	os.symlink(os.path.join(FIX, ".tasks", "reports", "secret.md"), link)
	out = run_client("adv-sess", "worker", f"cat {link}")
	expect_denied("oc deny: absolute symlink from the shared /tmp masked", out, SECRET)
	out = run_client("adv-sess", "worker", f"cat {WORKTREE}/.tasks/current/sibling.md")
	expect_denied("oc deny: sibling worktree storage read masked", out, SIBLING)
	out = run_plain(f"cat {FIX}/.tasks/reports/secret.md")
	expect("oc twin: plain host-side storage read succeeds without enforcement",
	       out.returncode == 0 and SECRET in out.stdout, out.stderr[:160])
else:
	expect_skip("oc deny/twin: relative, symlink, worktree class (bwrap not installed; degraded mode)")

print("== oc class 4+5: alternate commands and child-process wrappers ==")
if HAVE_BWRAP:
	for name, cmd in [
		("head", "head -1 .tasks/reports/secret.md"),
		("tail", "tail -1 .tasks/reports/secret.md"),
		("sed", "sed -n 1p .tasks/reports/secret.md"),
		("awk", "awk '1' .tasks/reports/secret.md"),
		("find-exec", "find .tasks -name '*.md' -exec head -1 {} \\;"),
		("stat", "stat .tasks/reports/secret.md"),
		("git-no-index", "git diff --no-index /dev/null .tasks/reports/secret.md"),
		("python", "python3 -c \"print(open('.tasks/reports/secret.md').read())\""),
		("bash-c", "bash -c 'cat .tasks/reports/secret.md'"),
		("substitution", "echo \"$(cat .tasks/reports/secret.md)\""),
		("env", "env cat .tasks/reports/secret.md"),
		("timeout", "timeout 5 cat .tasks/reports/secret.md"),
	]:
		out = run_client("adv-sess", "worker", cmd)
		expect_denied(f"oc deny: alternate command {name} masked", out, SECRET)
	out = run_plain("cat .tasks/reports/secret.md")
	expect("oc twin: alternate-command control reads the board without enforcement",
	       out.returncode == 0 and SECRET in out.stdout, out.stderr[:160])
else:
	expect_skip("oc deny/twin: alternate-command and child-process class (bwrap not installed; degraded mode)")

print("== oc class 6: inherited descriptors ==")
if HAVE_BWRAP:
	out = run_client("adv-sess", "worker",
	                 "exec 3< .tasks/reports/secret.md 2>/dev/null || echo OPEN-REFUSED; "
	                 "cat <&3 2>/dev/null || echo FD-READ-REFUSED; "
	                 "cat 0< .tasks/reports/secret.md 2>/dev/null || echo STDIN-REDIR-REFUSED; "
	                 "ls -l /proc/self/fd; true")
	expect_denied("oc deny: inherited-fd class (exec 3<, cat <&3, cat 0<) cannot open storage", out, SECRET)
	expect("oc deny: fd open refused under the mask",
	       "OPEN-REFUSED" in out.stdout + out.stderr, out.stdout[-160:] + out.stderr[-160:])
	expect("oc deny: no storage descriptors listed in /proc/self/fd",
	       ".tasks" not in out.stdout.split("FD-READ-REFUSED")[-1], out.stdout[-200:])
	out = run_plain("exec 3< .tasks/reports/secret.md && cat <&3")
	expect("oc twin: inherited-fd read succeeds without enforcement",
	       out.returncode == 0 and SECRET in out.stdout, out.stderr[:160])
else:
	expect_skip("oc deny/twin: inherited-fd class (bwrap not installed; degraded mode)")

print("== oc class 9: compound-composition shapes ==")
if HAVE_BWRAP:
	for name, cmd in [
		("and", "cat .tasks/reports/secret.md && echo AND-RAN"),
		("or", "cat .tasks/reports/secret.md || echo OR-RAN"),
		("sequence", "cat .tasks/reports/secret.md ; echo SEQ-RAN"),
		("pipe", "cat .tasks/reports/secret.md | grep -a SUITE"),
		("substitution", "echo \"leak=$(cat .tasks/reports/secret.md)\""),
		("backtick", "echo \"leak=`cat .tasks/reports/secret.md`\""),
		("redirect", "cat .tasks/reports/secret.md > /tmp/adv-exfil; cat /tmp/adv-exfil"),
	]:
		out = run_client("adv-sess", "worker", cmd)
		expect_denied(f"oc deny: composition {name} leaks no board bytes", out, SECRET)
	if os.path.exists("/tmp/adv-exfil"):
		os.unlink("/tmp/adv-exfil")
	out = run_plain("cat .tasks/reports/secret.md | grep -a SUITE")
	expect("oc twin: pipe composition reads the board without enforcement",
	       SECRET in out.stdout, out.stderr[:160])
else:
	expect_skip("oc deny/twin: compound-composition class (bwrap not installed; degraded mode)")

print("== oc class 8: write side and residue ==")
if HAVE_BWRAP:
	base = twin_hash(TWIN)
	for name, cmd in [
		("redirect", "echo ADV-WRITEPIN > .tasks/reports/secret.md"),
		("tee", "echo tee-pin | tee .tasks/reports/secret.md"),
		("sed-i", "sed -i 's/secret/REPLACED/' .tasks/reports/secret.md"),
		("mv", "mv .tasks/reports/secret.md .tasks/reports/moved.md"),
		("rm", "rm -f .tasks/reports/secret.md"),
		("rm-tree", "rm -rf .tasks"),
		("lock-touch", "touch .tasks/.lock"),
	]:
		out = run_client("adv-sess", "worker", cmd, cwd=TWIN)
		expect_denied(f"oc deny: write shape {name} lands in the mask only", out, TWIN_SECRET)
	expect("oc deny: masked write shapes leave the twin board byte-identical",
	       twin_hash(TWIN) == base, f"{base[:12]}.. -> {twin_hash(TWIN)[:12]}..")
	out = run_plain("echo ADV-WRITEPIN > .tasks/reports/secret.md; cat .tasks/reports/secret.md", cwd=TWIN)
	expect("oc twin: write class mutates the twin board without enforcement",
	       "ADV-WRITEPIN" in out.stdout, out.stderr[:160])
else:
	expect_skip("oc deny/twin: write-side class (bwrap not installed; degraded mode)")

print("== oc class 7: git-history smuggling ==")
if HAVE_BWRAP:
	out = run_client("adv-sess", "worker",
	                 "git add -f .tasks/reports/secret.md && git -c user.email=adv@fixture -c user.name=adv commit -qm smuggle && git show HEAD:.tasks/reports/secret.md",
	                 cwd=TWIN)
	expect_denied("oc deny: git add -f/commit/show smuggling masked", out, TWIN_SECRET)
	out = run_plain("echo OC-GIT-TWIN-3c07 > .tasks/reports/secret.md && git add -f .tasks/reports/secret.md && git -c user.email=adv@fixture -c user.name=adv commit -qm twin-smuggle && git show HEAD:.tasks/reports/secret.md",
	                cwd=TWIN)
	expect("oc twin: git smuggling recovers its own seeded marker without enforcement",
	       "OC-GIT-TWIN-3c07" in out.stdout, out.stderr[:200])
else:
	expect_skip("oc deny/twin: git-history smuggling class (bwrap not installed; degraded mode)")

print("== oc DC2: the other harness's transcript-copy store ==")
OC_XDG = os.environ["ISOLATION_OC_XDG"]
seed_file = os.path.join(OC_XDG, "opencode", "storage", "session", "default", "transcript.jsonl")
if HAVE_BWRAP:
	out = run_client("adv-sess", "worker", f"cat '{seed_file}'")
	expect_denied("oc deny: DC2 opencode transcript store masked under execute_masked", out, "DC2-OC-SEED-MARKER-4d18")
	out = run_client("adv-sess", "worker",
	                 f"cat '{os.environ['ISOLATION_OC_XDG']}/opencode/storage/session/default/nonexistent.md'")
	expect("oc deny: DC2 store's tmpfs hides seeded entries (empty view)",
	       "DC2-OC-SEED-MARKER-4d18" not in out.stdout + out.stderr,
	       out.stdout[:160])
else:
	expect_skip("oc deny: DC2 transcript-copy store (bwrap not installed; degraded mode)")
out = run_plain(f"cat '{seed_file}'")
expect("oc twin: DC2 store seed reads back without enforcement (characterization)",
       "DC2-OC-SEED-MARKER-4d18" in out.stdout, out.stderr[:160])

print("== oc cwd-board mask class: a standalone board at any depth around the request cwd ==")
CWD_BOARD = os.path.join(RUN, "cwd-board")
os.makedirs(os.path.join(CWD_BOARD, ".tasks", "reports"), mode=0o700, exist_ok=True)
CWD_BOARD_INNER = os.path.join(CWD_BOARD, "inner")
os.makedirs(CWD_BOARD_INNER, mode=0o700, exist_ok=True)
CWD_BOARD_D2 = os.path.join(CWD_BOARD, "d2", "l2")
os.makedirs(CWD_BOARD_D2, mode=0o700, exist_ok=True)
CWD_BOARD_D3 = os.path.join(CWD_BOARD, "d3", "l3", "l3c")
os.makedirs(CWD_BOARD_D3, mode=0o700, exist_ok=True)
CWD_BOARD_SECRET = "CWD-BOARD-SECRET-7a33"
with open(os.path.join(CWD_BOARD, ".tasks", "reports", "secret.md"), "w") as handle:
	handle.write(CWD_BOARD_SECRET + "\n")


if HAVE_BWRAP:
	cwd_board_before = twin_hash(CWD_BOARD)
	out = run_client("adv-sess", "worker", "cat .tasks/reports/secret.md", cwd=CWD_BOARD)
	expect_denied("oc deny: cwd IS the board - the self candidate masks the read (cwd-board)",
	              out, CWD_BOARD_SECRET)
	out = run_client("adv-sess", "worker", "cat ../.tasks/reports/secret.md", cwd=CWD_BOARD_INNER)
	expect_denied("oc deny: cwd one level inside the board - the parent candidate masks the read (cwd-board)",
	              out, CWD_BOARD_SECRET)
	out = run_client("adv-sess", "worker", f"cat {CWD_BOARD}/.tasks/reports/secret.md", cwd=CWD_BOARD_INNER)
	expect_denied("oc deny: absolute parent-board read masked (cwd-board)",
	              out, CWD_BOARD_SECRET)
	out = run_client("adv-sess", "worker", "cat ../../.tasks/reports/secret.md", cwd=CWD_BOARD_D2)
	expect_denied("oc deny: depth-2 cwd - the ancestor walk masks the board read (cwd-board)",
	              out, CWD_BOARD_SECRET)
	out = run_client("adv-sess", "worker", f"cat {CWD_BOARD}/.tasks/reports/secret.md", cwd=CWD_BOARD_D2)
	expect_denied("oc deny: depth-2 absolute board read masked by the walk (cwd-board)",
	              out, CWD_BOARD_SECRET)
	out = run_client("adv-sess", "worker", "cat ../../../.tasks/reports/secret.md", cwd=CWD_BOARD_D3)
	expect_denied("oc deny: depth-3 cwd - the ancestor walk masks the board read (cwd-board)",
	              out, CWD_BOARD_SECRET)
	out = run_client("adv-sess", "worker", f"cat {CWD_BOARD}/.tasks/reports/secret.md", cwd=CWD_BOARD_D3)
	expect_denied("oc deny: depth-3 absolute board read masked by the walk (cwd-board)",
	              out, CWD_BOARD_SECRET)
	out = run_plain("cat .tasks/reports/secret.md", cwd=CWD_BOARD)
	expect("oc twin: board-as-cwd read succeeds without enforcement (characterization)",
	       out.returncode == 0 and CWD_BOARD_SECRET in out.stdout, out.stderr[:160])
	out = run_plain("cat ../.tasks/reports/secret.md", cwd=CWD_BOARD_INNER)
	expect("oc twin: board-as-parent read succeeds without enforcement (characterization)",
	       out.returncode == 0 and CWD_BOARD_SECRET in out.stdout, out.stderr[:160])
	out = run_plain("cat ../../.tasks/reports/secret.md && cat " + CWD_BOARD + "/.tasks/reports/secret.md", cwd=CWD_BOARD_D2)
	expect("oc twin: depth-2 board reads succeed without enforcement (characterization)",
	       out.returncode == 0 and out.stdout.count(CWD_BOARD_SECRET) >= 2, out.stderr[:160])
	out = run_plain("cat ../../../.tasks/reports/secret.md && cat " + CWD_BOARD + "/.tasks/reports/secret.md", cwd=CWD_BOARD_D3)
	expect("oc twin: depth-3 board reads succeed without enforcement (characterization)",
	       out.returncode == 0 and out.stdout.count(CWD_BOARD_SECRET) >= 2, out.stderr[:160])
	expect("oc integrity: the cwd-board fixture stayed byte-identical (cwd-board)",
	       twin_hash(CWD_BOARD) == cwd_board_before)
else:
	expect_skip("oc deny/twin: cwd-board mask class (bwrap not installed; degraded mode)")

print("== oc R1: registered-pair replay from a service-descended peer ==")
if HAVE_BWRAP:
	r1_run = os.path.join(RUN, "r1-runtime")
	os.makedirs(r1_run, mode=0o700, exist_ok=True)
	r1_sock = os.path.join(r1_run, "broker.sock")
	r1_token = "tok-r1-replay"
	with open(os.path.join(r1_run, "token"), "w") as token_handle:
		token_handle.write(r1_token)
	r1_log = os.path.join(r1_run, "service.log")
	r1_host_py = os.path.join(RUN, "r1-host.py")
	with open(r1_host_py, "w") as host_handle:
		host_handle.write(
			"import importlib.util, sys, threading, time\n"
			f"sys.path.insert(0, {LIB!r})\n"
			f"spec = importlib.util.spec_from_file_location('svc', "
			f"{os.path.join(LIB, 'oc-task-service.py')!r})\n"
			"mod = importlib.util.module_from_spec(spec)\n"
			"spec.loader.exec_module(mod)\n"
			f"svc = mod.BrokerService({r1_sock!r}, {FIX!r}, {r1_token!r}, "
			f"{r1_log!r}, exec_peer_gate=True)\n"
			"svc.state[\"registry\"].add((\"adv-sess\", \"worker\"))\n"
			"svc.state[\"registry\"].add((\"adv-plan\", \"planner\"))\n"
			"threading.Thread(target=svc.serve_forever, "
			"kwargs={\"poll_interval\": 0.2}, daemon=True).start()\n"
			"time.sleep(600)\n"
		)
	r1_replay_py = os.path.join(RUN, "r1-replay.py")
	with open(r1_replay_py, "w") as replay_handle:
		replay_handle.write(
			"import json, socket, sys\n"
			"sock, token_path, cwd, entry = sys.argv[1:5]\n"
			"ancestor = int(sys.argv[5]) if len(sys.argv) > 5 else None\n"
			"request = {\"token\": open(token_path).read().strip(),\n"
			"           \"session\": \"adv-plan\", \"agent\": \"planner\", "
			"\"cwd\": cwd,\n"
			"           \"argv\": [\"tasks\", \"log\", entry, \"--from\", "
			"\"planner\",\n"
			"                    \"R1-REPLAY-MUTATION-8b20\"], "
			"\"timeout\": 60}\n"
			"if ancestor is not None:\n"
			"    request[\"peer_ancestor\"] = ancestor\n"
			"conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n"
			"conn.settimeout(90)\n"
			"conn.connect(sock)\n"
			"conn.sendall(json.dumps(request).encode())\n"
			"conn.shutdown(socket.SHUT_WR)\n"
			"buf = b\"\"\n"
			"while True:\n"
			"    try:\n"
			"        chunk = conn.recv(65536)\n"
			"    except socket.timeout:\n"
			"        break\n"
			"    if not chunk:\n"
			"        break\n"
			"    buf += chunk\n"
			"print(buf.decode(errors=\"replace\"))\n"
		)

	def r1_send(request):
		conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
		conn.settimeout(120)
		conn.connect(r1_sock)
		conn.sendall(json.dumps(request).encode())
		conn.shutdown(socket.SHUT_WR)
		buf = b""
		while True:
			try:
				chunk = conn.recv(65536)
			except socket.timeout:
				break
			if not chunk:
				break
			buf += chunk
		conn.close()
		return buf.decode(errors="replace")

	r1_before = twin_hash(FIX)
	r1_host = subprocess.Popen([sys.executable, r1_host_py], env=env_full,
	                           stdout=subprocess.DEVNULL,
	                           stderr=subprocess.DEVNULL)
	atexit.register(terminate_host, r1_host)
	r1_deadline = time.time() + 20
	while not os.path.exists(r1_sock) and time.time() < r1_deadline:
		time.sleep(0.1)

	def r1_masked_replay(with_forged_ancestor):
		masked_command = (f"python3 {r1_replay_py} {r1_sock} "
		                   f"{r1_run}/token {FIX} {ENTRY}")
		if with_forged_ancestor:
			masked_command += f" {os.getpid()}"
		return r1_send({
			"token": r1_token, "session": "adv-sess", "agent": "worker",
			"cwd": FIX, "argv": ["/bin/bash", "-c", masked_command],
			"stdin": "", "timeout": 90,
		})

	out = r1_masked_replay(False)
	expect("oc deny: masked child replaying a live planner pair refused by "
	       "the exec-peer ancestry gate (R1)",
	       "descends from the broker service process" in out,
	       f"out={out[:200]!r}")
	expect("oc deny: replayed planner write never reached the board (R1)",
	       "R1-REPLAY-MUTATION-8b20" not in
	       subprocess.run(["bash", "-c", f"grep -r R1-REPLAY {FIX}/.tasks || true"],
	                      capture_output=True, text=True).stdout)
	out = r1_masked_replay(True)
	expect("oc deny: replay with a forged --peer-ancestor still refused by "
	       "the through-service check (R1)",
	       "descends from the broker service process" in out,
	       f"out={out[:200]!r}")
	r1_audit = open(r1_log).read()
	expect("oc audit: both replays carry the ancestry-gate refusal record (R1)",
	       r1_audit.count("descends from the broker service process") == 2
	       and '"class": "sanctioned"' not in r1_audit,
	       r1_audit[-300:])
	out = subprocess.run(
		[sys.executable, os.path.join(LIB, "oc-broker-client.py"),
		 "--registry", r1_run, "--session", "adv-sess", "--agent", "worker",
		 "--peer-ancestor", str(os.getpid()), "exec",
		 f"tasks show {ENTRY} --json"],
		capture_output=True, text=True, cwd=FIX, env=env_full, timeout=180)
	expect("oc control: genuine client with --peer-ancestor round-trips "
	       "through the gated service (R1)",
	       out.returncode == 0 and '"Task":"Adversarial Target"' in out.stdout,
	       f"rc={out.returncode} out={out.stdout[:160]!r} err={out.stderr[:200]!r}")
	expect("oc integrity: the R1 fixture board stayed byte-identical (R1)",
	       twin_hash(FIX) == r1_before)
	r1_host.terminate()
	r1_host.wait()
else:
	expect_skip("oc R1 registered-pair replay class (bwrap not installed; degraded mode)")

print("== oc F2: main() arms the exec-peer gate in the process-hosted path ==")
if HAVE_BWRAP:
	f2_run = os.path.join(RUN, "f2-runtime")
	os.makedirs(f2_run, mode=0o700, exist_ok=True)
	f2_sock = os.path.join(f2_run, "broker.sock")
	f2_token = "tok-f2-arming"
	with open(os.path.join(f2_run, "token"), "w") as token_handle:
		token_handle.write(f2_token)
	f2_log = os.path.join(f2_run, "service.log")
	f2_host_py = os.path.join(RUN, "f2-host.py")
	with open(f2_host_py, "w") as host_handle:
		host_handle.write(
			"import importlib.util, sys\n"
			f"sys.path.insert(0, {LIB!r})\n"
			f"spec = importlib.util.spec_from_file_location('svcmain', "
			f"{os.path.join(LIB, 'oc-task-service.py')!r})\n"
			"mod = importlib.util.module_from_spec(spec)\n"
			"spec.loader.exec_module(mod)\n"
			"# production registers pairs through the opencode-only control\n"
			"# channel; the suite seeds the pair the guard would register so\n"
			"# the pin exercises main() verbatim\n"
			"orig_init = mod.BrokerService.__init__\n"
			"def seeded_init(self, *args, **kwargs):\n"
			"    orig_init(self, *args, **kwargs)\n"
			"    self.state[\"registry\"].add((\"adv-plan\", \"planner\"))\n"
			"mod.BrokerService.__init__ = seeded_init\n"
			f"sys.argv = ['oc-task-service.py', '--socket', {f2_sock!r}, "
			f"'--repo', {FIX!r}, '--audit-log', {f2_log!r}, "
			f"'--token-file', {os.path.join(f2_run, 'token')!r}]\n"
			"sys.exit(mod.main())\n"
		)
	f2_replay_py = os.path.join(RUN, "f2-replay.py")
	with open(f2_replay_py, "w") as replay_handle:
		replay_handle.write(
			"import json, socket, sys\n"
			"sock, token_path, cwd, entry = sys.argv[1:5]\n"
			"request = {\"token\": open(token_path).read().strip(),\n"
			"           \"session\": \"adv-plan\", \"agent\": \"planner\", "
			"\"cwd\": cwd,\n"
			"           \"argv\": [\"tasks\", \"show\", entry, \"--json\"], "
			"\"timeout\": 60}\n"
			"conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n"
			"conn.settimeout(90)\n"
			"conn.connect(sock)\n"
			"conn.sendall(json.dumps(request).encode())\n"
			"conn.shutdown(socket.SHUT_WR)\n"
			"buf = b\"\"\n"
			"while True:\n"
			"    try:\n"
			"        chunk = conn.recv(65536)\n"
			"    except socket.timeout:\n"
			"        break\n"
			"    if not chunk:\n"
			"        break\n"
			"    buf += chunk\n"
			"print(buf.decode(errors=\"replace\"))\n"
		)

	def f2_send(request):
		conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
		conn.settimeout(120)
		conn.connect(f2_sock)
		conn.sendall(json.dumps(request).encode())
		conn.shutdown(socket.SHUT_WR)
		buf = b""
		while True:
			try:
				chunk = conn.recv(65536)
			except socket.timeout:
				break
			if not chunk:
				break
			buf += chunk
		conn.close()
		return buf.decode(errors="replace")

	f2_host = subprocess.Popen([sys.executable, f2_host_py], env=env_full,
	                           stdout=subprocess.DEVNULL,
	                           stderr=subprocess.DEVNULL)
	atexit.register(terminate_host, f2_host)
	f2_deadline = time.time() + 20
	while not os.path.exists(f2_sock) and time.time() < f2_deadline:
		time.sleep(0.1)
	# the outer exec rides the f2 service itself (run_client pins the
	# main registry): the replay child must descend from the f2 service
	# for the ancestry gate to see the production shape
	out = f2_send({"token": f2_token, "session": "adv-plan", "agent": "planner",
	               "cwd": FIX, "argv": ["/bin/bash", "-c",
	               f"python3 {f2_replay_py} {f2_sock} {f2_run}/token {FIX} {ENTRY}"],
	               "stdin": "", "timeout": 90})
	expect("oc F2: the process-hosted main() service refuses the replay of "
	       "the live planner pair (F2)",
	       "descends from the broker service process" in out
	       and "Adversarial Target" not in out,
	       f"out={out[:240]!r}")
	f2_audit = open(f2_log).read()
	expect("oc F2: the arming refusal carries its audit record (F2)",
	       f2_audit.count("descends from the broker service process") == 1,
	       f2_audit[-300:])
	out = f2_send({"token": f2_token, "session": "adv-plan", "agent": "planner",
	               "cwd": FIX, "argv": ["tasks", "show", ENTRY, "--json"],
	               "timeout": 60})
	expect("oc F2: the armed gate still serves a direct peer reaching the pin (F2)",
	       "Adversarial Target" in out,
	       f"out={out[:200]!r}")
	out = run_client("adv-sess", "worker",
	                 f"python3 {f2_replay_py} {os.path.join(RUN, 'broker.sock')} "
	                 f"{os.path.join(RUN, 'token')} {FIX} {ENTRY}")
	expect("oc F2: the in-process suite construction stays disarmed - the "
	       "same replay executes there (F2)",
	       "Adversarial Target" in out.stdout,
	       f"rc={out.returncode} out={out.stdout[:200]!r} err={out.stderr[:200]!r}")
	f2_host.terminate()
	f2_host.wait()
else:
	expect_skip("oc F2 main() gate-arming pin (bwrap not installed; degraded mode)")

print("== oc recovery and concurrency (claims, lock, killed masked child) ==")
if HAVE_BWRAP:
	wt_tasks = os.path.join(WORKTREE, ".tasks")
	init = run_plain(f"'{TASKS_BIN_DIR}/tasks' init", cwd=WORKTREE)
	new = run_plain(f"'{TASKS_BIN_DIR}/tasks' new --id ADV-9 --name 'Recovery Target'", cwd=WORKTREE)
	wt_entries = sorted(f for f in os.listdir(os.path.join(wt_tasks, "current"))
	                    if f.startswith("ADV-9-"))
	expect("oc recovery: worktree board scaffolded (setup)",
	       init.returncode == 0 and new.returncode == 0 and bool(wt_entries),
	       f"init rc={init.returncode} new rc={new.returncode} err={new.stderr[:160]!r}")
	wt_entry = wt_entries[0]
	oc_label = "oc-channel-" + hashlib.sha256(b"tok-adversarial").hexdigest()[:16]
	claim = run_plain(f"'{TASKS_BIN_DIR}/tasks' claim {wt_entry} --owner {oc_label}", cwd=WORKTREE)
	expect("oc recovery: claim taken on the worktree board (setup)",
	       claim.returncode == 0, f"rc={claim.returncode} err={claim.stderr[:160]!r}")
	out = run_plain(f"'{TASKS_BIN_DIR}/tasks' claims --json", cwd=WORKTREE)
	expect("oc recovery: claims sweep reports the live channel-owned claim",
	       out.returncode == 0 and oc_label in out.stdout, out.stdout[:200])
	out = run_client("adv-sess", "worker",
	                 f"tasks log {wt_entry} --from someone-else 'oc recovery heartbeat through the channel'",
	                 cwd=WORKTREE)
	expect("oc recovery: sanctioned channel log lands as the channel-owned claim heartbeat",
	       out.returncode == 0,
	       f"rc={out.returncode} out={out.stdout[:120]!r} err={out.stderr[:160]!r}")
	out = run_client("adv-sess", "worker", f"tasks show {wt_entry} --json", cwd=WORKTREE)
	expect("oc recovery: the heartbeat entry carries the channel attribution",
	       out.returncode == 0 and "oc recovery heartbeat" in out.stdout
	       and "oc-channel-" in out.stdout, out.stdout[-200:])
	new2 = run_plain(f"'{TASKS_BIN_DIR}/tasks' new --id ADV-10 --name 'Recovery Foreign'", cwd=WORKTREE)
	wt2_entries = sorted(f for f in os.listdir(os.path.join(wt_tasks, "current"))
	                     if f.startswith("ADV-10-"))
	wt2 = wt2_entries[0]
	claim2 = run_plain(f"'{TASKS_BIN_DIR}/tasks' claim {wt2} --owner manager-main", cwd=WORKTREE)
	expect("oc recovery: foreign claim taken (setup)", claim2.returncode == 0,
	       f"rc={claim2.returncode} err={claim2.stderr[:160]!r}")
	out = run_plain(f"TASKS_SESSION=intruder '{TASKS_BIN_DIR}/tasks' release {wt2}", cwd=WORKTREE)
	expect("oc recovery: a foreign session cannot release a live claim it does not own (fail closed)",
	       out.returncode != 0 and "claimed by" in out.stderr,
	       f"rc={out.returncode} out={out.stdout[:160]!r} err={out.stderr[:160]!r}")
	out = run_client("adv-sess", "worker",
	                 f"tasks log {wt2} --from {oc_label} 'oc recovery foreign-claim write'",
	                 cwd=WORKTREE)
	expect("oc recovery: the live foreign claim does not gate the sanctioned log, write lands channel-attributed",
	       out.returncode == 0, f"rc={out.returncode} err={out.stderr[:160]!r}")
	out = run_client("adv-sess", "worker", f"tasks show {wt2} --json", cwd=WORKTREE)
	expect("oc recovery: the foreign-claimed entry carries the channel-attributed write",
	       out.returncode == 0 and "foreign-claim write" in out.stdout
	       and "oc-channel-" in out.stdout, out.stdout[-200:])
	results = {}

	def oc_log_thread(index):
		results[index] = run_client(
			"adv-sess", "worker",
			f"tasks log {wt_entry} --from {oc_label} 'oc concurrent write {index}'",
			cwd=WORKTREE)

	threads = [threading.Thread(target=oc_log_thread, args=(i,)) for i in range(2)]
	for thread in threads:
		thread.start()
	for thread in threads:
		thread.join(180)
	expect("oc recovery: two concurrent sanctioned writes both land under the board lock",
	       results[0].returncode == 0 and results[1].returncode == 0,
	       f"rc0={results[0].returncode} rc1={results[1].returncode}")
	out = run_client("adv-sess", "worker", f"tasks show {wt_entry} --json", cwd=WORKTREE)
	expect("oc recovery: both concurrent entries present in the Work Log",
	       out.returncode == 0 and "oc concurrent write 0" in out.stdout
	       and "oc concurrent write 1" in out.stdout, out.stdout[-200:])
	oc_residue_snippet = (
		"mkdir -p .tasks/oc-residue-dir && "
		"python3 -c 'import socket; sock = socket.socket(socket.AF_UNIX); "
		"sock.bind(\".tasks/oc-residue.sock\")' && "
		"touch .tasks/oc-residue.lock .tasks/.lock.residue")
	twin_snap_before = board_snapshot(TWIN)
	plant = run_plain(
		oc_residue_snippet + " && "
		"test -S .tasks/oc-residue.sock -a -d .tasks/oc-residue-dir "
		"-a -f .tasks/oc-residue.lock -a -f .tasks/.lock.residue",
		cwd=TWIN)
	expect("oc recovery twin: the residue payload plants sockets, temp dirs, and lock files without enforcement (setup)",
	       plant.returncode == 0, f"rc={plant.returncode} err={plant.stderr[:200]!r}")
	twin_snap_planted = board_snapshot(TWIN)
	expect("oc recovery twin: the board snapshot detector sees the planted residue (detector validation)",
	       all(name in twin_snap_planted for name in
	           ("oc-residue-dir", "oc-residue.sock", "oc-residue.lock", ".lock.residue"))
	       and twin_snap_planted != twin_snap_before, twin_snap_planted[-300:])
	cleanup = run_plain("rm -rf .tasks/oc-residue-dir .tasks/oc-residue.sock "
	                    ".tasks/oc-residue.lock .tasks/.lock.residue", cwd=TWIN)
	expect("oc recovery twin: the twin board snapshot is restored after cleanup (detector validation)",
	       cleanup.returncode == 0 and board_snapshot(TWIN) == twin_snap_before)
	wt_hash_before = twin_hash(WORKTREE)
	snap_before = board_snapshot(WORKTREE)
	claims_before = run_plain(f"'{TASKS_BIN_DIR}/tasks' claims --json", cwd=WORKTREE).stdout
	out = run_client("adv-sess", "worker",
	                 oc_residue_snippet + " && head -c 20000000 /dev/zero", cwd=WORKTREE)
	expect("oc recovery: a masked child planting residue and flooding output is killed at the cap",
	       out.returncode == 125, f"rc={out.returncode} out={len(out.stdout)} err={out.stderr[:120]!r}")
	snap_after = board_snapshot(WORKTREE)
	expect("oc recovery: the crashed masked child left no board residue (no sockets, temp dirs, or lock files)",
	       snap_after == snap_before,
	       f"diff={sorted(set(snap_after.splitlines()) ^ set(snap_before.splitlines()))[:6]}")
	expect("oc recovery: the killed masked child left the worktree board byte-identical",
	       twin_hash(WORKTREE) == wt_hash_before)
	claims_state = run_plain(f"'{TASKS_BIN_DIR}/tasks' claims --json", cwd=WORKTREE).stdout
	expect("oc recovery: the killed masked child left no claim residue",
	       claims_state == claims_before)
	out = run_client("adv-sess", "worker", f"tasks show {wt_entry} --json", cwd=WORKTREE)
	expect("oc recovery: the broker keeps serving sanctioned calls after the killed masked child",
	       out.returncode == 0, f"rc={out.returncode} err={out.stderr[:160]!r}")
else:
	expect_skip("oc recovery and concurrency class (bwrap not installed; degraded mode)")

print("== oc sanctioned controls ==")
out = run_client("adv-sess", "worker", f"tasks show {ENTRY} --json")
expect("oc control: sanctioned show round-trips under enforcement",
       out.returncode == 0 and '"Task":"Adversarial Target"' in out.stdout,
       f"rc={out.returncode} out={out.stdout[:160]!r} err={out.stderr[:200]!r}")
out = run_plain(f"TASKS_SESSION=adv-twin {TASKS_BIN_DIR}/tasks show {TWIN_TASKFILE} --json", cwd=TWIN)
expect("oc twin: the sanctioned shape also works without enforcement (characterization)",
       '"Task":"Adversarial Twin"' in out.stdout, out.stderr[:200])
PYEOF
)" || oc_rc=$?
absorb_results "opencode machine column" "$OC_OUT" "$oc_rc"

if [[ "$(board_hash "$REPO_FIX")" == "$BASE_HASH" ]]; then
	ok "oc column leaves the enforcement fixture board byte-identical"
else
	bad "oc column leaves the enforcement fixture board byte-identical"
fi

echo "== 5. routed findings: argv element cap and runtime-dir verification =="
RF_OUT="$(REPO_ROOT="$REPO_ROOT" ISOLATION_LIB="$LIB" ISOLATION_FIX="$REPO_FIX" \
	python3 - <<'PYEOF'
import importlib.util
import os
import subprocess
import sys
import threading
import time

LIB = os.environ["ISOLATION_LIB"]
FIX = os.environ["ISOLATION_FIX"]
REPO_ROOT = os.environ["REPO_ROOT"]
RUN = os.path.join(os.path.dirname(FIX), "rf-state")
os.makedirs(RUN, exist_ok=True)
os.chmod(RUN, 0o700)

spec = importlib.util.spec_from_file_location(
	"oc_task_service_routed", os.path.join(LIB, "oc-task-service.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def expect(label, cond, detail=""):
	print(("ok " if cond else "bad ") + label + (f" [{detail}]" if detail and not cond else ""))


def spawn_service(socket_name):
	"""One in-process BrokerService on its own socket, registry preseeded."""
	reg = os.path.join(RUN, socket_name)
	os.makedirs(reg, exist_ok=True)
	os.chmod(reg, 0o700)
	token = "tok-" + socket_name
	with open(os.path.join(reg, "token"), "w") as fh:
		fh.write(token)
	svc = mod.BrokerService(os.path.join(reg, "broker.sock"), FIX, token,
	                        os.path.join(reg, "service.log"))
	svc.state["registry"].add(("adv-cap", "worker"))
	threading.Thread(target=svc.serve_forever, kwargs={"poll_interval": 0.2},
	                 daemon=True).start()
	time.sleep(0.2)
	return reg


def client(reg, command):
	return subprocess.run(
		[sys.executable, os.path.join(LIB, "oc-broker-client.py"), "--registry", reg,
		 "--session", "adv-cap", "--agent", "worker", "exec", command],
		capture_output=True, text=True, cwd=FIX, timeout=120)


# R3 (10-2 parity): a per-element argv cap. The pi service refuses any
# argv element over 4096 bytes before execution; the landed oc broker
# had only the 64-element width cap, so a 4097-byte element rode
# through to the CLI. Red at the pre-fix base: exit 0, no refusal.
reg = spawn_service("cap-reg")
out = client(reg, "tasks list --limit " + "9" * 4097)
expect("oc routed R3: 4097-byte argv element refused at the cap",
       out.returncode == 126 and "4096" in out.stderr,
       f"rc={out.returncode} out={out.stdout[:120]!r} err={out.stderr[:160]!r}")
out = client(reg, "tasks list --limit " + "9" * 4077)
expect("oc routed R3: a carrier element at exactly the 4096-byte cap is not refused",
       not (out.returncode == 126 and "4096" in out.stderr),
       f"rc={out.returncode} err={out.stderr[:160]!r}")

# R4 (10-2 parity): the pi service refuses to bind outside a 0700
# runtime dir; the oc broker silently chmod-repaired a wide one and
# served. Red at the pre-fix base: the socket appeared and the
# service kept running in the wide dir.
wide = os.path.join(RUN, "wide-reg")
os.makedirs(wide, exist_ok=True)
os.chmod(wide, 0o755)
try:
	proc = subprocess.run(
		[sys.executable, os.path.join(LIB, "oc-task-service.py"),
		 "--socket", os.path.join(wide, "broker.sock"), "--repo", FIX,
		 "--audit-log", os.path.join(wide, "service.log")],
		capture_output=True, text=True, timeout=30)
	expect("oc routed R4: service refuses to bind outside a 0700 runtime dir",
	       proc.returncode != 0 and "0700" in proc.stderr,
	       f"rc={proc.returncode} err={proc.stderr[:200]!r}")
except subprocess.TimeoutExpired:
	expect("oc routed R4: service refuses to bind outside a 0700 runtime dir",
	       False, "service kept serving in a 0755 dir until the probe timeout")

tight = os.path.join(RUN, "tight-reg")
os.makedirs(tight, exist_ok=True)
os.chmod(tight, 0o700)
proc = subprocess.Popen(
	[sys.executable, os.path.join(LIB, "oc-task-service.py"),
	 "--socket", os.path.join(tight, "broker.sock"), "--repo", FIX,
	 "--audit-log", os.path.join(tight, "service.log")],
	stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
socket_up = False
for _ in range(50):
	if os.path.exists(os.path.join(tight, "broker.sock")):
		socket_up = True
		break
	time.sleep(0.1)
proc.terminate()
proc.wait(timeout=10)
expect("oc routed R4 control: a 0700 runtime dir starts and serves",
       socket_up, "socket never appeared in the tight dir")
PYEOF
)" || rf_rc=$?
absorb_results "routed findings R3/R4" "$RF_OUT" "${rf_rc:-0}"

echo "== 6. routed finding: output-cap pump-and-kill (oc) =="
TASKS_BIN="$REPO_ROOT/shell/.local/bin/tasks"
R2_OUT="$(REPO_ROOT="$REPO_ROOT" ISOLATION_LIB="$LIB" ISOLATION_FIX="$REPO_FIX" TASKS_BIN="$TASKS_BIN" \
	python3 - <<'PYEOF'
import json
import os
import subprocess
import sys

LIB = os.environ["ISOLATION_LIB"]
FIX = os.environ["ISOLATION_FIX"]
TASKS_BIN = os.environ["TASKS_BIN"]
RUN = os.path.join(os.path.dirname(FIX), "r2-state")
os.makedirs(RUN, exist_ok=True)
os.chmod(RUN, 0o700)

# Seed a task whose report body is 48 MiB, directly in the fixture
# board (a body this size cannot ride the 1 MiB-bounded broker stdin).
subprocess.run([TASKS_BIN, "new", "--id", "ADV-2", "--name", "R2 Target"],
	           cwd=FIX, capture_output=True, check=True)
name = subprocess.run(
	["bash", "-c", f"cd '{FIX}' && find .tasks/current -name 'ADV-2-*.md' -printf '%f\\n' | head -1"],
	capture_output=True, text=True).stdout.strip()
assert name, "ADV-2 task file missing"
report_dir = os.path.join(FIX, ".tasks", "reports", name)
os.makedirs(report_dir, exist_ok=True)
with open(os.path.join(report_dir, "01-big.md"), "w") as fh:
	fh.write("secret: R2-BODY-MARKER-77ab\\n")
	block = "x" * (1024 * 1024) + "\\n"
	for _ in range(48):
		fh.write(block)

# The service hosts in an isolated driver process so the VmHWM read is
# the service's own memory, and its registry seeds directly (the same
# construction path the production guard uses at spawn).
DRIVER = r'''
import importlib.util, json, os, subprocess, sys, threading, time
LIB, RUN, FIX, NAME = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("svc_r2", os.path.join(LIB, "oc-task-service.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
def vmhwm():
	with open("/proc/self/status") as fh:
		for line in fh:
			if line.startswith("VmHWM:"):
				return int(line.split()[1])
	return 0
open(os.path.join(RUN, "token"), "w").write("tok-r2")
svc = mod.BrokerService(os.path.join(RUN, "broker.sock"), FIX, "tok-r2",
                        os.path.join(RUN, "service.log"))
svc.state["registry"].add(("adv-plan", "planner"))
threading.Thread(target=svc.serve_forever, kwargs={"poll_interval": 0.2},
                 daemon=True).start()
time.sleep(0.2)

def client(command):
	return subprocess.run(
		[sys.executable, os.path.join(LIB, "oc-broker-client.py"), "--registry", RUN,
		 "--session", "adv-plan", "--agent", "planner", "exec", command],
		capture_output=True, text=True, cwd=FIX, timeout=300)

before = vmhwm()
big = client("tasks reports " + NAME + " --include-body --json")
time.sleep(0.3)
after = vmhwm()
small = client("tasks show " + NAME + " --json")
print(json.dumps({
	"before_kb": before, "after_kb": after,
	"delta_mb": round((after - before) / 1024.0, 1),
	"big_rc": big.returncode,
	"big_err": big.stderr[-200:],
	"small_rc": small.returncode,
	"small_no_other_body": "Adversarial Target" not in small.stdout,
	"small_err": small.stderr[-200:],
}))
'''
driver_path = os.path.join(RUN, "r2-driver.py")
with open(driver_path, "w") as fh:
	fh.write(DRIVER)
out = subprocess.run([sys.executable, driver_path, LIB, RUN, FIX, name],
	                 capture_output=True, text=True, timeout=600)
assert out.stdout.strip(), f"driver produced no output: {out.stderr[-400:]}"
result = json.loads(out.stdout.strip().splitlines()[-1])


def expect(label, cond, detail=""):
	print(("ok " if cond else "bad ") + label + (f" [{detail}]" if detail and not cond else ""))


expect("oc routed R2: a 48MiB report pull is killed at the response cap",
       result["big_rc"] == 125 and "response cap" in result["big_err"],
       f"rc={result['big_rc']} err={result['big_err'][:160]!r}")
expect("oc routed R2: service memory stays bounded across the killed pull",
       result["delta_mb"] <= 24,
       f"VmHWM delta {result['delta_mb']}MB (red-at-base reference: ~144MB)")
expect("oc routed R2 control: small sanctioned pulls still round-trip",
       result["small_rc"] == 0, f"rc={result['small_rc']}")
expect("oc routed R2 control: the small pull carries no other task's body",
       result["small_no_other_body"],
       f"err={result['small_err'][:160]!r}")
PYEOF
)" || r2_rc=$?
absorb_results "routed finding R2 (output cap)" "$R2_OUT" "${r2_rc:-0}"

echo "== 7. recovery and concurrency (claims, lock, crashed child; pi column) =="
if [[ "$HAVE_BWRAP" == "1" ]]; then
RECOVERY_TASKS_BIN="$REPO_ROOT/shell/.local/bin"
RECOVERY_OUT="$(REPO_ROOT="$REPO_ROOT" ISOLATION_LIB="$LIB" ISOLATION_FIX="$REPO_FIX" \
	ISOLATION_WORKTREE="$WORKTREE_FIX" ISOLATION_TASKFILE="$TASKFILE_BASE" \
	ISOLATION_SOCKET="$SOCKET" ISOLATION_CLIENT="$CLIENT_PY" \
	ISOLATION_TWIN="$TWIN" \
	ISOLATION_AGENT_DIR="$AGENT_DIR" ISOLATION_TRUST="$TRUST_FILE" \
	TASKS_BIN_DIR="$RECOVERY_TASKS_BIN" \
	python3 - <<'PYEOF'
import hashlib
import os
import subprocess
import sys
import threading
import time

LIB = os.environ["ISOLATION_LIB"]
FIX = os.environ["ISOLATION_FIX"]
WORKTREE = os.environ["ISOLATION_WORKTREE"]
TWIN = os.environ["ISOLATION_TWIN"]
TASKS = os.path.join(os.environ["TASKS_BIN_DIR"], "tasks")
sys.path.insert(0, LIB)
import isolation_common as ic


def expect(label, cond, detail=""):
	print(("ok " if cond else "bad ") + label + (f" [{detail}]" if detail and not cond else ""))


def board_hash(root):
	out = subprocess.run(
		["bash", "-c",
		 f"cd '{root}' && find .tasks -type f -not -name '*.claim' -print0"
		 " | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1"],
		capture_output=True, text=True)
	return out.stdout.strip()


def board_snapshot(repo):
	# Entries carry their find %y type, so sockets and fifos that the
	# -type f hash walk never sees still count as residue.
	return subprocess.run(
		["bash", "-c",
		 f"cd '{repo}' && find .tasks -printf '%y %p\\n' | LC_ALL=C sort"],
		capture_output=True, text=True).stdout


RESIDUE_SNIPPET = (
	"mkdir -p .tasks/pi-residue-dir && "
	"python3 -c 'import socket; sock = socket.socket(socket.AF_UNIX); "
	"sock.bind(\".tasks/pi-residue.sock\")' && "
	"touch .tasks/pi-residue.lock .tasks/.lock.residue")


def tcli(*argv, session=None):
	env = dict(os.environ)
	if session:
		env["TASKS_SESSION"] = session
	return subprocess.run([TASKS, *argv], capture_output=True, text=True,
	                      cwd=FIX, env=env, timeout=120)


cli_env = {**os.environ,
           "PI_TASK_STORAGE_SOCKET": os.environ["ISOLATION_SOCKET"],
           "PI_TASK_STORAGE_TOKEN": "adv-suite-token",
           "TASKS_SESSION": "recovery-driver"}


def cli(*argv):
	return subprocess.run([sys.executable, os.environ["ISOLATION_CLIENT"], *argv],
	                      capture_output=True, text=True, cwd=FIX,
	                      env=cli_env, timeout=180)


init = tcli("init")
new = tcli("new", "--id", "ADV-11", "--name", "Pi Recovery Target")
entries = sorted(f for f in os.listdir(os.path.join(FIX, ".tasks", "current"))
                 if f.startswith("ADV-11-"))
expect("pi recovery: fixture board scaffolded (setup)",
       init.returncode == 0 and new.returncode == 0 and bool(entries),
       f"init rc={init.returncode} new rc={new.returncode} err={new.stderr[:160]!r}")
entry = entries[0]

label = "iso-channel-" + hashlib.sha256(b"adv-suite-token").hexdigest()[:16]
claim = tcli("claim", entry, "--owner", label)
expect("pi recovery: claim taken on the fixture board (setup)",
       claim.returncode == 0, f"rc={claim.returncode} err={claim.stderr[:160]!r}")
out = tcli("claims", "--json")
expect("pi recovery: claims sweep reports the live channel-owned claim",
       out.returncode == 0 and label in out.stdout, out.stdout[:200])
out = cli("tasks", "log", entry, "--from", "someone-else",
          "pi recovery heartbeat through the channel")
expect("pi recovery: sanctioned channel log lands as the channel-owned claim heartbeat",
       out.returncode == 0,
       f"rc={out.returncode} out={out.stdout[:160]!r} err={out.stderr[:160]!r}")
out = cli("tasks", "show", entry, "--json")
expect("pi recovery: the heartbeat entry carries the channel attribution",
       out.returncode == 0 and "pi recovery heartbeat" in out.stdout
       and "iso-channel-" in out.stdout, out.stdout[-200:])

new2 = tcli("new", "--id", "ADV-12", "--name", "Recovery Foreign")
entries2 = sorted(f for f in os.listdir(os.path.join(FIX, ".tasks", "current"))
                  if f.startswith("ADV-12-"))
expect("pi recovery: foreign-claim task scaffolded (setup)",
       new2.returncode == 0 and bool(entries2),
       f"new rc={new2.returncode} err={new2.stderr[:160]!r}")
entry2 = entries2[0]
claim2 = tcli("claim", entry2, "--owner", "manager-main")
expect("pi recovery: foreign claim taken (setup)", claim2.returncode == 0,
       f"rc={claim2.returncode} err={claim2.stderr[:160]!r}")
out = tcli("release", entry2, session="intruder")
expect("pi recovery: a foreign session cannot release a live claim it does not own (fail closed)",
       out.returncode != 0 and "claimed by" in out.stderr,
       f"rc={out.returncode} out={out.stdout[:160]!r} err={out.stderr[:160]!r}")
out = cli("tasks", "log", entry2, "--from", label,
          "pi recovery foreign-claim write")
expect("pi recovery: the live foreign claim does not gate the sanctioned log, write lands channel-attributed",
       out.returncode == 0, f"rc={out.returncode} err={out.stderr[:160]!r}")
out = cli("tasks", "show", entry2, "--json")
expect("pi recovery: the foreign-claimed entry carries the channel-attributed write",
       out.returncode == 0 and "foreign-claim write" in out.stdout
       and "iso-channel-" in out.stdout, out.stdout[-200:])

results = {}


def log_thread(index):
	results[index] = cli("tasks", "log", entry, "--from", label,
	                     f"pi concurrent write {index}")


threads = [threading.Thread(target=log_thread, args=(i,)) for i in range(2)]
for thread in threads:
	thread.start()
for thread in threads:
	thread.join(180)
expect("pi recovery: two concurrent sanctioned writes both land under the board lock",
       results[0].returncode == 0 and results[1].returncode == 0,
       f"rc0={results[0].returncode} rc1={results[1].returncode} "
       f"e0={results[0].stderr[:120]!r} e1={results[1].stderr[:120]!r}")
out = cli("tasks", "show", entry, "--json")
expect("pi recovery: both concurrent entries present in the Work Log",
       out.returncode == 0 and "pi concurrent write 0" in out.stdout
       and "pi concurrent write 1" in out.stdout, out.stdout[-200:])

twin_snap_before = board_snapshot(TWIN)
plant = subprocess.run(["bash", "-c",
                        RESIDUE_SNIPPET + " && "
                        "test -S .tasks/pi-residue.sock -a -d .tasks/pi-residue-dir "
                        "-a -f .tasks/pi-residue.lock -a -f .tasks/.lock.residue"],
                       capture_output=True, text=True, cwd=TWIN, timeout=60)
expect("pi recovery twin: the residue payload plants sockets, temp dirs, and lock files without enforcement (setup)",
       plant.returncode == 0, f"rc={plant.returncode} err={plant.stderr[:200]!r}")
twin_snap_planted = board_snapshot(TWIN)
expect("pi recovery twin: the board snapshot detector sees the planted residue (detector validation)",
       all(name in twin_snap_planted for name in
           ("pi-residue-dir", "pi-residue.sock", "pi-residue.lock", ".lock.residue"))
       and twin_snap_planted != twin_snap_before, twin_snap_planted[-300:])
cleanup = subprocess.run(["bash", "-c",
                          "rm -rf .tasks/pi-residue-dir .tasks/pi-residue.sock "
                          ".tasks/pi-residue.lock .tasks/.lock.residue"],
                         capture_output=True, text=True, cwd=TWIN, timeout=60)
expect("pi recovery twin: the twin board snapshot is restored after cleanup (detector validation)",
       cleanup.returncode == 0 and board_snapshot(TWIN) == twin_snap_before)

hash_before = board_hash(FIX)
snap_before_fix = board_snapshot(FIX)
snap_before_wt = board_snapshot(WORKTREE)
claims_before = tcli("claims", "--json").stdout
wrapped_env = dict(os.environ)
wrapped_env.update({
	"PI_TASK_STORAGE_ISOLATION": "1",
	"PI_TASK_STORAGE_MASK_PATHS": "\n".join([
		os.path.realpath(os.path.join(FIX, ".tasks")),
		os.path.realpath(os.path.join(WORKTREE, ".tasks")),
	]),
	"PI_TASK_STORAGE_SOCKET": os.environ["ISOLATION_SOCKET"],
	"PI_TASK_STORAGE_TOKEN": "adv-suite-token",
	"PI_TASK_STORAGE_TRUST_FILE": os.environ["ISOLATION_TRUST"],
})
argv = ic.build_isolation_argv("/bin/bash",
                               ["-c", RESIDUE_SNIPPET + " && "
                                "echo RESIDUE >> .tasks/dashboard.md; "
                                "touch /tmp/pi-residue-canary; sleep 60"],
                               wrapped_env,
                               agent_dir=os.environ["ISOLATION_AGENT_DIR"])
child = subprocess.Popen(argv, cwd=WORKTREE, env=wrapped_env,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2)
if child.poll() is None:
	child.terminate()
	try:
		child.wait(timeout=30)
	except subprocess.TimeoutExpired:
		child.kill()
		child.wait()
else:
	child.wait()
expect("pi recovery: no namespace /tmp canary reached the host tmpfs",
       not os.path.exists("/tmp/pi-residue-canary"))
out = cli("tasks", "show", entry, "--json")
expect("pi recovery: the service keeps serving sanctioned calls after a wrapped child was killed",
       out.returncode == 0, f"rc={out.returncode} err={out.stderr[:160]!r}")
expect("pi recovery: the killed wrapped child left the fixture board byte-identical",
       board_hash(FIX) == hash_before)
snap_after_fix = board_snapshot(FIX)
snap_after_wt = board_snapshot(WORKTREE)
expect("pi recovery: the killed wrapped child left no board residue (no sockets, temp dirs, or lock files)",
       snap_after_fix == snap_before_fix and snap_after_wt == snap_before_wt,
       f"diff={sorted(set(snap_after_fix.splitlines()) ^ set(snap_before_fix.splitlines()))[:6]}")
claims_state = tcli("claims", "--json").stdout
expect("pi recovery: the killed wrapped child left no claim residue",
       claims_state == claims_before, claims_state[:200])
PYEOF
)" || RECOVERY_RC=$?
absorb_results "pi recovery and concurrency column" "$RECOVERY_OUT" "${RECOVERY_RC:-0}"
else
	for section in "claims" "concurrent writes" "crashed wrapped child"; do
		skip_test "pi recovery: $section (bwrap not installed; degraded mode)"
	done
fi

print_result
if ((fail > 0)); then
	exit 1
fi
exit 0
