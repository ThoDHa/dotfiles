#!/usr/bin/env bash
#
# Enforcement suite for raw task-storage isolation (ORCH-4-10-2).
#
# Verifies the pi enforcement surface end to end without an LLM and
# without touching the live host install:
#
#   0. tool gates and lint gates (py_compile, shellcheck, node parse)
#   1. constant cross-checks so the TS wrap, the python mirror, the
#      patcher, and the service cannot drift their contract names
#   2. wrap-patcher units on a fixture vendored extension
#   3. hermetic fixtures: agent dir, board repo, sibling worktree,
#      seeded parent transcript
#   4. driver sections (node): guard normalization units including the
#      symlink-then-dotdot divergence class, installed wrap block
#      parity against the suite builder, extension factory behavior
#      including digest-based drift refusal and a hosted-service round
#      trip
#   5. machine-side bwrap probes running exactly the argv the builder
#      produces (parity-pinned to the installed wrap): direct, symlink,
#      realpath, and sibling-worktree read denials; the one-namespace
#      masked round trip; the write round trip driving log and report
#      bodies through the production client; the transcript-leak pair
#      (leak demonstrated under the pre-fix shape, closed under the
#      production shape); credential and trust provisioning
#   6. escape-channel service units: socket-visibility gate, sanctioned
#      read and write verbs, path-policy and stdin-only-body refusals,
#      service-bound write attribution, the slow-send read window,
#      token/session/verb/--dir/oversize refusals, parent-death
#      watchdog
#
# Deny evidence here is machine-side and deterministic; an LLM child
# run is composition-only evidence (the walking skeleton covers that
# path; ORCH-4-10-4 owns the full adversarial suite).
#
# Degradation contract: with ISOLATION_ALLOW_DEGRADED=1 (set by the
# container verify chain, which lacks bwrap, node, and shellcheck)
# the tool-dependent gates and sections are announced as skipped and
# the suite gates on what ran; without the flag a missing tool fails
# the suite loudly. Enforced labels are decided by full-mode host
# runs only.
#
# Exit contract: non-zero unless every check passes; on failure the
# scratch directory is kept and its path printed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_DIR="$REPO_ROOT/tests/task-storage-isolation"
LIB="$SUITE_DIR/lib"
RUN="$(mktemp -d /tmp/isolation-suite.XXXXXX)"
SERVICE_PID=""
status=0

# The EXIT handler is inline as a workaround: the natural form is a
# named cleanup() referenced by the trap, but shellcheck 0.11.0
# cannot model functions invoked via trap (SC2329, the handler is
# flagged as never called) and cannot track assignments inside trap
# strings, so the body is inlined and status is pre-initialized and
# reassigned at fire time. A shellcheck release that models
# trap-invoked functions makes this restructure revertible to the
# named-function form.
trap '{
	status=$?
	if [[ -n "$SERVICE_PID" ]]; then
		kill "$SERVICE_PID" 2>/dev/null || true
	fi
	if [[ "$status" -eq 0 ]]; then
		rm -rf "$RUN"
	else
		echo "isolation suite artifacts kept for inspection: $RUN"
	fi
}' EXIT

fail_fast() {
	echo "SUITE-FAIL: $*" >&2
	exit 1
}

# shellcheck source=/dev/null
source "$REPO_ROOT/tests/lib/harness.sh"
# The counters are initialized by the harness at source time; they are
# re-declared here so static analysis sees the assignment without
# following the sourced file (the harness helpers that consume them
# are invisible to shellcheck, hence the targeted directive).
# shellcheck disable=SC2034
pass=0
fail=0
# shellcheck disable=SC2034
skip=0

# Feed one runner's "ok <name>" / "bad <name>" result lines into the
# suite counters and gate on the runner's own exit status.
absorb_results() { # <label> <output> <rc>
	local label="$1" output="$2" rc="$3"
	local line
	while IFS= read -r line; do
		case "$line" in
			"ok "*) ok "${line#"ok "}";;
			"bad "*) bad "${line#"bad "}";;
			*) printf '    runner: %s\n' "$line" ;;
		esac
	done <<<"$output"
	if [[ "$rc" -ne 0 ]]; then
		bad "$label (runner exited $rc)"
	fi
}

DEGRADED="${ISOLATION_ALLOW_DEGRADED:-0}"

# The suite imports the repo-source wrap and service modules (digest
# derivation, in-process service units); importlib writes __pycache__
# beside those sources, and the pi-extensions deploy-completeness gate
# then fails on the untracked litter. py_compile below stays on its own
# external cache prefix because an explicit compile ignores this flag.
export PYTHONDONTWRITEBYTECODE=1

command -v python3 >/dev/null || fail_fast "python3 not installed"
command -v tasks >/dev/null || fail_fast "tasks CLI not on PATH"
HAVE_NODE=0
command -v node >/dev/null && HAVE_NODE=1
HAVE_BWRAP=0
command -v bwrap >/dev/null && HAVE_BWRAP=1
HAVE_SHELLCHECK=0
command -v shellcheck >/dev/null && HAVE_SHELLCHECK=1
if [[ "$DEGRADED" != "1" ]]; then
	[[ "$HAVE_NODE" == "1" ]] || fail_fast "node not installed"
	[[ "$HAVE_BWRAP" == "1" ]] || fail_fast "bwrap not installed (machine probes cannot run)"
	[[ "$HAVE_SHELLCHECK" == "1" ]] || fail_fast "shellcheck not installed"
fi

WRAP_PY="$REPO_ROOT/pi/extensions/task-storage-isolation-wrap.py"
SERVICE_PY="$REPO_ROOT/pi/extensions/task-storage-isolation-service.py"
CLIENT_PY="$REPO_ROOT/pi/extensions/task-storage-isolation-client.py"
GUARD_TS="$REPO_ROOT/pi/extensions/task-storage-isolation.ts"
DRIVER="$LIB/ts-driver.mjs"
COMMON="$LIB/isolation_common.py"
EXT_COPY="$RUN/patcher/agent/extensions/subagent/index.ts"
FIX="$RUN/fixtures"
AGENT_DIR="$FIX/agent"
REPO="$FIX/repo"
WORKTREE="$FIX/worktree"
DRIVER_DIR="$RUN/driver"
ACTIVATED_COPY="$RUN/driver-extension/vendored-activated.ts"
ESCAPE_DIR="$RUN/escape"
SOCKET="$ESCAPE_DIR/service.sock"
TRUST_FILE="$ESCAPE_DIR/trust.json"
SERVICE_LOG="$ESCAPE_DIR/service.log"
TASKFILE_BASE=""

echo "== 0. tool and lint gates =="
if PYTHONPYCACHEPREFIX="$RUN/pycache" python3 -m py_compile "$WRAP_PY" "$SERVICE_PY" "$CLIENT_PY" "$COMMON"; then
	ok "py_compile clean on all enforcement python"
else
	bad "py_compile clean on all enforcement python"
fi
if [[ "$HAVE_SHELLCHECK" == "1" ]]; then
	if shellcheck "$SUITE_DIR/run-suite.sh"; then
		ok "shellcheck clean on run-suite.sh"
	else
		bad "shellcheck clean on run-suite.sh"
	fi
else
	skip_test "shellcheck clean on run-suite.sh (shellcheck not installed; degraded mode)"
fi
if [[ "$HAVE_NODE" == "1" ]]; then
	if node --check "$DRIVER"; then
		ok "node parses ts-driver.mjs"
	else
		bad "node parses ts-driver.mjs"
	fi
else
	skip_test "node parses ts-driver.mjs (node not installed; degraded mode)"
fi

echo "== 1. constant cross-checks (anti-drift) =="
for constant in PI_TASK_STORAGE_ISOLATION PI_TASK_STORAGE_MASK_PATHS \
	PI_TASK_STORAGE_SOCKET PI_TASK_STORAGE_TRUST_FILE \
	PI_TASK_STORAGE_AGENT_DIR PI_TASK_STORAGE_UNMASKED; do
	if grep -qF "$constant" "$WRAP_PY" && grep -qF "$constant" "$COMMON" \
		&& grep -qF "$constant" "$GUARD_TS"; then
		ok "contract constant $constant named in wrap, builder, and extension"
	else
		bad "contract constant $constant named in wrap, builder, and extension"
	fi
done
# The token is deliberately not consumed by the wrap (it rides the
# inherited environment; the service enforces it), so its contract
# spans the builder, the extension, and the client.
if grep -qF "PI_TASK_STORAGE_TOKEN" "$COMMON" && grep -qF "PI_TASK_STORAGE_TOKEN" "$GUARD_TS" \
	&& grep -qF "PI_TASK_STORAGE_TOKEN" "$CLIENT_PY"; then
	ok "contract constant PI_TASK_STORAGE_TOKEN named in builder, extension, and client"
else
	bad "contract constant PI_TASK_STORAGE_TOKEN named in builder, extension, and client"
fi
if grep -qF "TASK-STORAGE-ISOLATION WRAP BEGIN" "$WRAP_PY" \
	&& grep -qF 'WRAP_MARKER = "TASK-STORAGE-ISOLATION WRAP BEGIN"' "$GUARD_TS"; then
	ok "wrap marker identical in patcher and drift checker"
else
	bad "wrap marker identical in patcher and drift checker"
fi
if grep -qF '"show", "list", "reports", "log", "report"' "$SERVICE_PY"; then
	ok "service whitelists exactly the sanctioned verb set"
else
	bad "service whitelists exactly the sanctioned verb set"
fi
WRAP_BLOCK_DIGEST_EXPECTED="$(python3 - "$WRAP_PY" <<'PYEOF'
import hashlib, importlib.util, sys
spec = importlib.util.spec_from_file_location("wrap_under_test", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(hashlib.sha256(module.WRAP_BLOCK[:-1].encode()).hexdigest())
PYEOF
)"
if grep -qF "$WRAP_BLOCK_DIGEST_EXPECTED" "$GUARD_TS"; then
	ok "wrap block content digest identical in patcher (derived) and drift checker (pinned)"
else
	bad "wrap block content digest identical in patcher (derived) and drift checker (pinned)"
fi
if grep -qF "PI_TASK_STORAGE_SOCKET" "$CLIENT_PY" \
	&& grep -qF "PI_TASK_STORAGE_TOKEN" "$CLIENT_PY" \
	&& grep -qF "TASKS_SESSION" "$CLIENT_PY"; then
	ok "client consumes socket, token, and session from the child environment"
else
	bad "client consumes socket, token, and session from the child environment"
fi

echo "== 2. wrap-patcher units =="
python3 -c "
import sys
sys.path.insert(0, '$LIB')
from isolation_common import make_fixture_vendored_extension
make_fixture_vendored_extension('$EXT_COPY')
" || fail_fast "fixture vendored extension could not be created"
pristine_copy="$RUN/patcher/pristine.ts"
cp "$EXT_COPY" "$pristine_copy"

patcher_out="$(python3 "$WRAP_PY" verify "$RUN/patcher/agent" 2>&1)"
verify_rc=$?
if [[ $verify_rc -eq 0 ]]; then
	ok "verify reports pristine (exit 0)"
else
	bad "verify reports pristine (exit 0): $patcher_out"
fi

patcher_out="$(python3 "$WRAP_PY" activate "$RUN/patcher/agent" 2>&1)"
activate_rc=$?
if [[ $activate_rc -eq 0 ]] && grep -qF "TASK-STORAGE-ISOLATION WRAP BEGIN" "$EXT_COPY"; then
	ok "activate installs the wrap block"
else
	bad "activate installs the wrap block: rc=$activate_rc $patcher_out"
fi

patcher_out="$(python3 "$WRAP_PY" activate "$RUN/patcher/agent" 2>&1)"
reactivate_rc=$?
count_begin="$(grep -cF "TASK-STORAGE-ISOLATION WRAP BEGIN" "$EXT_COPY")"
if [[ $reactivate_rc -eq 0 && "$count_begin" -eq 1 ]]; then
	ok "re-activate is idempotent (single block)"
else
	bad "re-activate is idempotent (single block): rc=$reactivate_rc blocks=$count_begin"
fi

patcher_out="$(python3 "$WRAP_PY" verify "$RUN/patcher/agent" 2>&1)"
verify_rc=$?
if [[ $verify_rc -eq 0 ]]; then
	ok "verify reports activated and intact"
else
	bad "verify reports activated and intact: $patcher_out"
fi
# Stable activated reference for the driver sections (section 2 leaves
# the working copy deactivated again below).
cp "$EXT_COPY" "$RUN/patcher/activated.ts"

# S-drift: in-block content drift with the markers kept must fail
# verify, refuse activate, and leave the file untouched; deactivate
# still restores the pristine bytes (the recovery path stays open).
sed -i 's/"--die-with-parent",/"--die-with-parent-drifted",/' "$EXT_COPY"
cp "$EXT_COPY" "$RUN/patcher/inblock-drifted.ts"
patcher_out="$(python3 "$WRAP_PY" verify "$RUN/patcher/agent" 2>&1)"
inblock_verify_rc=$?
if [[ $inblock_verify_rc -ne 0 ]] && grep -q "drifted" <<<"$patcher_out"; then
	ok "verify fails on in-block drift keeping markers intact"
else
	bad "verify fails on in-block drift keeping markers intact: rc=$inblock_verify_rc $patcher_out"
fi
patcher_out="$(python3 "$WRAP_PY" activate "$RUN/patcher/agent" 2>&1)"
inblock_activate_rc=$?
if [[ $inblock_activate_rc -ne 0 ]] && cmp -s "$RUN/patcher/inblock-drifted.ts" "$EXT_COPY"; then
	ok "activate refuses on in-block drift and leaves the file untouched"
else
	bad "activate refuses on in-block drift and leaves the file untouched: rc=$inblock_activate_rc"
fi
cp "$RUN/patcher/inblock-drifted.ts" "$EXT_COPY"
python3 "$WRAP_PY" deactivate "$RUN/patcher/agent" >/dev/null 2>&1
inblock_deactivate_rc=$?
if [[ $inblock_deactivate_rc -eq 0 ]] && cmp -s "$pristine_copy" "$EXT_COPY"; then
	ok "deactivate still restores pristine bytes through an in-block drift"
else
	bad "deactivate still restores pristine bytes through an in-block drift: rc=$inblock_deactivate_rc"
fi
cp "$RUN/patcher/activated.ts" "$EXT_COPY"

sed -i 's/return { command: "pi", args };/return { command: "pi-drifted", args };/' "$EXT_COPY"
cp "$EXT_COPY" "$RUN/patcher/drifted.ts"
patcher_out="$(python3 "$WRAP_PY" activate "$RUN/patcher/agent" 2>&1)"
drift_rc=$?
if [[ $drift_rc -ne 0 ]] && cmp -s "$RUN/patcher/drifted.ts" "$EXT_COPY"; then
	ok "activate refuses on seam drift and leaves the file untouched"
else
	bad "activate refuses on seam drift and leaves the file untouched: rc=$drift_rc"
fi
cp "$pristine_copy" "$EXT_COPY"
python3 "$WRAP_PY" activate "$RUN/patcher/agent" >/dev/null 2>&1 || fail_fast "re-activate after drift-restore failed"

patcher_out="$(python3 "$WRAP_PY" deactivate "$RUN/patcher/agent" 2>&1)"
deactivate_rc=$?
if [[ $deactivate_rc -eq 0 ]] && cmp -s "$pristine_copy" "$EXT_COPY"; then
	ok "deactivate restores the vendored file byte-identically (no data loss)"
else
	bad "deactivate restores the vendored file byte-identically (no data loss): rc=$deactivate_rc"
fi
patcher_out="$(python3 "$WRAP_PY" deactivate "$RUN/patcher/agent" 2>&1)"
noop_rc=$?
if [[ $noop_rc -eq 0 ]]; then
	ok "deactivate on a pristine file is a no-op"
else
	bad "deactivate on a pristine file is a no-op: $patcher_out"
fi

echo "== 3. hermetic fixtures =="
mkdir -p "$DRIVER_DIR" "$ESCAPE_DIR"
chmod 700 "$ESCAPE_DIR"
python3 - "$FIX" "$LIB" <<'EOF' || fail_fast "fixture build failed"
import os
import sys

fix, lib = sys.argv[1], sys.argv[2]
sys.path.insert(0, lib)
import isolation_common as ic

os.makedirs(fix, exist_ok=True)
agent_dir, _markers = ic.make_fixture_agent_dir(fix)
repo, secret_marker = ic.make_fixture_repo(fix)
worktree, _sibling = ic.add_fixture_worktree(repo, os.path.join(fix, "worktree"))
# The seeded parent transcript carries board content: the exact leak
# lane the transcript-leak probe demonstrates and the production wrap
# closes.
ic.seed_transcript(agent_dir, "--fixture-cwd--", secret_marker)
print(agent_dir)
EOF
if [[ ! -d "$AGENT_DIR/sessions" || ! -d "$REPO/.tasks" || ! -d "$WORKTREE/.tasks" ]]; then
	fail_fast "fixtures incomplete"
fi

export TASKS_SESSION=isolation-suite
(cd "$REPO" && tasks init >/dev/null) || fail_fast "tasks init failed on fixture"
(cd "$REPO" && tasks new --id ISO-1 --name "Isolation Suite Target" >/dev/null) || fail_fast "tasks new failed on fixture"
TASKFILE_BASE="$(cd "$REPO" && find .tasks/current -maxdepth 1 -name 'ISO-1-*.md' -printf '%f\n' | head -1)"
if [[ -n "$TASKFILE_BASE" ]]; then
	ok "fixture board ready (task file $TASKFILE_BASE)"
else
	fail_fast "fixture task file was not created"
fi

SUITE_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

echo "== 4. escape-channel service (shared instance) =="
printf '{}\n' >"$TRUST_FILE"
PI_TASK_STORAGE_TOKEN="$SUITE_TOKEN" python3 "$SERVICE_PY" "$SOCKET" "$REPO" "$SERVICE_LOG" &
SERVICE_PID=$!
for _ in $(seq 1 50); do
	if [[ -S "$SOCKET" ]]; then
		break
	fi
	sleep 0.1
done
if [[ -S "$SOCKET" ]]; then
	ok "service listening on the 0700 escape dir"
else
	fail_fast "service socket never appeared"
fi

echo "== 5. driver sections (guard units, wrap parity, extension factory) =="
mkdir -p "$RUN/driver-extension"
cp "$RUN/patcher/activated.ts" "$RUN/driver-extension/vendored-activated.ts"
mkdir -p "$RUN/xdg-data/opencode/storage/session/default"
printf '{"content":"parity transcript seed"}\n' > "$RUN/xdg-data/opencode/storage/session/default/transcript.jsonl"
parity_out="$(python3 - "$REPO" "$LIB" "$RUN/parity-expected.json" "$SOCKET" "$TRUST_FILE" "$AGENT_DIR" "$RUN/xdg-data" <<'PYEOF'
import json
import os
import sys

repo, lib, out, socket, trust, agent_dir, xdg_data_home = sys.argv[1:8]
sys.path.insert(0, lib)
import isolation_common as ic

tasks_main = os.path.join(os.path.realpath(repo), ".tasks")
tasks_sibling = os.path.join(os.path.realpath(os.path.join(repo, "..", "worktree")), ".tasks")
env = {
	"PI_TASK_STORAGE_ISOLATION": "1",
	"PI_TASK_STORAGE_MASK_PATHS": "\n".join([tasks_main, tasks_sibling]),
	"PI_TASK_STORAGE_SOCKET": socket,
	"PI_TASK_STORAGE_TRUST_FILE": trust,
	"PI_TASK_STORAGE_AGENT_DIR": agent_dir,
	"XDG_DATA_HOME": xdg_data_home,
}
argv = ic.build_isolation_argv("node", ["child.js"], env, agent_dir=agent_dir)
payload = {
	"command": argv[0],
	"argv": argv[1:],
	"mask_paths": [tasks_main, tasks_sibling],
	"socket": socket,
	"trust": trust,
	"agent_dir": agent_dir,
	"xdg_data_home": xdg_data_home,
}
with open(out, "w") as handle:
	json.dump(payload, handle)
print("parity feed written")
PYEOF
)"
parity_rc=$?
if [[ $parity_rc -ne 0 ]]; then
	fail_fast "parity feed failed (rc=$parity_rc): $parity_out"
fi

if [[ "$HAVE_NODE" == "1" ]]; then
	driver_out="$(node "$DRIVER" guard "$REPO_ROOT" "$RUN/driver-guard" 2>&1)"
	absorb_results "ts-driver guard section" "$driver_out" $?

	driver_out="$(node "$DRIVER" wrap "$REPO_ROOT" "$RUN/driver-wrap" "$ACTIVATED_COPY" "$RUN/parity-expected.json" 2>&1)"
	absorb_results "ts-driver wrap section (parity)" "$driver_out" $?

	driver_out="$(node "$DRIVER" extension "$REPO_ROOT" "$RUN/driver-extension" "$REPO" "$TASKFILE_BASE" 2>&1)"
	absorb_results "ts-driver extension section (hosting round trip)" "$driver_out" $?
else
	skip_test "ts-driver guard, wrap-parity, and extension sections (node not installed; degraded mode)"
fi

echo "== 6. machine-side bwrap probes (builder argv, parity-pinned) =="
if [[ "$HAVE_BWRAP" != "1" ]]; then
	skip_test "machine-side bwrap probes (bwrap not installed; degraded mode)"
fi
if [[ "$HAVE_BWRAP" == "1" ]]; then
export PI_TASK_STORAGE_ISOLATION="1"
MASK_LIST="$(python3 -c "import os; print('\n'.join([os.path.realpath('$REPO/.tasks'), os.path.realpath('$WORKTREE/.tasks')]))")"
export PI_TASK_STORAGE_MASK_PATHS="$MASK_LIST"
export PI_TASK_STORAGE_SOCKET="$SOCKET"
export PI_TASK_STORAGE_TRUST_FILE="$TRUST_FILE"
export PI_TASK_STORAGE_AGENT_DIR="$AGENT_DIR"
export PI_TASK_STORAGE_TOKEN="$SUITE_TOKEN"
export TASKS_SESSION="masked-child"
SECRET_MARKER="$(grep -oE 'SUITE-SECRET-[a-z0-9-]+' "$REPO/.tasks/current/secret.md")"
TRANSCRIPT="$AGENT_DIR/sessions/--fixture-cwd--/2026-11-17T00-00-00-seeded.jsonl"

run_machine_probe() { # <shape production|leak> <payload-shell-text> -> JSON result on stdout
	local shape="$1" payload="$2"
	ISOLATION_LIB="$LIB" python3 - "$shape" "$payload" <<'PYEOF'
import json
import os
import subprocess
import sys

shape, payload = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

command = ["/bin/sh", "-c", payload]
if shape == "leak":
	argv = ic.build_isolation_argv(command[0], command[1:], dict(os.environ), include_agent_dir_sessions=True)
else:
	argv = ic.build_isolation_argv(command[0], command[1:], dict(os.environ))
completed = subprocess.run(argv, capture_output=True, text=True, timeout=120)
print(json.dumps({"rc": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}))
PYEOF
}

verify_probe() { # <name> <assert-script...> ; runs python - "$probe_json" with extra args
	local name="$1"
	shift
	local probe_json="$1"
	shift
	local verdict
	verdict="$(python3 - "$probe_json" "$@" 2>&1)"
	verdict_rc=$?
	if [[ $verdict_rc -eq 0 ]]; then
		ok "$name"
	else
		bad "$name: ${verdict:0:300}"
	fi
}

probe_json="$(run_machine_probe production "cat '$REPO/.tasks/current/secret.md'")"
verify_probe "machine deny: direct read of the masked tree is denied (ENOENT, no marker)" "$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
marker = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert result["rc"] != 0, f"direct read succeeded: {combined}"
assert "No such file or directory" in combined, f"no ENOENT denial text: {combined}"
assert marker not in combined, "SECRET MARKER LEAKED through direct read"
PYEOF

probe_json="$(run_machine_probe production "cat '$REPO/link-rel'; cat '$REPO/link-abs'; cat '$REPO/sub/deeper/link-updown'")"
verify_probe "machine deny: relative, absolute, and parent-traversal symlinks all denied" "$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
marker = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert result["rc"] != 0, f"symlink reads succeeded: {combined}"
assert combined.count("No such file or directory") == 3, f"expected three denials: {combined}"
assert marker not in combined, "SECRET MARKER LEAKED through symlink class"
PYEOF

probe_json="$(run_machine_probe production "python3 -c \"import os; p='$REPO/link-rel'; print(os.path.realpath(p)); open(p).read()\"")"
verify_probe "machine deny: realpath-normalized open resolves into the empty mask and is denied" "$probe_json" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
combined = result["stdout"] + result["stderr"]
assert result["rc"] != 0, f"realpath open succeeded: {combined}"
assert "FileNotFoundError" in combined or "No such file" in combined, f"no denial text: {combined}"
PYEOF

probe_json="$(run_machine_probe production "cat '$WORKTREE/.tasks/current/sibling.md'")"
verify_probe "machine deny: sibling worktree .tasks denied (multi-root mask)" "$probe_json" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
combined = result["stdout"] + result["stderr"]
assert result["rc"] != 0, f"sibling worktree read succeeded: {combined}"
assert "SIBLING-SECRET" not in combined, "SIBLING SECRET LEAKED"
PYEOF

echo "-- masked round trip in one namespace (composition integration) --"
round_trip_payload="cat '$REPO/.tasks/current/secret.md'
python3 '$CLIENT_PY' tasks show '$TASKFILE_BASE' --json
echo SHOW-EXIT=\$?
python3 - <<'UNLINK-PROBE'
import os
try:
    os.unlink('$SOCKET')
    print('UNLINK-SUCCEEDED')
except OSError as err:
    print('UNLINK-REFUSED', err)
UNLINK-PROBE
python3 '$CLIENT_PY' tasks show '$TASKFILE_BASE' --project"
probe_json="$(run_machine_probe production "$round_trip_payload")"
verify_probe "masked round trip: direct read denied, sanctioned verb passes, socket unlink refused, service survives" "$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
marker = sys.argv[2]
out = result["stdout"]
assert result["rc"] == 0, f"namespace run failed: rc={result['rc']} {result['stderr'][:400]}"
combined = result["stdout"] + result["stderr"]
assert marker not in combined and "No such file or directory" in combined, "direct read not denied inside the round-trip run"
assert "schema_version" in result["stdout"], f"sanctioned show did not round-trip: {result['stdout'][:400]}"
assert "Isolation Suite Target" in result["stdout"], f"board title missing from round-trip output: {result['stdout'][:400]}"
assert "SHOW-EXIT=0" in result["stdout"], f"client exit was not zero: {result['stdout'][:400]}"
lower = combined.lower()
assert "UNLINK-REFUSED" in result["stdout"], f"unlink attempt did not fail: {result['stdout'][-400:]}"
assert "busy" in lower or "read-only" in lower or "ero" in lower, f"unlink failure was not a mount-level refusal: {result['stdout'][-400:]}"
assert "UNLINK-SUCCEEDED" not in result["stdout"], "child unlinked the socket file"
PYEOF

echo "-- F2: write verbs through the production client (masked round trip) --"
# The role-contract stdin shapes must work end to end through the
# production client: a piped log checkpoint and a piped report body
# (both the no-marker role shape and the explicit '-' shape), then the
# deposits read back through the channel.
f2_payload="cat '$REPO/.tasks/current/secret.md'
printf 'fix-round channel checkpoint body PROVEMARK-F2L\\n' | python3 '$CLIENT_PY' tasks log '$TASKFILE_BASE' --from masked-child 'fix-round channel checkpoint'
echo LOG-EXIT=\$?
printf 'Fix-round report body PROVEMARK-F2R.\\n' | python3 '$CLIENT_PY' tasks report '$TASKFILE_BASE' --slug fix-round --from masked-child --digest 'fix-round channel deposit'
echo REPORT-EXIT=\$?
printf 'Explicit stdin shape body PROVEMARK-F2D.\\n' | python3 '$CLIENT_PY' tasks report '$TASKFILE_BASE' --slug fix-round-stdin --from masked-child --digest 'explicit stdin shape' -
echo REPORT-DASH-EXIT=\$?
python3 '$CLIENT_PY' tasks show '$TASKFILE_BASE' --tail 8 | grep -a 'fix-round channel checkpoint'
echo SHOWTAIL-EXIT=\$?
python3 '$CLIENT_PY' tasks reports '$TASKFILE_BASE' --include-body --json"
probe_json="$(run_machine_probe production "$f2_payload")"
verify_probe "F2 masked round trip: log and report bodies ride client stdin end to end" "$probe_json" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
out = result["stdout"]
assert result["rc"] == 0, f"namespace run failed: rc={result['rc']} {result['stderr'][:400]}"
assert "LOG-EXIT=0" in out, f"channel log failed: {out[-600:]}"
assert "REPORT-EXIT=0" in out, f"channel report (role stdin shape) failed: {out[-600:]}"
assert "REPORT-DASH-EXIT=0" in out, f"channel report (marker shape) failed: {out[-600:]}"
assert "fix-round channel checkpoint" in out, f"log deposit not readable back: {out[-600:]}"
assert "SHOWTAIL-EXIT=0" in out, f"show tail failed: {out[-600:]}"
assert "PROVEMARK-F2R" in out, f"role-shape report body not deposited: {out[-800:]}"
assert "PROVEMARK-F2D" in out, f"marker-shape report body not deposited: {out[-800:]}"
PYEOF

echo "-- transcript-leak pair (decision-log falsifiable test) --"
probe_json="$(run_machine_probe leak "cat '$TRANSCRIPT'")"
verify_probe "leak demonstrated: the pre-fix wrap exposes the parent transcript carrying board content" "$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
marker = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert result["rc"] == 0, f"pre-fix shape could not read the transcript: {combined[:300]}"
assert marker in combined, "pre-fix shape read the transcript but the marker was absent"
PYEOF

probe_json="$(run_machine_probe production "cat '$TRANSCRIPT'; ls '$AGENT_DIR/sessions'")"
verify_probe "leak closed: the production wrap hides the parent transcript store entirely" "$probe_json" "$SECRET_MARKER" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
marker = sys.argv[2]
combined = result["stdout"] + result["stderr"]
assert result["rc"] != 0, f"production shape read the transcript: {combined[:300]}"
assert marker not in combined, "TRANSCRIPT MARKER LEAKED under the production shape"
PYEOF

probe_json="$(run_machine_probe production "cat '$AGENT_DIR/auth.json'; cat '$AGENT_DIR/mcp-auth.json'; cat '$AGENT_DIR/sessions/--fixture-cwd--/2026-11-17T00-00-00-seeded.jsonl'; cat '$AGENT_DIR/trust.json'")"
verify_probe "credentials and parent trust state are hidden; only the scratch trust file is bound" "$probe_json" <<'PYEOF'
import json, sys
result = json.loads(sys.argv[1])
combined = result["stdout"] + result["stderr"]
for leaked in ("AUTH-MARKER", "MCPAUTH-MARKER", "TRANSCRIPT-MARKER", "TRUST-MARKER"):
	assert leaked not in combined, f"{leaked} leaked into the child"
# The scratch trust file is bound over agentDir/trust.json: the child
# sees the empty provisioning object, not the parent's real trust
# state, and the transcript, auth, and mcp-auth paths are simply
# absent (their cat errors above).
assert "{}" in result["stdout"], f"scratch trust file not bound: {result['stdout'][:300]}"
assert combined.count("No such file or directory") >= 3, f"hidden entries not all denied: {combined[:300]}"
PYEOF
fi

echo "== 7. escape-channel service units =="
# The service runs against the same fixture repo; these requests are
# host-side (no namespace), exercising the service contract directly.
export SUITE_RUN_DIR="$RUN" SUITE_REPO="$REPO" SUITE_AGENT_DIR="$AGENT_DIR" SUITE_SERVICE_PY="$SERVICE_PY"
run_service_unit() { # python snippet on stdin; ok/bad lines on stdout
	ISOLATION_LIB="$LIB" python3 - "$@" 2>&1
}

service_out="$(run_service_unit "$SOCKET" "$SUITE_TOKEN" "$TASKFILE_BASE" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

socket, token, taskfile = sys.argv[1:4]

def request(argv, session="driver-child", tok=token, stdin=""):
	return ic.service_request(socket, {"argv": argv, "session": session, "token": tok, "stdin": stdin})

exit_code, stdout, stderr = request(["tasks", "show", taskfile, "--json"])
assert exit_code == 0, f"sanctioned read failed: {exit_code} {stderr[:200]}"
assert "schema_version" in stdout, "sanctioned read body missing"
print("ok service serves the sanctioned read verb")
PYEOF
)"
absorb_results "service read unit" "$service_out" $?

service_out="$(run_service_unit "$SOCKET" "$SUITE_TOKEN" "$TASKFILE_BASE" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

socket, token, taskfile = sys.argv[1:4]

def request(argv, session="driver-child", tok=token, stdin=""):
	return ic.service_request(socket, {"argv": argv, "session": session, "token": tok, "stdin": stdin})

exit_code, _stdout, stderr = request(
	["tasks", "log", taskfile, "--from", "driver-child", "isolation suite checkpoint through the channel"])
assert exit_code == 0, f"sanctioned log failed: {exit_code} {stderr[:300]}"
exit_code, _stdout, stderr = request(
	["tasks", "report", taskfile, "--slug", "suite", "--from", "driver-child", "--digest", "channel deposit check", "-"],
	stdin="# Suite report body\n\nDeposited through the escape channel.\n",
)
assert exit_code == 0, f"sanctioned report failed: {exit_code} {stderr[:300]}"
exit_code, stdout, _stderr = request(["tasks", "show", taskfile, "--tail", "20"])
assert "isolation suite checkpoint through the channel" in stdout, f"log entry not visible: {stdout[:400]}"
assert "iso-channel-" in stdout, f"service-bound attribution label missing: {stdout[-400:]}"
assert "driver-child" not in stdout, f"claimed session leaked into the board: {stdout[-400:]}"
print("ok service serves the sanctioned write verbs with service-bound attribution")
PYEOF
)"
absorb_results "service write units" "$service_out" $?

# S-attribution pin: write attribution binds to the service's session
# registry (the token-derived channel label); a claimed session or a
# claimed --from never reaches the board.
service_out="$(run_service_unit "$SOCKET" "$SUITE_TOKEN" "$TASKFILE_BASE" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

socket, token, taskfile = sys.argv[1:4]


def request(argv, session="driver-child", tok=token, stdin=""):
	return ic.service_request(socket, {"argv": argv, "session": session, "token": tok, "stdin": stdin})

exit_code, _out, stderr = request(
	["tasks", "log", taskfile, "--from", "spoofed-agent", "attribution binding checkpoint"],
	session="manager")
assert exit_code == 0, f"sanctioned log with claimed identity failed: {exit_code} {stderr[:300]}"
exit_code, stdout, _stderr = request(["tasks", "show", taskfile, "--tail", "1"])
assert exit_code == 0, f"show failed: {exit_code}"
assert "attribution binding checkpoint" in stdout, f"log entry missing: {stdout[-400:]}"
assert "spoofed-agent" not in stdout, f"claimed --from reached the board: {stdout[-400:]}"
assert "manager" not in stdout, f"claimed session reached the board: {stdout[-400:]}"
assert "iso-channel-" in stdout, f"provisioned channel label not the attribution: {stdout[-400:]}"
print("ok S-attribution: channel writes attribute to the service-bound label, claimed identities never land")
PYEOF
)"
absorb_results "S-attribution pin" "$service_out" $?

# F1 pins: the report verb's body-file positional was an unmasked
# arbitrary-file-read lane (the service read the child-named file with
# the parent's view and deposited its content into the board, and the
# file shape was unbounded). The file shape is refused outright, the
# secret must never appear in any response or deposit, and every
# element resolving outside the board repo is refused (the compose pin
# drives a symlink-then-dotdot positional through esc-etc, which only
# the kernel-style candidate sees).
service_out="$(run_service_unit "$SOCKET" "$SUITE_TOKEN" "$TASKFILE_BASE" <<'PYEOF'
import json, os, sys
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

socket, token, taskfile = sys.argv[1:4]
suite_dir = os.environ["SUITE_RUN_DIR"]
repo_real = os.path.realpath(os.environ["SUITE_REPO"])


def request(argv, session="driver-child", tok=token, stdin=""):
	return ic.service_request(socket, {"argv": argv, "session": session, "token": tok, "stdin": stdin})

secret_file = os.path.join(os.environ["SUITE_AGENT_DIR"], "auth.json")
with open(secret_file) as handle:
	secret_text = handle.read()
exit_code, out, stderr = request(
	["tasks", "report", taskfile, "--slug", "steal", "--from", "evil",
	 "--digest", "arbitrary read attempt", secret_file])
assert exit_code == 126, f"body file outside the board not refused: {exit_code} {stderr[:200]}"
assert "refused" in stderr.lower(), f"refusal not named: {stderr[:200]}"
assert "AUTH-MARKER-4f21" not in out + stderr, "SECRET CONTENT REACHED THE CHILD"

exit_code, out, stderr = request(
	["tasks", "report", taskfile, "--slug", "inside", "--from", "evil",
	 "--digest", "board-internal file attempt", os.path.join(repo_real, "README.md")])
assert exit_code == 126, f"board-internal body file not refused: {exit_code} {stderr[:200]}"

big_file = os.path.join(suite_dir, "flood.bin")
with open(big_file, "wb") as handle:
	handle.write(b"x" * (2 * 1024 * 1024))
exit_code, out, stderr = request(
	["tasks", "report", taskfile, "--slug", "flood", "--from", "evil",
	 "--digest", "flooding attempt", big_file])
assert exit_code == 126, f"unbounded body-file shape not refused: {exit_code} {stderr[:200]}"

exit_code, out, stderr = request(
	["tasks", "show", "esc-etc/hostname"], session="driver-child")
assert exit_code == 126, f"escaping positional not refused: {exit_code} {stderr[:200]}"
assert "outside the board repo" in stderr, f"path policy not named: {stderr[:200]}"

exit_code, out, _stderr = request(
	["tasks", "reports", taskfile, "--include-body", "--json"], session="driver-child")
assert exit_code == 0, f"reports read failed: {exit_code}"
assert "AUTH-MARKER-4f21" not in out, "SECRET REACHED THE BOARD"
assert "steal" not in out and "flood" not in out, "refused deposits still landed"
print("ok F1 pins: child-named body files and board-escaping positionals are refused; the flood lane is closed")
PYEOF
)"
absorb_results "F1 refusal pins" "$service_out" $?

service_out="$(run_service_unit "$SOCKET" "$SUITE_TOKEN" "$TASKFILE_BASE" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

socket, token, taskfile = sys.argv[1:4]

def request(argv, session="driver-child", tok=token, stdin=""):
	return ic.service_request(socket, {"argv": argv, "session": session, "token": tok, "stdin": stdin})

exit_code, _out, stderr = request(["tasks", "show", taskfile, "--json"], tok="")
assert exit_code == 126 and "token" in stderr.lower(), f"missing token not refused: {exit_code} {stderr[:200]}"
exit_code, _out, _stderr = request(["tasks", "show", taskfile, "--json"], tok="0" * 64)
assert exit_code == 126, f"wrong token not refused: {exit_code}"
exit_code, _out, _stderr = request(["tasks", "show", taskfile, "--json"], session="")
assert exit_code == 126, f"missing session not refused: {exit_code}"
exit_code, _out, _stderr = request(["tasks", "show", taskfile, "--json"], session="bad session!")
assert exit_code == 126, f"malformed session not refused: {exit_code}"
exit_code, _out, _stderr = request(["tasks", "set", taskfile, "Status=Completed"])
assert exit_code == 126, f"non-whitelisted verb not refused: {exit_code}"
exit_code, _out, _stderr = request(["tasks", "init"])
assert exit_code == 126, f"init not refused: {exit_code}"
exit_code, _out, _stderr = request(["tasks", "export", "--include-reports"])
assert exit_code == 126, f"export not refused: {exit_code}"
exit_code, _out, stderr = request(["tasks", "show", "--dir", "/tmp", taskfile])
assert exit_code == 126 and "--dir" in stderr, f"--dir not refused: {exit_code} {stderr[:200]}"
print("ok service refuses missing and wrong tokens, bad sessions, unsanctioned verbs, and --dir")
PYEOF
)"
absorb_results "service refusal units" "$service_out" $?

service_out="$(run_service_unit "$SOCKET" "$SUITE_TOKEN" "$TASKFILE_BASE" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

socket, token, taskfile = sys.argv[1:4]
oversize = "x" * (2 * 1024 * 1024)
exit_code, _out, stderr = ic.service_request(
	socket,
	{"argv": ["tasks", "report", taskfile, "--slug", "big", "--digest", "d", "-"],
	 "session": "driver-child", "token": token, "stdin": oversize})
assert exit_code == 126 and "cap" in stderr.lower(), f"oversize request not refused: {exit_code} {stderr[:200]}"
exit_code, stdout, _stderr = ic.service_request(
	socket, {"argv": ["tasks", "show", taskfile, "--project"], "session": "driver-child", "token": token})
assert exit_code == 0, f"service did not survive the oversize refusal: {exit_code} {stdout[:200]}"
print("ok oversize requests are rejected and the service keeps serving")
PYEOF
)"
absorb_results "service oversize unit" "$service_out" $?

# S-slow-send pin: a hostile sender trickling bytes under the per-recv
# timeout must hit the wall-clock read window instead of holding the
# sequential service. The window constant is patched short and handle()
# runs directly against a socketpair so the pin stays fast.
service_out="$(run_service_unit <<'PYEOF'
import importlib.util, json, os, socket, sys, threading, time

spec = importlib.util.spec_from_file_location("iso_service_under_test", os.environ["SUITE_SERVICE_PY"])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REQUEST_RECV_WINDOW_SECONDS = 0.5

parent, child = socket.socketpair()


def slow_peer():
	try:
		while True:
			child.sendall(b"x")
			time.sleep(0.2)
	except OSError:
		pass

threading.Thread(target=slow_peer, daemon=True).start()

start = time.monotonic()
box = {}


def serve():
	module.handle(parent, os.environ["SUITE_REPO"], "unused-token",
	              os.path.join(os.environ["SUITE_RUN_DIR"], "slow-send.log"))

server = threading.Thread(target=serve)
server.start()
server.join(timeout=5)
elapsed = time.monotonic() - start
assert not server.is_alive(), "handle did not return after the read window"
assert elapsed < 3, f"slow sender held the connection for {elapsed:.2f}s"
child.settimeout(2)
response = b""
try:
	while True:
		chunk = child.recv(65536)
		if not chunk:
			break
		response += chunk
except socket.timeout:
	pass
verdict = json.loads(response.decode())
assert verdict["exit"] == 126, f"slow sender not refused: {verdict}"
assert "read window" in verdict["stderr"], f"window refusal not named: {verdict}"
print("ok S-slow-send: a trickle sender hits the wall-clock read window and is refused")
PYEOF
)"
absorb_results "S-slow-send pin" "$service_out" $?

service_out="$(run_service_unit "$SOCKET" "$SUITE_TOKEN" "$TASKFILE_BASE" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["ISOLATION_LIB"])
import isolation_common as ic

socket, token, taskfile = sys.argv[1:4]
exit_code, stdout, _stderr = ic.service_request(
	socket, {"argv": ["tasks", "show", taskfile, "--project"],
	         "session": "driver-child", "token": token})
assert exit_code == 0, f"service did not survive the slow-send window pin: {exit_code}"
print("ok service keeps serving after the slow-send window pin")
PYEOF
)"
absorb_results "service survives slow-send pin" "$service_out" $?

# L1 edge-fix pin: a request trickled across the read window must not
# leave the response sendall inheriting the window's near-zero timeout
# residue. handle() runs against a recording socketpair proxy so the
# pin asserts the timeout is reset to the full send timeout after the
# recv loop breaks and before the first response send.
service_out="$(run_service_unit "$TASKFILE_BASE" <<'PYEOF'
import importlib.util, json, os, socket, sys, threading, time

spec = importlib.util.spec_from_file_location("iso_service_under_test", os.environ["SUITE_SERVICE_PY"])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REQUEST_RECV_WINDOW_SECONDS = 1.0

taskfile = sys.argv[1]

parent, child = socket.socketpair()


class RecordingSocket:

	def __init__(self, sock):
		self.sock = sock
		self.events = []

	def settimeout(self, value):
		self.events.append(("settimeout", value))
		self.sock.settimeout(value)

	def recv(self, size):
		self.events.append(("recv", size))
		return self.sock.recv(size)

	def sendall(self, data):
		self.events.append(("sendall", len(data)))
		self.sock.sendall(data)

	def close(self):
		self.sock.close()


recording = RecordingSocket(parent)

request = json.dumps({
	"argv": ["tasks", "show", taskfile, "--project"],
	"session": "driver-child", "token": "edge-fix-token", "stdin": "",
}).encode()


def trickling_peer():
	sent = 0
	while sent < len(request):
		child.sendall(request[sent:sent + 4])
		sent += 4
		time.sleep(0.01)
	child.shutdown(socket.SHUT_WR)


threading.Thread(target=trickling_peer, daemon=True).start()


def serve():
	module.handle(recording, os.environ["SUITE_REPO"], "edge-fix-token",
	              os.path.join(os.environ["SUITE_RUN_DIR"], "edge-fix-residue.log"))


server = threading.Thread(target=serve)
server.start()
server.join(timeout=10)
assert not server.is_alive(), "handle did not return for the trickled request"

child.settimeout(5)
response = b""
while True:
	chunk = child.recv(65536)
	if not chunk:
		break
	response += chunk
child.close()
verdict = json.loads(response.decode())
assert verdict["exit"] == 0, f"trickled request not served: {verdict}"

first_send = next(index for index, (kind, _value) in enumerate(recording.events)
                  if kind == "sendall")
timeouts_before_send = [value for kind, value in recording.events[:first_send]
                        if kind == "settimeout"]
assert len(timeouts_before_send) >= 2, (
	f"trickle did not force multiple recv iterations: {recording.events}")
assert all(value <= module.REQUEST_RECV_WINDOW_SECONDS
           for value in timeouts_before_send[:-1]), (
	f"in-loop recv timeouts exceed the patched window: {timeouts_before_send}")
assert timeouts_before_send[-1] == module.REQUEST_TIMEOUT_SECONDS, (
	f"response send inherits the recv-window residue {timeouts_before_send[-1]!r} "
	f"instead of the full {module.REQUEST_TIMEOUT_SECONDS}s send timeout")
print("ok L1 edge-fix: the response send never inherits the recv-window timeout residue")
PYEOF
)"
absorb_results "L1 timeout-residue pin" "$service_out" $?

bad_dir="$RUN/open-escape"
mkdir -p "$bad_dir"
chmod 755 "$bad_dir"
service_out="$(PI_TASK_STORAGE_TOKEN="$SUITE_TOKEN" python3 "$SERVICE_PY" "$bad_dir/service.sock" "$REPO" "$bad_dir/service.log" 2>&1)"
visibility_rc=$?
if [[ $visibility_rc -ne 0 ]] && grep -q "0700" <<<"$service_out"; then
	ok "service refuses to bind outside a 0700 socket dir (visibility gate)"
else
	bad "service refuses to bind outside a 0700 socket dir (visibility gate): rc=$visibility_rc"
fi

watchdog_dir="$RUN/watchdog"
mkdir -p "$watchdog_dir"
chmod 700 "$watchdog_dir"
watchdog_sh="$watchdog_dir/parent.sh"
cat >"$watchdog_sh" <<EOF
#!/bin/sh
PI_TASK_STORAGE_TOKEN="$SUITE_TOKEN" python3 "$SERVICE_PY" "$watchdog_dir/service.sock" "$REPO" "$watchdog_dir/service.log" &
pid=\$!
printf '%s' "\$pid" > "$watchdog_dir/pid"
wait
EOF
chmod +x "$watchdog_sh"
watchdog_parent_pid="$(bash -c "$watchdog_sh >/dev/null 2>&1 & echo \$!")"
for _ in $(seq 1 50); do
	if [[ -S "$watchdog_dir/service.sock" ]]; then
		break
	fi
	sleep 0.1
done
if [[ ! -S "$watchdog_dir/service.sock" ]]; then
	fail_fast "watchdog probe service never came up"
fi
watchdog_service_pid="$(cat "$watchdog_dir/pid")"
kill "$watchdog_parent_pid" 2>/dev/null
watchdog_clean=0
for _ in $(seq 1 100); do
	if ! kill -0 "$watchdog_service_pid" 2>/dev/null && [[ ! -e "$watchdog_dir/service.sock" ]]; then
		watchdog_clean=1
		break
	fi
	sleep 0.1
done
if [[ "$watchdog_clean" -eq 1 ]]; then
	ok "service exits and unlinks its socket when the parent session dies (no daemon surface)"
else
	bad "service exits and unlinks its socket when the parent session dies"
fi

if grep -qF "sanctioned=True" "$SERVICE_LOG"; then
	ok "service log carries sanctioned attribution records"
else
	bad "service log carries sanctioned attribution records"
fi

print_result
if ((fail == 0)); then
	exit 0
fi
exit 1
