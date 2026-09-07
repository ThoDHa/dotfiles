#!/usr/bin/env bash
#
# LRU-16 wire proof demo: drives two headless opencode sessions (plugin OFF and
# plugin ON) against a local scripted mock provider, captures the outbound
# request payloads at the wire, and writes a verdict report with verbatim
# excerpts to $DEMO_DIR/demo-report.md. Re-runnable: the scratch directory is
# cleaned at the start of each run and the logs persist until the next run.
# Requires only node and opencode.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEMO_MJS="$REPO_ROOT/tests/opencode/lru-demo.mjs"
PLUGIN="$REPO_ROOT/opencode/.config/opencode/plugin/lru-context.ts"
DEMO_DIR="${LRU_DEMO_DIR:-/tmp/opencode/lru-demo}"
OPENCODE_BIN="${OPENCODE_BIN:-$(command -v opencode || true)}"
PROMPT="Proceed with the task steps; inspect $DEMO_DIR/files as needed."
SESSION_ENV="XDG_CONFIG_HOME=$DEMO_DIR/xdg/config XDG_DATA_HOME=$DEMO_DIR/xdg/data XDG_CACHE_HOME=$DEMO_DIR/xdg/cache XDG_STATE_HOME=$DEMO_DIR/xdg/state OPENCODE_DISABLE_AUTOCOMPACT=1 OPENCODE_DISABLE_PRUNE=1"

say()  { printf '[lru-demo] %s\n' "$1"; }
fail() { printf '[lru-demo] FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$DEMO_MJS" ]] || fail "demo module not found: $DEMO_MJS"
[[ -f "$PLUGIN" ]] || fail "plugin not found: $PLUGIN"
command -v node >/dev/null || fail "node not found on PATH"
[[ -n "$OPENCODE_BIN" ]] || fail "opencode not found on PATH"

config_meta_hash() {
	find "$HOME/.config/opencode" -xdev \( -type f -o -type l \) -printf '%y %p %s %T@\n' 2>/dev/null | sort | sha256sum | cut -d' ' -f1
}

config_content_hash() {
	find "$HOME/.config/opencode" -xdev -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1
}

wait_for_port() {
	local port="$1"
	for _ in $(seq 1 50); do
		if (echo > "/dev/tcp/127.0.0.1/$port") 2>/dev/null; then return 0; fi
		sleep 0.1
	done
	return 1
}

run_variant() {
	local variant="$1" port="$2"
	node "$DEMO_MJS" serve "$DEMO_DIR" "$port" "$variant" > "$DEMO_DIR/logs/server-$variant.log" 2>&1 &
	local server_pid=$!
	wait_for_port "$port" || { kill "$server_pid" 2>/dev/null; return 1; }
	(
		cd "$DEMO_DIR/projects/$variant" || exit 1
		env $SESSION_ENV "$OPENCODE_BIN" run --print-logs --log-level DEBUG "$PROMPT" \
			> "$DEMO_DIR/logs/run-$variant.stdout.log" \
			2> "$DEMO_DIR/logs/run-$variant.stderr.log"
	)
	local exit_code=$?
	kill "$server_pid" 2>/dev/null
	wait "$server_pid" 2>/dev/null
	printf '%s' "$exit_code"
}

META_BEFORE="$(config_meta_hash)"
CONTENT_BEFORE="$(config_content_hash)"

AVAIL_KB="$(df -k "$(dirname "$DEMO_DIR")" | awk 'NR==2 {print $4}')"
[[ "$AVAIL_KB" =~ ^[0-9]+$ ]] || AVAIL_KB=0
[[ "$AVAIL_KB" -ge 409600 ]] || fail "only ${AVAIL_KB}KiB free on $(dirname "$DEMO_DIR"); the demo needs ~500MiB of scratch space"

say "cleaning scratch directory $DEMO_DIR"
rm -rf "$DEMO_DIR"
mkdir -p "$DEMO_DIR"

PORT="$(node -e 'const s=require("node:net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})')"
[[ "$PORT" =~ ^[0-9]+$ ]] || fail "could not acquire a free port"

node "$DEMO_MJS" setup "$DEMO_DIR" "$PORT" "$PLUGIN" || fail "scratch setup failed"
OC_VERSION="$("$OPENCODE_BIN" --version 2>/dev/null | head -n1)"
say "scratch ready: port=$PORT opencode=$OC_VERSION plugin=$PLUGIN"

CMD_OFF="cd $DEMO_DIR/projects/off && $SESSION_ENV $OPENCODE_BIN run --print-logs --log-level DEBUG \"$PROMPT\""
CMD_ON="cd $DEMO_DIR/projects/on && $SESSION_ENV $OPENCODE_BIN run --print-logs --log-level DEBUG \"$PROMPT\""

say "running OFF session (plugin not registered)"
EXIT_OFF="$(run_variant off "$PORT")"
say "OFF session exit=$EXIT_OFF requests=$(ls "$DEMO_DIR"/capture/off/req-*.json 2>/dev/null | wc -l)"

say "running ON session (plugin registered by absolute path)"
EXIT_ON="$(run_variant on "$PORT")"
say "ON session exit=$EXIT_ON requests=$(ls "$DEMO_DIR"/capture/on/req-*.json 2>/dev/null | wc -l)"

META_AFTER="$(config_meta_hash)"
CONTENT_AFTER="$(config_content_hash)"

GEN_EXIT=0
node "$DEMO_MJS" report "$DEMO_DIR" "$EXIT_OFF" "$EXIT_ON" "$CMD_OFF" "$CMD_ON" "$OC_VERSION" \
	"$META_BEFORE" "$META_AFTER" "$CONTENT_BEFORE" "$CONTENT_AFTER" || GEN_EXIT=$?

cat "$DEMO_DIR/demo-report.md"
echo
say "log directory: $DEMO_DIR"
exit "$GEN_EXIT"
