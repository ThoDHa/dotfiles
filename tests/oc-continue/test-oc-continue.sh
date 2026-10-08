#!/usr/bin/env bash
#
# Tests for the oc-continue runner. Self-contained: a fake opencode binary
# (invocation recorder with a scripted outcome plan) drives the engine
# through the OC_BIN / OC_STATE_DIR / OC_WAIT_SECONDS /
# OC_MIN_PROGRESS_SECONDS seams, asserting productive-cycle budget
# counting across quota hits (no-progress re-parks, the never-reset
# bound, and the wall-time fallback included), park math, per-session
# retention, the --follow launch-plus-tail contract, and flag passthrough
# isolation. When the real opencode is on PATH, OC_VALUE_FLAGS is
# additionally pinned against live `opencode run --help` and the declared
# flag table checked for overlap with the documented set; without it
# those checks skip.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OC="$REPO_ROOT/shell/bin/oc-continue"

pass=0
fail=0
skip=0

ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }
skip_test() { printf '  \033[0;33m- skipped\033[0m %s\n' "$1"; skip=$((skip + 1)); }

assert_eq() { # label expected actual
	if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
assert_contains() { # label haystack needle
	if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing [$3])"; fi
}
assert_not_contains() { # label haystack needle
	if grep -qF -- "$3" <<<"$2"; then bad "$1 (unexpected [$3])"; else ok "$1"; fi
}
refuse() { # label; rest is the command to attempt
	local label="$1"; shift
	if oc "$@" </dev/null >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi
}

ROOT="$(mktemp -d)"
follower=""
cleanup() {
	local pf pid
	[[ -n "$follower" ]] && kill "$follower" 2>/dev/null
	for pf in "$ROOT"/*/state/run.pid; do
		[[ -f "$pf" ]] || continue
		pid="$(cat "$pf" 2>/dev/null)"
		if [[ "$pid" =~ ^[0-9]+$ ]]; then
			kill "$pid" 2>/dev/null
			sleep 0.1
			kill -9 "$pid" 2>/dev/null
		fi
	done
	rm -rf "$ROOT"
}
trap cleanup EXIT

FAKE="$ROOT/fake-opencode"
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
# Recorder fake: appends this invocation's argv to $FAKE_STATE/args
# (tab-separated, one record per line), counts calls in
# $FAKE_STATE/count, and follows $FAKE_STATE/plan line N for call N:
# quota (noise prologue, then an immediate quota fail: no progress),
# productive (the same noise prologue, then one blockquote-shaped
# assistant line without the · separator, whose survival against the
# banner exclusion pins its both-markers rule, then a quota fail),
# slowquota (the noise prologue, a FAKE_SLOW wait, then a quota fail),
# fail, slow, or ok by default. The noise prologue is the real
# transcript's opening: an escape-only line, the run banner, and a
# second escape-only line; none of it may read as progress.
n=$(( $(cat "$FAKE_STATE/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAKE_STATE/count"
{ printf '\t%s' "$@"; printf '\n'; } >>"$FAKE_STATE/args"
mode="$(sed -n "${n}p" "$FAKE_STATE/plan" 2>/dev/null)"
esc_reset=$'\e[0m'
banner='> build · glm-5.3'
quota_noise() { printf '%s\n' "$esc_reset" "$banner" "$esc_reset"; }
quota_fail() { echo "Error 429: rate limit exceeded"; echo "stderr: quota window active" >&2; exit 1; }
case "${mode:-ok}" in
	quota)      quota_noise; quota_fail ;;
	productive) quota_noise; echo "> quoted remark"; quota_fail ;;
	slowquota)  quota_noise; sleep "${FAKE_SLOW:-5}"; quota_fail ;;
	fail)       echo "fake session $n start"; echo "fatal: unrecoverable failure"; exit 3 ;;
	slow)       echo "slow line one"; sleep "${FAKE_SLOW:-5}"; echo "slow line two"; exit 0 ;;
	*)          echo "fake session $n start"; echo "fake session $n done"; exit 0 ;;
esac
EOF
chmod +x "$FAKE"

fresh() { # name; new isolated state dir and fake control files
	STATE="$ROOT/$1/state"
	FAKE_STATE="$ROOT/$1/fake"
	mkdir -p "$STATE" "$FAKE_STATE"
	: >"$FAKE_STATE/args"
	: >"$FAKE_STATE/count"
	: >"$FAKE_STATE/plan"
	# exported live: the engine and its fake are grandchildren that must
	# see the current scenario's control files
	export FAKE_STATE
}

OC_ENV=()
oc() { # oc-continue under test, seams wired for the current scenario
	env OC_BIN="$FAKE" OC_STATE_DIR="$STATE" ${OC_ENV[@]+"${OC_ENV[@]}"} "$OC" "$@"
}

wait_for() { # timeout_seconds; rest is a poll command run until it succeeds
	local deadline=$(( $(date +%s) + $1 )); shift
	while (( $(date +%s) < deadline )); do
		if "$@" >/dev/null 2>&1; then return 0; fi
		sleep 0.1
	done
	return 1
}

engine_idle() { [[ ! -f "$STATE/run.pid" ]]; }
proc_gone() { ! kill -0 "$1" 2>/dev/null; }
fake_calls() { cat "$FAKE_STATE/count" 2>/dev/null || echo 0; }
invocation_args() { # n; prints the nth recorded invocation, one arg per line
	sed -n "${1}p" "$FAKE_STATE/args" | tr '\t' '\n' | sed '/^$/d'
}
assert_invocation() { # label n expected-args...
	local label="$1" n="$2"; shift 2
	assert_eq "$label" "$(printf '%s\n' "$@")" "$(invocation_args "$n")"
}

# A non-interactive shell backgrounds jobs with SIGINT ignored, exec
# preserves that disposition, and no shell can unignore it, so a plain
# background launch would make the follower immune to the very signal
# under test. perl (or python3) can restore SIG_DFL via sigaction before
# exec, which is the only faithful way to simulate Ctrl-C from a script.
reset_int=()
if command -v perl >/dev/null 2>&1; then
	reset_int=(perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV')
elif command -v python3 >/dev/null 2>&1; then
	reset_int=(python3 -c 'import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
os.execvp(sys.argv[1], sys.argv[1:])')
fi

echo "== budget counting across productive quota cycles =="
fresh budget
printf 'productive\nproductive\nok\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.3)
out="$(oc run -n 3 ship the feature)"
OC_ENV=()
assert_contains "launcher detaches immediately" "$out" "detached (pid"
wait_for 15 engine_idle && ok "engine rides two quota windows and finishes" \
	|| bad "engine rides two quota windows and finishes"
assert_eq "three sessions ran under a three-session budget" "3" "$(fake_calls)"
assert_contains "engine log records the clean completion" "$(cat "$STATE/engine.log")" \
	"session 3: run completed cleanly"
assert_contains "engine log records the OC_WAIT_SECONDS park" "$(cat "$STATE/engine.log")" \
	"parking 0.3s"
assert_invocation "every session resumes with --continue --auto" 3 \
	run --continue --auto "ship the feature"

fresh spent
printf 'productive\nproductive\nproductive\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.2)
oc run -n 2 keep going >/dev/null 2>&1
OC_ENV=()
wait_for 15 engine_idle && ok "budget-spent run parks once then quits" \
	|| bad "budget-spent run parks once then quits"
assert_eq "budget spent stops at the second hit" "2" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "engine log records the spent budget" "$log" "budget spent"
assert_contains "the quit fires on the Nth productive hit" "$log" \
	"productive quota hit 2 of budget 2; budget spent, quitting"

fresh hardfail
printf 'fail\n' >"$FAKE_STATE/plan"
oc run one shot only >/dev/null 2>&1
wait_for 10 engine_idle && ok "non-quota failure ends the run" \
	|| bad "non-quota failure ends the run"
assert_eq "non-quota failure is not retried" "1" "$(fake_calls)"
assert_contains "engine log records the non-quota failure" "$(cat "$STATE/engine.log")" \
	"non-quota failure rc=3"

fresh oneshot
printf 'quota\n' >"$FAKE_STATE/plan"
oc in 0 --pure do it >/dev/null 2>&1
wait_for 10 engine_idle && ok "one-shot completes its single run" \
	|| bad "one-shot completes its single run"
assert_invocation "one-shot forwards oc flags after its duration" 1 \
	run --continue --auto --pure "do it"
assert_contains "one-shot quota hit is not retried" "$(cat "$STATE/engine.log")" \
	"one-shot: quota hit"
[[ -f "$STATE/last.1.out" ]] && ok "one-shot run retains its session output" \
	|| bad "one-shot run retains its session output"

echo "== no-progress re-parks and the never-reset bound =="
fresh budget_free
# productive cycles count toward the budget while a no-progress attempt
# leaves it untouched: the quit fires on the Nth productive hit, not the
# Nth invocation
printf 'quota\nproductive\nproductive\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.2)
oc run -n 2 try again >/dev/null 2>&1
OC_ENV=()
wait_for 15 engine_idle && ok "a no-progress fail followed by two productive hits ends on the budget" \
	|| bad "a no-progress fail followed by two productive hits ends on the budget"
assert_eq "the no-progress attempt ran but spent no budget unit" "3" "$(fake_calls)"
assert_contains "the fake's banner noise reached the retained session output" \
	"$(cat "$STATE/last.1.out")" "> build · glm-5.3"
log="$(cat "$STATE/engine.log")"
assert_contains "the banner-noise prologue alone classifies no progress" "$log" \
	"no-progress quota hit 1 of 3 consecutive; no budget consumed"
assert_contains "the budget still quits on the second productive hit" "$log" \
	"productive quota hit 2 of budget 2; budget spent, quitting"

fresh repark
# an immediate quota fail right after a park means the reset never took:
# the engine re-parks on the same math without consuming budget and can
# still finish cleanly later
printf 'quota\nquota\nok\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.2)
oc run -n 2 keep trying >/dev/null 2>&1
OC_ENV=()
wait_for 15 engine_idle && ok "two no-progress fails re-park and a later session finishes cleanly" \
	|| bad "two no-progress fails re-park and a later session finishes cleanly"
assert_eq "both re-parks retried without spending the two-session budget" "3" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the run ends cleanly rather than on the budget" "$log" "run completed cleanly"
assert_not_contains "no productive cycle was ever spent" "$log" "budget spent"
for n in 1 2 3; do
	[[ -f "$STATE/last.$n.out" ]] && ok "retry session $n keeps its own last.$n.out" \
		|| bad "retry session $n keeps its own last.$n.out"
done

fresh neverreset
# three consecutive no-progress attempts mean the window never opened:
# the bound quit fires even though the budget is far from spent
printf 'quota\nquota\nquota\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.2)
oc run -n 5 still trying >/dev/null 2>&1
OC_ENV=()
wait_for 15 engine_idle && ok "three consecutive no-progress attempts end the run" \
	|| bad "three consecutive no-progress attempts end the run"
assert_eq "the bound quit stops after the third attempt" "3" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the engine reports the limit never reset" "$log" \
	"no-progress quota hit 3 consecutive; limit never reset, quitting"
assert_not_contains "the bound quit stays distinct from budget exhaustion" "$log" "budget spent"

fresh boundreset
# a productive session resets the consecutive count, so no-progress
# streaks on either side of it neither quit the run nor spend budget
printf 'quota\nproductive\nquota\nquota\nproductive\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.2)
oc run -n 2 push through >/dev/null 2>&1
OC_ENV=()
wait_for 15 engine_idle && ok "a productive session lets the run survive later no-progress streaks" \
	|| bad "a productive session lets the run survive later no-progress streaks"
assert_eq "the run reaches its fifth invocation before the budget quits" "5" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the consecutive count restarts after a productive session" "$log" \
	"no-progress quota hit 2 of 3 consecutive; no budget consumed"
assert_contains "the productive cycles still spend the budget" "$log" \
	"productive quota hit 2 of budget 2; budget spent, quitting"
assert_not_contains "the reset kept the bound from firing" "$log" "limit never reset"

echo "== wall-time fallback for content-less quota hits =="
fresh fallback_up
# the time half of the conjunction: a quota fail whose whole output
# matched the filter still counts as productive once it outlasted the
# floor, which OC_MIN_PROGRESS_SECONDS pins low enough to test
printf 'slowquota\nok\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.2 FAKE_SLOW=1.2 OC_MIN_PROGRESS_SECONDS=1)
oc run -n 2 grind it out >/dev/null 2>&1
OC_ENV=()
wait_for 15 engine_idle && ok "a slow quota fail at or over the floor counts as productive" \
	|| bad "a slow quota fail at or over the floor counts as productive"
assert_eq "the slow fail ran once and the run resumed past it" "2" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the at-floor slow fail spent a productive cycle" "$log" \
	"productive quota hit 1 of budget 2; parking 0.2s"
assert_contains "the run finished cleanly after the fallback hit" "$log" "run completed cleanly"

fresh fallback_under
# under the floor the same fail is no-progress: the engine re-parks
# without spending budget and still finishes cleanly
printf 'slowquota\nok\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=0.2 FAKE_SLOW=1.2 OC_MIN_PROGRESS_SECONDS=5)
oc run -n 2 slow start >/dev/null 2>&1
OC_ENV=()
wait_for 15 engine_idle && ok "a slow quota fail under the floor is no progress" \
	|| bad "a slow quota fail under the floor is no progress"
assert_eq "the sub-floor fail re-parked instead of spending budget" "2" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the sub-floor fail logged a no-progress re-park" "$log" \
	"no-progress quota hit 1 of 3 consecutive; no budget consumed"
assert_not_contains "no productive cycle was recorded" "$log" "productive quota hit"

echo "== park math =="
park_default="$(sed -n 's/^PARK_SECONDS=\([0-9]\+\).*/\1/p' "$OC")"
epoch_fn="$(awk '/^epoch_of\(\)/{f=1} f{print} f&&/^}/{exit}' "$OC")"
park_fn="$(awk '/^park_seconds\(\)/{f=1} f{print} f&&/^}/{exit}' "$OC")"
zsh_park() {
	env "$@" zsh -c "PARK_SECONDS=$park_default
$epoch_fn
$park_fn
park_seconds"
}
assert_eq "OC_WAIT_SECONDS pins the park length" "7" "$(zsh_park OC_WAIT_SECONDS=7)"
assert_eq "no override parks the observed default" "$park_default" \
	"$(zsh_park -u OC_WAIT_SECONDS -u OC_WAIT_UNTIL)"
assert_eq "a past OC_WAIT_UNTIL floors to a minute" "60" \
	"$(zsh_park OC_WAIT_UNTIL=yesterday)"
future_park="$(zsh_park OC_WAIT_UNTIL='+90 seconds')"
if [[ "$future_park" =~ ^[0-9]+$ ]] && (( future_park >= 85 && future_park <= 90 )); then
	ok "a future OC_WAIT_UNTIL parks exactly the remaining seconds ($future_park)"
else
	bad "a future OC_WAIT_UNTIL parks exactly the remaining seconds (got [$future_park])"
fi
if zsh_park OC_WAIT_UNTIL='not a time' >/dev/null 2>&1; then
	bad "an unparseable OC_WAIT_UNTIL fails"
else
	ok "an unparseable OC_WAIT_UNTIL fails"
fi

echo "== per-session retention =="
fresh retain
printf 'productive\nok\n' >"$FAKE_STATE/plan"
OC_ENV=(OC_WAIT_SECONDS=2)
oc run -n 2 keep going >/dev/null 2>&1
OC_ENV=()
# waiting on the fake's stderr line proves the merged 2>&1 stream, not
# just stdout, lands live in last.out through the multios tee
wait_for 10 grep -q "stderr: quota window active" "$STATE/last.out" \
	&& ok "live last.out fills with merged stdout and stderr" \
	|| bad "live last.out fills with merged stdout and stderr"
assert_not_contains "while parked, the live file still shows the finished session" \
	"$(cat "$STATE/last.out")" "fake session 2"
wait_for 15 engine_idle && ok "parked run resumes and finishes" \
	|| bad "parked run resumes and finishes"
for n in 1 2; do
	[[ -f "$STATE/last.$n.out" ]] && ok "session $n output retained at last.$n.out" \
		|| bad "session $n output retained at last.$n.out"
done
assert_not_contains "retained session 1 holds no session 2 output" \
	"$(cat "$STATE/last.1.out")" "fake session 2"
assert_not_contains "retained session 2 holds no session 1 output" \
	"$(cat "$STATE/last.2.out")" "fake session 1"
assert_contains "retained session 2 is complete" "$(cat "$STATE/last.2.out")" "fake session 2 done"
assert_eq "live last.out ends as the final session alone" "$(cat "$STATE/last.2.out")" \
	"$(cat "$STATE/last.out")"
st="$(oc status)"
assert_contains "status lists the retained outputs" "$st" \
	"retained session output: last.1.out last.2.out"
clean_out="$(oc clean)"
assert_contains "clean reports the wiped state" "$clean_out" "cleaned"
[[ ! -d "$STATE" ]] && ok "clean removes the retained set with the state dir" \
	|| bad "clean removes the retained set with the state dir"

fresh prune
: >"$STATE/last.2.out"
oc run -n 1 fresh start >/dev/null 2>&1
wait_for 10 engine_idle && ok "prune-probe run completes" || bad "prune-probe run completes"
st="$(oc status)"
assert_contains "status presents the new run's session" "$st" "retained session output: last.1.out"
assert_not_contains "a stale longer run's sessions are pruned at start" "$st" "last.2.out"
[[ ! -f "$STATE/last.2.out" ]] && ok "the stale last.2.out is gone from the state dir" \
	|| bad "the stale last.2.out is gone from the state dir"

echo "== run --follow: consumed flag, Ctrl-C kills the follower only =="
fresh follow
printf 'slow\n' >"$FAKE_STATE/plan"
follow_out="$ROOT/follow/follow.out"
if ((${#reset_int[@]})); then
	"${reset_int[@]}" env OC_BIN="$FAKE" OC_STATE_DIR="$STATE" FAKE_SLOW=6 \
		"$OC" run --model zhipu/glm-5.3 --follow -n 2 ship it >"$follow_out" 2>&1 &
else
	env OC_BIN="$FAKE" OC_STATE_DIR="$STATE" FAKE_SLOW=6 \
		"$OC" run --model zhipu/glm-5.3 --follow -n 2 ship it >"$follow_out" 2>&1 &
fi
follower=$!
wait_for 10 grep -q "following live output" "$follow_out" \
	&& ok "launcher announces follow mode" || bad "launcher announces follow mode"
engine_pid="$(cat "$STATE/run.pid" 2>/dev/null)"
[[ "$engine_pid" =~ ^[0-9]+$ ]] && ok "engine armed its pid" || bad "engine armed its pid"
wait_for 10 grep -q "slow line one" "$follow_out" \
	&& ok "follower tails the live engine output" || bad "follower tails the live engine output"
assert_invocation "--follow and -n are consumed after a passthrough flag, never forwarded" 1 \
	run --continue --auto --model zhipu/glm-5.3 "ship it"
sess="$(ps -o sess= -p "$engine_pid" 2>/dev/null | tr -d '[:space:]')"
assert_eq "engine runs in its own session, out of terminal signal reach" "$engine_pid" "$sess"
if ((${#reset_int[@]})); then
	kill -INT "$follower"
	follower_sig="INT"
else
	kill -TERM "$follower"
	follower_sig="TERM"
	skip_test "true Ctrl-C delivery (no perl or python3 to restore SIGINT)"
fi
wait "$follower" 2>/dev/null
follower_rc=$?
if (( follower_rc != 0 )); then
	ok "$follower_sig to the follower kills the follower ($follower_sig exit)"
else
	bad "$follower_sig to the follower kills the follower (rc 0)"
fi
sleep 0.3
if kill -0 "$engine_pid" 2>/dev/null; then
	ok "engine keeps running after the follower died"
else
	bad "engine keeps running after the follower died"
fi
st="$(oc status | head -1)"
assert_contains "status still shows the run after follower death" "$st" "running (pid"
stop_out="$(oc stop)"
assert_contains "stop still cancels the engine" "$stop_out" "stopped (pid"
wait_for 5 proc_gone "$engine_pid" && ok "stopped engine process is gone" \
	|| bad "stopped engine process is gone"
follower=""

echo "== passthrough isolation =="
fresh pass_known
oc run --session sess-1 --dir /tmp --log-level DEBUG --pure --fork \
	--model=zhipu/glm -m other/model fix it now >/dev/null 2>&1
wait_for 10 engine_idle && ok "flag-heavy run completes" || bad "flag-heavy run completes"
assert_invocation "value flags pair with their tokens, equals forms stay intact" 1 \
	run --continue --auto --session sess-1 --dir /tmp --log-level DEBUG --pure --fork \
	--model=zhipu/glm -m other/model "fix it now"

fresh pass_after
# a synchronous case must never carry --follow: the launcher execs into
# tail -F and would hang the suite, so bool-after-passthrough coverage
# lives in the backgrounded follower scenario above and this pins the
# trailing declared value flag instead, through the same dispatch arm
printf 'productive\nok\n' >"$FAKE_STATE/plan"
# timing invariant: the armed-pidfile window (park plus the two session
# durations) must outlast the launcher's poll grid (READY_POLLS x
# READY_POLL_INTERVAL in the script); a single-ok plan or a park under
# ~0.2s would reintroduce poll-grid misses and flake "failed to start"
# on slow machines
OC_ENV=(OC_WAIT_SECONDS=1)
pass_out="$(oc run --model zhipu/glm-5.3 -n 3 fix it 2>&1)"
OC_ENV=()
assert_contains "declared-after-passthrough launcher detaches cleanly" "$pass_out" "detached (pid"
wait_for 10 engine_idle && ok "declared-after-passthrough run completes" \
	|| bad "declared-after-passthrough run completes"
assert_invocation "a trailing declared value flag after a passthrough flag is consumed with its pair" 1 \
	run --continue --auto --model zhipu/glm-5.3 "fix it"

fresh pass_unknown
oc run --bogus --nonsense=1 fix >/dev/null 2>&1
wait_for 10 engine_idle && ok "unknown-flag run completes" || bad "unknown-flag run completes"
assert_invocation "unknown dash tokens pass through verbatim" 1 \
	run --continue --auto --bogus --nonsense=1 fix

fresh pass_unknown_val
oc run --flavor spicy fix >/dev/null 2>&1
wait_for 10 engine_idle && ok "unknown bare-flag run completes" \
	|| bad "unknown bare-flag run completes"
assert_invocation "unknown bare flags do not steal the next token" 1 \
	run --continue --auto --flavor "spicy fix"

fresh pass_dashdash
oc run -- --weird -n 2 >/dev/null 2>&1
wait_for 10 engine_idle && ok "dash-forced prompt run completes" \
	|| bad "dash-forced prompt run completes"
assert_invocation "bare -- forces everything after it to be prompt" 1 \
	run --continue --auto "--weird -n 2"

fresh pass_prompt_first
oc run fix --session ID >/dev/null 2>&1
wait_for 10 engine_idle && ok "prompt-first run completes" || bad "prompt-first run completes"
assert_invocation "flags after the first prompt word stay prompt" 1 \
	run --continue --auto "fix --session ID"

fresh pass_default
default_prompt="$(sed -n "s/^DEFAULT_PROMPT='\(.*\)'$/\1/p" "$OC")"
oc run >/dev/null 2>&1
wait_for 10 engine_idle && ok "default-prompt run completes" || bad "default-prompt run completes"
assert_invocation "no prompt falls back to the continuation prompt" 1 \
	run --continue --auto "$default_prompt"

fresh refuse_usage
refuse "run refuses a non-numeric budget" run -n abc fix it
refuse "run refuses a valueless trailing -n" run -n
refuse "run refuses a valueless trailing --model" run --model
err="$(oc run -n abc fix it 2>&1 >/dev/null || true)"
assert_contains "non-numeric budget refusal says why" "$err" "-n needs a number"
assert_eq "usage refusals spawn no invocation" "" "$(cat "$FAKE_STATE/args")"
[[ ! -f "$STATE/run.pid" ]] && ok "usage refusals arm no pid file" \
	|| bad "usage refusals arm no pid file"

echo "== value-flag parity against the real opencode binary =="
if real_oc="$(command -v opencode)"; then
	opt_re='^[[:space:]]*(-([a-zA-Z0-9]),[[:space:]]+)?(--[a-zA-Z0-9-]+)'
	inline_val_re='\[(string|number|array)\]'
	wrapped_val_re='^[[:space:]]*\[(string|number|array)\]'
	# The help wraps long option descriptions, leaving the type marker
	# alone on the next line; a bare marker line belongs to the option
	# above it.
	declare -A opt_takes_value=() opt_short=()
	opt_order=()
	cur=""
	while IFS= read -r line; do
		if [[ "$line" =~ $opt_re ]]; then
			cur="${BASH_REMATCH[3]}"
			[[ -z "${opt_takes_value[$cur]+x}" ]] && opt_order+=("$cur")
			opt_short["$cur"]="${BASH_REMATCH[2]:-}"
			if [[ "$line" =~ $inline_val_re ]]; then
				opt_takes_value["$cur"]=1
			else
				opt_takes_value["$cur"]=0
			fi
		elif [[ -n "$cur" && "$line" =~ $wrapped_val_re ]]; then
			opt_takes_value["$cur"]=1
		fi
	done < <("$real_oc" run --help 2>&1)
	derived_value=()
	derived_all=()
	for opt in "${opt_order[@]}"; do
		derived_all+=("$opt")
		[[ -n "${opt_short[$opt]}" ]] && derived_all+=("-${opt_short[$opt]}")
		if [[ "${opt_takes_value[$opt]}" == 1 ]]; then
			derived_value+=("$opt")
			[[ -n "${opt_short[$opt]}" ]] && derived_value+=("-${opt_short[$opt]}")
		fi
	done
	script_value_flags="$(sed -n 's/^OC_VALUE_FLAGS=(\(.*\))$/\1/p' "$OC" \
		| tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort)"
	assert_eq "OC_VALUE_FLAGS equals the help-derived value-taking set" \
		"$(printf '%s\n' "${derived_value[@]}" | LC_ALL=C sort)" "$script_value_flags"
	run_value_line="$(sed -n 's/^OC_RUN_VALUE_FLAGS=(\(.*\))$/\1/p' "$OC")"
	run_bool_line="$(sed -n 's/^OC_RUN_BOOL_FLAGS=(\(.*\))$/\1/p' "$OC")"
	assert_contains "declared value table extracted from the script" "$run_value_line" "-n"
	assert_contains "declared bool table extracted from the script" "$run_bool_line" "--follow"
	declare -A documented=()
	for flag in "${derived_all[@]}"; do documented["$flag"]=1; done
	overlap=""
	for flag in $run_value_line $run_bool_line; do
		[[ -n "${documented[$flag]+x}" ]] && overlap="$overlap $flag"
	done
	assert_eq "declared flags stay disjoint from the documented opencode set" "" "$overlap"
else
	skip_test "OC_VALUE_FLAGS parity (no real opencode on PATH)"
	skip_test "declared-table disjointness (no real opencode on PATH)"
fi

echo
printf 'Result: \033[0;32m%d passed\033[0m, ' "$pass"
if ((fail > 0)); then printf '\033[0;31m%d failed\033[0m' "$fail"; else printf '%d failed' "$fail"; fi
if ((skip > 0)); then printf ', \033[0;33m%d skipped\033[0m' "$skip"; fi
printf '\n'
((fail == 0)) || exit 1
