#!/usr/bin/env bash
#
# Tests for the pi-continue runner. Self-contained: a fake pi binary
# (invocation recorder with a scripted outcome plan) drives the engine
# through the PI_CONTINUE_BIN / PI_CONTINUE_STATE_DIR /
# PI_CONTINUE_WAIT_SECONDS / PI_CONTINUE_MIN_PROGRESS_SECONDS /
# PI_CONTINUE_NO_PROGRESS_LIMIT seams, asserting productive-cycle budget
# counting across quota hits (no-progress re-parks, the never-reset
# bound, and the wall-time fallback included), cycle-differentiated
# prompts and the completion-claim challenge cycle, pi's first-use
# session-warning classification, truncation as a non-quota stop,
# --session-id lockstep, park math, per-session retention, the --follow
# launch-plus-tail contract, and flag passthrough isolation, with no
# model injection anywhere. When the real pi is on PATH, PI_VALUE_FLAGS
# is additionally pinned against live `pi --help` and the declared flag
# tables checked against the documented set (the -n carve-out excepted);
# without it those checks skip.
#
# Hermetic: the fake pi substitutes via PI_CONTINUE_BIN, state lives
# under mktemp via PI_CONTINUE_STATE_DIR, parks are pinned via
# PI_CONTINUE_WAIT_SECONDS; no network, no provider calls, and no real
# ~/.local/share/pi writes. Detached scenarios assert on engine.log and
# the fake's recorded state rather than launcher stdout, and the fake's
# success modes sleep briefly so a ride's engine outlives the launcher's
# readiness poll grid; both per the launch-race guidance from the
# script's unit report.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PC="$REPO_ROOT/shell/bin/pi-continue"

source "$REPO_ROOT/tests/lib/harness.sh"

# Prompt constants extracted from the engine under test, so assertions
# track the source instead of restating it; the marker rides to the fake
# through the environment. There is no model constant: the supervisor
# never injects a model.
complete_marker="$(sed -n "s/^COMPLETE_MARKER='\(.*\)'$/\1/p" "$PC")"
marker_instruction="$(sed -n "s/^MARKER_INSTRUCTION='\(.*\)'$/\1/p" "$PC")"
default_prompt="$(sed -n "s/^DEFAULT_PROMPT='\(.*\)'$/\1/p" "$PC")"
resume_note="$(sed -n "s/^RESUME_NOTE='\(.*\)'$/\1/p" "$PC")"
resume_prompt="${resume_note} ${marker_instruction}"
challenge_prompt="$(sed -n "s/^CHALLENGE_PROMPT='\(.*\)'$/\1/p" "$PC")"
export PI_FAKE_MARKER="$complete_marker"
with_marker() { # first-line; the cycle-1 ride prompt with the marker line appended
	printf '%s\n%s' "$1" "$marker_instruction"
}

refuse() { # label; rest is the command to attempt
	local label="$1"; shift
	if pc "$@" </dev/null >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi
}

refuse_rc() { # expected_status label; rest is the command to attempt
	local want="$1" label="$2"; shift 2
	local rc=0
	pc "$@" </dev/null >/dev/null 2>&1 || rc=$?
	assert_eq "$label" "$want" "$rc"
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

FAKE="$ROOT/fake-pi"
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
# Recorder fake: appends this invocation's argv to $FAKE_STATE/args
# (tab-separated, one record per invocation; a prompt carrying the
# appended marker line spans physical lines, and every record starts
# with a tab), counts calls in $FAKE_STATE/count, and follows
# $FAKE_STATE/plan line N for call N. pi print-mode shapes: a failed
# call prints its error to stderr and nothing to stdout, a successful
# one prints final-message text to stdout, and there is no banner.
# quota (immediate quota fail: the dead-window shape where wall time is
#   all the classifier has),
# productive (one stdout content line, then the quota fail; real pi
#   cannot produce this shape, a failed call prints no stdout, it
#   exists to pin the content half of made_progress),
# slowquota (a FAKE_SLOW wait, then the quota fail: the real-pi primary
#   productive signal, elapsed time over the floor),
# deadwindow (pi's real first-use session warning on stderr, then the
#   quota fail, empty stdout: the dead-window session 1 shape),
# warning429 (only the warning line, its session id carrying a
#   non-digit-bounded 429, exit 1: the id must never read as quota),
# deadwindow-slow (the warning, a FAKE_SLOW wait, then the quota fail:
#   the elapsed-floor productive control with the warning present),
# complete (a work line, a short FAKE_OK_SLEEP, then the completion
#   marker as the final line),
# complete_ansi (the marker wrapped in ANSI escape sequences),
# complete_quota (quota text with the marker still last, so the
#   completion claim has to fire before quota classification),
# marker_mid_quota (a bare marker line mid-output, which must not stop
#   the ride), truncation (partial stdout, pi's exact truncation stderr
#   string, exit 1), fail, slow, or ok by default. The success modes
#   sleep FAKE_OK_SLEEP so the engine's armed-pidfile window outlasts
#   the launcher's 0.1s readiness poll grid.
n=$(( $(cat "$FAKE_STATE/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAKE_STATE/count"
{ printf '\t%s' "$@"; printf '\n'; } >>"$FAKE_STATE/args"
mode="$(sed -n "${n}p" "$FAKE_STATE/plan" 2>/dev/null)"
quota_fail() { echo "Error 429: rate limit exceeded" >&2; exit 1; }
session_warning() { printf 'Warning: No project session found with id %s; creating a new session with that id.\n' "$1"; }
case "${mode:-ok}" in
	quota)           quota_fail ;;
	productive)      echo "worked through the todo list"; quota_fail ;;
	slowquota)       sleep "${FAKE_SLOW:-5}"; quota_fail ;;
	deadwindow)      session_warning "pi-continue-20261022T010402-$$" >&2; quota_fail ;;
	warning429)      session_warning "pi-continue-20261022T010402-429" >&2; exit 1 ;;
	deadwindow-slow) session_warning "pi-continue-20261022T010402-$$" >&2; sleep "${FAKE_SLOW:-5}"; quota_fail ;;
	complete)        echo "wrapped up the remaining work"; sleep "${FAKE_OK_SLEEP:-0.3}"; printf '%s\n' "$PI_FAKE_MARKER"; exit 0 ;;
	complete_ansi)   printf '\e[32m%s\e[0m\n' "$PI_FAKE_MARKER"; exit 0 ;;
	complete_quota)  echo "Error 429: rate limit exceeded"; printf '%s\n' "$PI_FAKE_MARKER"; exit 1 ;;
	marker_mid_quota) printf '%s\n' "$PI_FAKE_MARKER"; echo "more work continues past the mention"; quota_fail ;;
	truncation)      echo "partial answer text, cut off mid-sentence"; echo "Response was truncated: the model reached its output token limit." >&2; exit 1 ;;
	fail)            echo "fatal: unrecoverable failure" >&2; exit 3 ;;
	slow)            echo "slow line one"; sleep "${FAKE_SLOW:-5}"; echo "slow line two"; exit 0 ;;
	*)               echo "fake session $n start"; sleep "${FAKE_OK_SLEEP:-0.3}"; echo "fake session $n done"; exit 0 ;;
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

PC_ENV=()
pc() { # pi-continue under test, seams wired for the current scenario
	env PI_CONTINUE_BIN="$FAKE" PI_CONTINUE_STATE_DIR="$STATE" ${PC_ENV[@]+"${PC_ENV[@]}"} "$PC" "$@"
}

# The engine is a zsh script; a parse slip would surface as confusing
# per-test failures long before their cause, so pin the syntax upfront.
# stderr is captured for the failure message; stdout stays clean either way.
zsh_parse_err="$(zsh -n "$PC" 2>&1 >/dev/null)" \
	&& ok "the script parses clean as zsh" \
	|| bad "the script parses clean as zsh ($zsh_parse_err)"

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
ride_id() { cat "$STATE/session.id" 2>/dev/null; }
invocation_args() { # n; prints the nth recorded invocation, one arg per line
	# a ride prompt carries the appended marker line, so a record spans
	# physical lines; records are delimited by their leading tab
	awk -v n="$1" '/^\t/{rec++} rec==n' "$FAKE_STATE/args" \
		| sed 's/^\t//' | tr '\t' '\n' | sed '/^$/d'
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
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
out="$(pc run -n 3 ship the feature)"
PC_ENV=()
assert_contains "launcher detaches immediately" "$out" "detached (pid"
wait_for 15 engine_idle && ok "engine rides two quota windows and finishes" \
	|| bad "engine rides two quota windows and finishes"
assert_eq "three sessions ran under a three-session budget" "3" "$(fake_calls)"
assert_contains "the engine log names each invoking pi run" "$(cat "$STATE/engine.log")" \
	"session 1: invoking pi"
assert_contains "engine log records the clean completion" "$(cat "$STATE/engine.log")" \
	"session 3: run completed cleanly"
assert_contains "engine log records the PI_CONTINUE_WAIT_SECONDS park" "$(cat "$STATE/engine.log")" \
	"parking 0.5s"
assert_invocation "the final session resumes with only the resumption prompt" 3 \
	-p --session-id "$(ride_id)" -- "$resume_prompt"

fresh spent
printf 'productive\nproductive\nproductive\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run -n 2 keep going >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "budget-spent run parks once then quits" \
	|| bad "budget-spent run parks once then quits"
assert_eq "budget spent stops at the second hit" "2" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "engine log records the spent budget" "$log" "budget spent"
assert_contains "the quit fires on the Nth productive hit" "$log" \
	"productive quota hit 2 of budget 2; budget spent, quitting"

fresh hardfail
printf 'fail\n' >"$FAKE_STATE/plan"
pc run one shot only >/dev/null 2>&1
wait_for 10 grep -q "non-quota failure" "$STATE/engine.log" \
	&& ok "non-quota failure ends the run" || bad "non-quota failure ends the run"
assert_eq "non-quota failure is not retried" "1" "$(fake_calls)"
assert_contains "engine log records the non-quota failure" "$(cat "$STATE/engine.log")" \
	"non-quota failure rc=3"

fresh oneshot
printf 'quota\n' >"$FAKE_STATE/plan"
pc in 0 --fork --provider openai do it >/dev/null 2>&1
wait_for 10 grep -q "one-shot: invoking pi" "$STATE/engine.log" \
	&& ok "one-shot reaches its single invocation" || bad "one-shot reaches its single invocation"
wait_for 10 grep -q "one-shot: quota hit" "$STATE/engine.log" \
	&& ok "one-shot completes its single run" || bad "one-shot completes its single run"
assert_invocation "one-shot forwards pi flags after its duration" 1 \
	-p --session-id "$(ride_id)" --fork --provider openai -- "do it"
assert_contains "the one-shot engine log names its invoking pi run" \
	"$(cat "$STATE/engine.log")" "one-shot: invoking pi"
assert_contains "one-shot quota hit is not retried" "$(cat "$STATE/engine.log")" \
	"one-shot: quota hit"
[[ -f "$STATE/last.1.out" ]] && ok "one-shot run retains its session output" \
	|| bad "one-shot run retains its session output"
assert_contains "one-shot output opens with the timestamped session stamp" \
	"$(head -n 1 "$STATE/last.1.out")" "pi-continue: invoking pi (session 1, "

echo "== the first-use session warning classifies as metadata (real-pi shape) =="
fresh deadwindow
# pi prints its first-use session warning on session 1, merged into the
# retained output; the warning line alone must classify as no progress,
# never as productive content, or a dead-window launch burns budget
printf 'deadwindow\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run -n 1 dead window ride >/dev/null 2>&1
PC_ENV=()
wait_for 10 grep -q "no-progress quota hit 1 of" "$STATE/engine.log" \
	&& ok "a dead-window session 1 re-parks instead of reading productive" \
	|| bad "a dead-window session 1 re-parks instead of reading productive"
log="$(cat "$STATE/engine.log")"
assert_contains "the dead-window hit consumed no budget unit" "$log" \
	"no-progress quota hit 1 of 90 consecutive; no budget consumed"
assert_not_contains "the warning shape never reads as a productive hit" "$log" "productive quota hit"
assert_not_contains "a one-cycle budget is never burned on the warning shape" "$log" "budget spent"
wait_for 10 engine_idle && ok "the ride continues past the dead window to a clean finish" \
	|| bad "the ride continues past the dead window to a clean finish"
assert_eq "the retry after the dead window ran the second session" "2" "$(fake_calls)"
assert_contains "the real warning shape reached the retained session output" \
	"$(cat "$STATE/last.1.out")" "Warning: No project session found with id "

fresh warning429
# the warning line embeds the session id; a 429 inside that id must
# never read as a quota event, or the metadata line would keep the ride
# cycling instead of stopping on the honest non-quota failure
printf 'warning429\n' >"$FAKE_STATE/plan"
pc run warning id ride >/dev/null 2>&1
wait_for 10 grep -q "non-quota failure" "$STATE/engine.log" \
	&& ok "a 429 in the warning's session id never reads as quota" \
	|| bad "a 429 in the warning's session id never reads as quota"
log="$(cat "$STATE/engine.log")"
assert_contains "the warning-only session stops as a non-quota failure" "$log" \
	"non-quota failure rc=1; not retrying"
assert_not_contains "the warning id never starts a no-progress streak" "$log" "no-progress quota hit"
assert_not_contains "the warning id never counts a productive cycle" "$log" "productive quota hit"
assert_eq "the ride stopped after one invocation" "1" "$(fake_calls)"

fresh deadwindow_slow
# the warning present plus a slow child: the elapsed-floor signal must
# survive the warning exclusion, so a session that worked and then hit
# quota still counts productive (the F1 fix must not overcorrect)
printf 'deadwindow-slow\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 FAKE_SLOW=1.2 PI_CONTINUE_MIN_PROGRESS_SECONDS=1)
pc run -n 2 slow dead window >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "the slow warning ride finishes" || bad "the slow warning ride finishes"
log="$(cat "$STATE/engine.log")"
assert_contains "the elapsed floor classifies the slow warning session productive" "$log" \
	"productive quota hit 1 of budget 2; parking 0.5s"
assert_contains "the ride finished cleanly after the fallback hit" "$log" "run completed cleanly"

echo "== no-progress re-parks and the never-reset bound =="
fresh budget_free
# productive cycles count toward the budget while a no-progress attempt
# leaves it untouched: the quit fires on the Nth productive hit, not the
# Nth invocation
printf 'quota\nproductive\nproductive\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 PI_CONTINUE_NO_PROGRESS_LIMIT=3)
pc run -n 2 try again >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a no-progress fail followed by two productive hits ends on the budget" \
	|| bad "a no-progress fail followed by two productive hits ends on the budget"
assert_eq "the no-progress attempt ran but spent no budget unit" "3" "$(fake_calls)"
assert_contains "the fake's stderr quota error reached the retained session output" \
	"$(cat "$STATE/last.1.out")" "Error 429: rate limit exceeded"
log="$(cat "$STATE/engine.log")"
assert_contains "the quota-error prologue alone classifies no progress" "$log" \
	"no-progress quota hit 1 of 3 consecutive; no budget consumed"
assert_contains "the budget still quits on the second productive hit" "$log" \
	"productive quota hit 2 of budget 2; budget spent, quitting"

fresh repark
# an immediate quota fail right after a park means the reset never took:
# the engine re-parks on the same math without consuming budget and can
# still finish cleanly later
printf 'quota\nquota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run -n 2 keep trying >/dev/null 2>&1
PC_ENV=()
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
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 PI_CONTINUE_NO_PROGRESS_LIMIT=3)
pc run -n 5 still trying >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "three consecutive no-progress attempts end the run" \
	|| bad "three consecutive no-progress attempts end the run"
assert_eq "the bound quit stops after the third attempt" "3" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the engine reports the limit never reset" "$log" \
	"no-progress quota hit 3 consecutive; limit never reset, quitting"
assert_not_contains "the bound quit stays distinct from budget exhaustion" "$log" "budget spent"
assert_eq "the persisted streak reads three after the bound quit" "3" \
	"$(cat "$STATE/failed.count")"

fresh boundreset
# a productive session resets the consecutive count, so no-progress
# streaks on either side of it neither quit the run nor spend budget
printf 'quota\nproductive\nquota\nquota\nproductive\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 PI_CONTINUE_NO_PROGRESS_LIMIT=3)
pc run -n 2 push through >/dev/null 2>&1
PC_ENV=()
wait_for 20 engine_idle && ok "a productive session lets the run survive later no-progress streaks" \
	|| bad "a productive session lets the run survive later no-progress streaks"
assert_eq "the run reaches its fifth invocation before the budget quits" "5" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the consecutive count restarts after a productive session" "$log" \
	"no-progress quota hit 2 of 3 consecutive; no budget consumed"
assert_contains "the productive cycles still spend the budget" "$log" \
	"productive quota hit 2 of budget 2; budget spent, quitting"
assert_not_contains "the reset kept the bound from firing" "$log" "limit never reset"
assert_eq "the persisted streak reads zero after the productive budget quit" "0" \
	"$(cat "$STATE/failed.count")"

echo "== cycle-differentiated prompts and the completion marker =="
fresh prompts
# cycle 1 sends the caller's words plus the appended marker line, cycles
# 2 and up only the resumption prompt; the plan ends ok so the ride
# stops cleanly after three invocations
printf 'productive\nproductive\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run ship the feature >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a caller-prompt ride completes" \
	|| bad "a caller-prompt ride completes"
assert_invocation "cycle 1 sends the caller's prompt with the marker line appended" 1 \
	-p --session-id "$(ride_id)" -- "$(with_marker "ship the feature")"
assert_invocation "cycle 2 re-sends only the resumption prompt" 2 \
	-p --session-id "$(ride_id)" -- "$resume_prompt"
assert_invocation "cycle 3 still never sees the caller's original prompt" 3 \
	-p --session-id "$(ride_id)" -- "$resume_prompt"

fresh no_progress_repeats_prompt
# a no-progress attempt spends no cycle, so the retry re-sends the
# caller's prompt: the model may never have consumed the words, and the
# resumption note would claim a window reset that never happened
printf 'quota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run ship it >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a ride past a no-progress attempt finishes" \
	|| bad "a ride past a no-progress attempt finishes"
assert_invocation "the no-progress retry re-sends the caller's prompt with the marker line" 2 \
	-p --session-id "$(ride_id)" -- "$(with_marker "ship it")"

fresh productive_switches_to_resume
# a genuinely productive cycle is what switches later invocations to the
# resumption note
printf 'productive\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run ship it >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a ride past a productive cycle finishes" \
	|| bad "a ride past a productive cycle finishes"
assert_invocation "the first productive cycle switches the next invocation to the resumption note" 2 \
	-p --session-id "$(ride_id)" -- "$resume_prompt"

fresh marker_in_prompt
# the append skips when the caller's own words already carry the marker
printf 'ok\n' >"$FAKE_STATE/plan"
pc run "wrap up; end with $complete_marker when finished" >/dev/null 2>&1
wait_for 10 engine_idle && ok "a self-marking prompt run completes" \
	|| bad "a self-marking prompt run completes"
assert_invocation "a caller prompt already carrying the marker is sent verbatim" 1 \
	-p --session-id "$(ride_id)" -- "wrap up; end with $complete_marker when finished"

fresh marker_last
# a first completion claim no longer stops the ride: it arms exactly one
# challenge session, and only the challenge's own marker ends it
printf 'complete\ncomplete\n' >"$FAKE_STATE/plan"
pc run finish the lot >/dev/null 2>&1
wait_for 10 engine_idle && ok "a confirming challenge ends the ride" \
	|| bad "a confirming challenge ends the ride"
assert_eq "the ride ended on the challenge, after two sessions" "2" "$(fake_calls)"
assert_invocation "the challenge session runs the enumeration prompt" 2 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
log="$(cat "$STATE/engine.log")"
assert_contains "the confirming stop carries the challenge-confirmed wording and the child's rc" "$log" \
	"session 2: work complete (PI-CONTINUE: COMPLETE, rc=0, challenge confirmed)"
assert_not_contains "no clean-exit line rides on a challenge-confirmed stop" "$log" "completed cleanly"

fresh marker_ansi
# ANSI escapes are stripped before the last-line comparison, so an
# ANSI-wrapped marker still read as the terminal line and still earns
# its challenge
printf 'complete_ansi\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run finish in color >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "an ANSI-wrapped marker still earns its challenge" \
	|| bad "an ANSI-wrapped marker still earns its challenge"
assert_contains "the wrapped marker read as the terminal line" "$(cat "$STATE/engine.log")" \
	"completion marker claimed; challenging the claim in session 2"

fresh marker_quota
# the marker check runs before quota classification: a session whose
# last line is the marker despite a quota fail still earns its
# challenge, and the confirming challenge never reaches the park logic
printf 'complete_quota\ncomplete\n' >"$FAKE_STATE/plan"
pc run finish through the hit >/dev/null 2>&1
wait_for 10 engine_idle && ok "a marker under a quota fail still earns its challenge" \
	|| bad "a marker under a quota fail still earns its challenge"
log="$(cat "$STATE/engine.log")"
assert_contains "the claim fired before quota classification" "$log" \
	"completion marker claimed; challenging the claim in session 2"
assert_not_contains "the quota hit never reached the park logic" "$log" "parking"

fresh marker_mid
# a bare marker line mid-output is a mention, not a stop: the ride
# continues, spends a productive cycle, and finishes cleanly
printf 'marker_mid_quota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run mention and keep going >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a mid-output marker mention does not stop the ride" \
	|| bad "a mid-output marker mention does not stop the ride"
assert_eq "the ride continued past the mention to a second session" "2" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the mention session spent a productive cycle" "$log" \
	"session 1: productive quota hit 1; unbounded ride continues"
assert_not_contains "no complete report for a mid-output mention" "$log" "work complete"

echo "== the challenge cycle: one challenge per completion claim =="
fresh challenge_first_claim
# the first marker never ends the ride: exactly one challenge session
# follows it, running the enumeration prompt, and the ride goes on
printf 'complete\nok\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run claim and get challenged >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "the ride continues past a challenged claim" \
	|| bad "the ride continues past a challenged claim"
assert_invocation "the first marker arms one challenge running the enumeration prompt" 2 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
assert_eq "exactly one challenge followed the first claim" "1" \
	"$(grep -c 'completion marker claimed' "$STATE/engine.log")"
assert_eq "the challenge counted no session beyond its own" "3" "$(fake_calls)"

fresh challenge_finds_work
# the challenge ends rc 0 without the marker: the model found remaining
# work, so the ride continues on the normal resumption prompt without a
# park; the park length stays pinned to prove the transition parks
# nothing
printf 'complete\nok\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run challenged with work left >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a work-finding challenge continues the ride without parking" \
	|| bad "a work-finding challenge continues the ride without parking"
assert_eq "the ride reached three sessions with no park in between" "3" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the work-finding challenge spent a productive cycle" "$log" \
	"session 2: productive challenge 1; unbounded ride continues; work found, continuing immediately with session 3"
assert_not_contains "the work-found transition parks nothing" "$log" "; parking "
assert_invocation "the session after a work-finding challenge resumes the normal cycle immediately" 3 \
	-p --session-id "$(ride_id)" -- "$resume_prompt"
assert_contains "the continued ride finished cleanly" "$log" "run completed cleanly"
assert_not_contains "work found is never read as completion" "$log" "work complete"

fresh challenge_budget
# the same work-found continuation under -n: the challenge's cycle still
# spends the budget and the budget quit still outranks the continuation;
# with no park length pinned the default 600s park would outlast the
# engine_idle wait, so a clean finish proves no park ran
printf 'complete\nok\nproductive\n' >"$FAKE_STATE/plan"
pc run -n 2 challenged on a budget >/dev/null 2>&1
wait_for 10 engine_idle && ok "a budgeted work-found challenge ride ends on the budget" \
	|| bad "a budgeted work-found challenge ride ends on the budget"
assert_eq "the budget quit stopped after the second productive cycle" "3" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the budgeted work-finding challenge logs the immediate continuation" "$log" \
	"session 2: productive challenge 1 of budget 2; work found, continuing immediately with session 3"
assert_contains "the budget quit still fires ahead of the continuation" "$log" \
	"session 3: productive quota hit 2 of budget 2; budget spent, quitting"
assert_not_contains "no park runs on the work-found transition at the default park length" "$log" "; parking "

fresh challenge_quota
# the challenge itself hits quota: existing parking rules apply
# unchanged, the quota hit with progress spends a cycle, and the ride
# goes on to a later confirmed completion; a progress-passing quota hit
# is classifiable content, so the claim's challenge clears and session
# 3 resumes the normal cycle
printf 'complete\nproductive\ncomplete\ncomplete\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run challenged through a window >/dev/null 2>&1
PC_ENV=()
wait_for 20 engine_idle && ok "a quota-hit challenge parks and the ride continues" \
	|| bad "a quota-hit challenge parks and the ride continues"
assert_invocation "the quota-hit challenge ran the enumeration prompt" 2 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
assert_invocation "the session after the progress-making quota challenge resumes the normal cycle" 3 \
	-p --session-id "$(ride_id)" -- "$resume_prompt"
log="$(cat "$STATE/engine.log")"
assert_contains "the challenge's quota hit keeps the existing parking rules" "$log" \
	"session 2: productive quota hit 1; unbounded ride continues"
assert_contains "the quota-hit challenge parked before resuming" "$log" "parking 0.5s"
assert_contains "the ride later ended on a confirmed completion" "$log" \
	"challenge confirmed"
assert_not_contains "the quota challenge never reported clean completion" "$log" \
	"completed cleanly"

fresh challenge_no_progress
# a quota fail that eats the challenge (no progress: the enumeration
# never reached the model) re-parks with the claim still challenged, so
# the retry re-asks the enumeration instead of dropping it; the claim
# is never taken for granted and the ride continues past the re-ask
printf 'complete\nquota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 PI_CONTINUE_NO_PROGRESS_LIMIT=5)
pc run claim challenged through a dead window >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a quota-eaten challenge re-parks with the claim still challenged" \
	|| bad "a quota-eaten challenge re-parks with the claim still challenged"
assert_invocation "the quota-eaten challenge ran the enumeration prompt" 2 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
assert_invocation "the retry after the quota-eaten challenge re-asks the enumeration" 3 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
log="$(cat "$STATE/engine.log")"
assert_contains "the quota-eaten challenge re-parked as no progress" "$log" \
	"session 2: no-progress quota hit 1 of 5 consecutive"
assert_contains "the ride ended cleanly only after the re-asked challenge" "$log" \
	"session 4: run completed cleanly"

fresh challenge_zeroes_streak
# a claim session is productive (marker content ends it, whatever the
# child's rc), so it zeroes the no-progress streak: the quota hit eating
# its challenge starts a fresh count instead of extending the pre-claim
# streak, and the never-reset bound does not fire early
printf 'quota\nquota\ncomplete\nquota\ncomplete\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 PI_CONTINUE_NO_PROGRESS_LIMIT=3)
pc run claim after a streak >/dev/null 2>&1
PC_ENV=()
wait_for 20 engine_idle && ok "a claim after no-progress hits restarts the streak" \
	|| bad "a claim after no-progress hits restarts the streak"
log="$(cat "$STATE/engine.log")"
assert_contains "the claim logged between the pre-claim streak and the post-claim hit" "$log" \
	"session 3: completion marker claimed; challenging the claim in session 4"
assert_contains "the post-claim quota hit re-parks on a fresh streak of one" "$log" \
	"session 4: no-progress quota hit 1 of 3 consecutive"
assert_not_contains "the never-reset bound never fired on the carried streak" "$log" \
	"limit never reset"
assert_contains "the ride still ended on a confirmed completion" "$log" \
	"challenge confirmed"
assert_eq "the confirmed stop was the fifth session" "5" "$(fake_calls)"

fresh challenge_confirms_under_quota
# the challenge ends with the marker despite a quota fail: the claim
# confirms, and the confirmed stop carries the challenge's non-zero rc
printf 'complete\ncomplete_quota\n' >"$FAKE_STATE/plan"
pc run claim confirmed through a hit >/dev/null 2>&1
wait_for 10 engine_idle && ok "a challenge ending in the marker under a quota fail ends the ride" \
	|| bad "a challenge ending in the marker under a quota fail ends the ride"
assert_invocation "the confirming challenge ran the enumeration prompt" 2 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
assert_contains "the confirmed stop carries the challenge's non-zero rc" \
	"$(cat "$STATE/engine.log")" \
	"work complete (PI-CONTINUE: COMPLETE, rc=1, challenge confirmed)"

fresh challenge_reset
# challenged resets on any session that does not end in the marker, so
# a second fresh claim earns a second challenge
printf 'complete\nok\ncomplete\ncomplete\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run claim, challenged, claim again >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a second fresh claim earns a second challenge" \
	|| bad "a second fresh claim earns a second challenge"
assert_eq "both fresh claims were challenged" "2" \
	"$(grep -c 'completion marker claimed' "$STATE/engine.log")"
assert_invocation "the first claim's challenge ran the enumeration prompt" 2 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
assert_invocation "the second claim's challenge ran the enumeration prompt again" 4 \
	-p --session-id "$(ride_id)" -- "$challenge_prompt"
assert_eq "the second challenge confirmed and ended the ride" "4" "$(fake_calls)"
assert_contains "the ride ended on the second challenge's confirmation" \
	"$(cat "$STATE/engine.log")" "challenge confirmed"

echo "== unbounded ride =="
fresh unbounded
# no -n: the ride outlasts any default and ends on a challenge-confirmed
# marker, never on a budget report
printf 'productive\nproductive\nproductive\ncomplete\ncomplete\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
out="$(pc run ride it out)"
PC_ENV=()
wait_for 20 engine_idle && ok "the unbounded ride ends on the confirmed marker" \
	|| bad "the unbounded ride ends on the confirmed marker"
assert_contains "the launcher detached the unbounded engine" "$out" "detached (pid"
assert_eq "the ride outlasted three productive windows before the marker" "5" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the engine logs the ride as unbounded, until the marker" "$log" \
	"unbounded, until PI-CONTINUE: COMPLETE"
assert_contains "the ride quits with the confirmed complete report, not a budget line" "$log" \
	"work complete (PI-CONTINUE: COMPLETE, rc=0, challenge confirmed)"
assert_not_contains "an unbounded ride never reports a spent budget" "$log" "budget spent"
assert_contains "productive hits on an unbounded ride just re-park" "$log" \
	"unbounded ride continues"

fresh unbounded_neverreset
# the never-reset bound stays active without -n
printf 'quota\nquota\nquota\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 PI_CONTINUE_NO_PROGRESS_LIMIT=3)
pc run ride a dead window >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "an unbounded ride still honors the never-reset bound" \
	|| bad "an unbounded ride still honors the never-reset bound"
assert_eq "the bound quit stopped after the third attempt" "3" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the never-reset report fires on an unbounded ride" "$log" \
	"no-progress quota hit 3 consecutive; limit never reset, quitting"
assert_not_contains "the unbounded quit stays distinct from budget exhaustion" "$log" "budget spent"
assert_eq "the unbounded bound quit leaves the streak persisted" "3" \
	"$(cat "$STATE/failed.count")"

echo "== wall-time fallback for content-less quota hits =="
fresh fallback_up
# the time half of the conjunction: a quota fail whose whole output
# matched the filter still counts as productive once it outlasted the
# floor, which PI_CONTINUE_MIN_PROGRESS_SECONDS pins low enough to test
printf 'slowquota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 FAKE_SLOW=1.2 PI_CONTINUE_MIN_PROGRESS_SECONDS=1)
pc run -n 2 grind it out >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a slow quota fail at or over the floor counts as productive" \
	|| bad "a slow quota fail at or over the floor counts as productive"
assert_eq "the slow fail ran once and the run resumed past it" "2" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the at-floor slow fail spent a productive cycle" "$log" \
	"productive quota hit 1 of budget 2; parking 0.5s"
assert_contains "the run finished cleanly after the fallback hit" "$log" "run completed cleanly"

fresh fallback_under
# under the floor the same fail is no-progress: the engine re-parks
# without spending budget and still finishes cleanly
printf 'slowquota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 FAKE_SLOW=1.2 PI_CONTINUE_MIN_PROGRESS_SECONDS=5 PI_CONTINUE_NO_PROGRESS_LIMIT=3)
pc run -n 2 slow start >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "a slow quota fail under the floor is no progress" \
	|| bad "a slow quota fail under the floor is no progress"
assert_eq "the sub-floor fail re-parked instead of spending budget" "2" "$(fake_calls)"
log="$(cat "$STATE/engine.log")"
assert_contains "the sub-floor fail logged a no-progress re-park" "$log" \
	"no-progress quota hit 1 of 3 consecutive; no budget consumed"
assert_not_contains "no productive cycle was recorded" "$log" "productive quota hit"

echo "== truncation stops the ride as a non-quota failure =="
fresh truncation
# pi exits 1 with the truncation string when a session hits the output
# token limit; no quota term matches, so the ride must stop after one
# invocation with the partial output retained
printf 'truncation\n' >"$FAKE_STATE/plan"
pc run partial output ride >/dev/null 2>&1
wait_for 10 grep -q "non-quota failure rc=1" "$STATE/engine.log" \
	&& ok "a truncated session stops the ride as a non-quota failure" \
	|| bad "a truncated session stops the ride as a non-quota failure"
log="$(cat "$STATE/engine.log")"
assert_contains "the truncation stop names the child's rc" "$log" \
	"session 1: non-quota failure rc=1; not retrying"
assert_not_contains "truncation never starts a no-progress streak" "$log" "no-progress quota hit"
assert_not_contains "truncation never counts a productive cycle" "$log" "productive quota hit"
assert_eq "the truncated session is not retried" "1" "$(fake_calls)"
assert_contains "the partial stdout is retained" "$(cat "$STATE/last.1.out")" \
	"partial answer text, cut off mid-sentence"
assert_contains "the truncation stderr string is retained in the same file" \
	"$(cat "$STATE/last.1.out")" \
	"Response was truncated: the model reached its output token limit."

echo "== park math =="
park_default="$(sed -n 's/^PARK_SECONDS=\([0-9]\+\).*/\1/p' "$PC")"
limit_default="$(sed -n 's/^NO_PROGRESS_LIMIT="${PI_CONTINUE_NO_PROGRESS_LIMIT:-\([0-9]\+\)}"$/\1/p' "$PC")"
min_progress_default="$(sed -n 's/^MIN_PROGRESS_SECONDS="${PI_CONTINUE_MIN_PROGRESS_SECONDS:-\([0-9]\+\)}"$/\1/p' "$PC")"
assert_eq "PARK_SECONDS defaults to 600" "600" "$park_default"
assert_eq "NO_PROGRESS_LIMIT defaults to 90" "90" "$limit_default"
assert_eq "MIN_PROGRESS_SECONDS defaults to 20" "20" "$min_progress_default"
epoch_fn="$(awk '/^epoch_of\(\)/{f=1} f{print} f&&/^}/{exit}' "$PC")"
park_fn="$(awk '/^park_seconds\(\)/{f=1} f{print} f&&/^}/{exit}' "$PC")"
zsh_park() {
	env "$@" zsh -c "PARK_SECONDS=$park_default
$epoch_fn
$park_fn
park_seconds"
}
assert_eq "PI_CONTINUE_WAIT_SECONDS pins the park length" "7" "$(zsh_park PI_CONTINUE_WAIT_SECONDS=7)"
assert_eq "no override parks the observed default" "$park_default" \
	"$(zsh_park -u PI_CONTINUE_WAIT_SECONDS -u PI_CONTINUE_WAIT_UNTIL)"
assert_eq "a past PI_CONTINUE_WAIT_UNTIL floors to a minute" "60" \
	"$(zsh_park PI_CONTINUE_WAIT_UNTIL=yesterday)"
future_park="$(zsh_park PI_CONTINUE_WAIT_UNTIL='+90 seconds')"
if [[ "$future_park" =~ ^[0-9]+$ ]] && (( future_park >= 85 && future_park <= 90 )); then
	ok "a future PI_CONTINUE_WAIT_UNTIL parks exactly the remaining seconds ($future_park)"
else
	bad "a future PI_CONTINUE_WAIT_UNTIL parks exactly the remaining seconds (got [$future_park])"
fi
if zsh_park PI_CONTINUE_WAIT_UNTIL='not a time' >/dev/null 2>&1; then
	bad "an unparseable PI_CONTINUE_WAIT_UNTIL fails"
else
	ok "an unparseable PI_CONTINUE_WAIT_UNTIL fails"
fi

echo "== session-start stamp and warning classification =="
stamp_lib="$ROOT/stamp-lib.zsh"
{
	printf 'TAIL_LINES=%s\n' "$(sed -n 's/^TAIL_LINES=\([0-9]\+\)$/\1/p' "$PC")"
	printf "QUOTA_REGEX='%s'\n" "$(sed -n "s/^QUOTA_REGEX='\(.*\)'$/\1/p" "$PC")"
	printf "SESSION_START_REGEX='%s'\n" "$(sed -n "s/^SESSION_START_REGEX='\(.*\)'$/\1/p" "$PC")"
	printf "SESSION_WARNING_REGEX='%s'\n" "$(sed -n "s/^SESSION_WARNING_REGEX='\(.*\)'$/\1/p" "$PC")"
	printf 'ANSI_ESC=%s\n' "$(sed -n 's/^ANSI_ESC=\(.*\)$/\1/p' "$PC")"
	printf "COMPLETE_MARKER='%s'\n" "$complete_marker"
	printf 'MIN_PROGRESS_SECONDS=%s\n' "$min_progress_default"
	for fn in looks_like_quota made_progress session_completed; do
		awk -v fn="$fn" '$0 ~ "^" fn "\\(\\)" {f=1} f{print} f && /^}/{exit}' "$PC"
	done
} >"$stamp_lib"
stamp_probe() { # file elapsed; prints quota/progress/complete flags
	STAMP_PROBE_FILE="$1" STAMP_PROBE_ELAPSED="$2" STAMP_LIB="$stamp_lib" zsh -c '
. "$STAMP_LIB"
if looks_like_quota "$STAMP_PROBE_FILE"; then q=1; else q=0; fi
if made_progress "$STAMP_PROBE_FILE" "$STAMP_PROBE_ELAPSED"; then p=1; else p=0; fi
if session_completed "$STAMP_PROBE_FILE"; then c=1; else c=0; fi
printf "quota:%s progress:%s complete:%s" "$q" "$p" "$c"'
}
stamp_dir="$ROOT/stamp"
mkdir -p "$stamp_dir"
printf 'pi-continue: invoking pi (session 429, 2026-01-01T00:00:00+00:00)\n' \
	>"$stamp_dir/only"
assert_eq "a lone session-429 stamp is neither quota nor progress" \
	"quota:0 progress:0 complete:0" "$(stamp_probe "$stamp_dir/only" 0)"
printf 'pi-continue: invoking pi (session 7, 2026-01-01T00:00:00+00:00)\nError 429: rate limit exceeded\n' \
	>"$stamp_dir/quota"
assert_eq "the stamp never masks a real quota signal" \
	"quota:1 progress:0 complete:0" "$(stamp_probe "$stamp_dir/quota" 0)"
printf 'pi-continue: invoking pi (session 7, 2026-01-01T00:00:00+00:00)\nworked through the todo list\n' \
	>"$stamp_dir/plain"
assert_eq "a plain text line past the stamp is progress" \
	"quota:0 progress:1 complete:0" "$(stamp_probe "$stamp_dir/plain" 0)"
printf 'pi-continue: invoking pi (session 7, 2026-01-01T00:00:00+00:00)\nwrapped up the remaining work\n%s\n' \
	"$complete_marker" >"$stamp_dir/marker"
assert_eq "the stamp never breaks marker detection" \
	"quota:0 progress:1 complete:1" "$(stamp_probe "$stamp_dir/marker" 0)"
printf '%s\n' "Warning: No project session found with id pi-continue-20261022T010402-5321; creating a new session with that id." \
	>"$stamp_dir/warn_plain"
assert_eq "the first-use session warning alone is neither quota nor progress" \
	"quota:0 progress:0 complete:0" "$(stamp_probe "$stamp_dir/warn_plain" 0)"
printf '%s\n' "Warning: No project session found with id pi-continue-20261022T010402-429; creating a new session with that id." \
	>"$stamp_dir/warn_429"
assert_eq "a 429 inside the warning's session id is neither quota nor progress" \
	"quota:0 progress:0 complete:0" "$(stamp_probe "$stamp_dir/warn_429" 0)"
# The r2-documented residual edge: looks_like_quota does not ANSI-strip
# before its exclusion, so a colored warning with a non-digit-bounded 429
# in the id reads as quota there, while made_progress strips first and
# stays immune. This pins the documented behavior; a future ANSI strip in
# looks_like_quota flips it deliberately.
printf '\e[31mWarning: No project session found with id pi-continue-20261022T010402-429; creating a new session with that id.\e[0m\n' \
	>"$stamp_dir/warn_color"
assert_eq "a colored 429-id warning reads as quota pre-strip (documented edge), never as progress" \
	"quota:1 progress:0 complete:0" "$(stamp_probe "$stamp_dir/warn_color" 0)"
printf '\e[31mWarning: No project session found with id pi-continue-20261022T010402-429; creating a new session with that id.\e[0m\nError 429: rate limit exceeded\n' \
	>"$stamp_dir/warn_color_slow"
assert_eq "the colored warning never blocks the elapsed-floor productive signal in made_progress" \
	"quota:1 progress:1 complete:0" "$(stamp_probe "$stamp_dir/warn_color_slow" "$min_progress_default")"

echo "== failed-run counter =="
fresh failedcount
# two no-progress attempts, a productive cycle, then one more
# no-progress, then a clean finish: the persisted count mirrors only the
# consecutive no-progress streak, so the productive session zeroes it
# mid-ride and the next attempt starts the streak over at one
printf 'quota\nquota\nproductive\nquota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5 PI_CONTINUE_NO_PROGRESS_LIMIT=5)
pc run -n 2 count the failures >/dev/null 2>&1
PC_ENV=()
wait_for 20 engine_idle && ok "a mixed ride with no-progress attempts finishes on the budget" \
	|| bad "a mixed ride with no-progress attempts finishes on the budget"
log="$(cat "$STATE/engine.log")"
assert_contains "the post-reset attempt starts the streak over at one of the limit" "$log" \
	"session 4: no-progress quota hit 1 of 5 consecutive"
assert_not_contains "no cumulative failed total rides anywhere in the log" "$log" "(failed total"
assert_eq "the persisted streak reads zero after the clean finish" "0" \
	"$(cat "$STATE/failed.count")"
st="$(pc status)"
assert_contains "idle status still reports the reset failed count" "$st" "failed runs: 0"

fresh failedstatus
# parked mid-ride behind no-progress attempts: status must show the
# live streak while the engine still runs
printf 'quota\nquota\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=3 PI_CONTINUE_NO_PROGRESS_LIMIT=5)
pc run -n 1 stall and watch >/dev/null 2>&1
PC_ENV=()
wait_for 15 grep -q "no-progress quota hit 2" "$STATE/engine.log" \
	&& ok "the ride parks behind two no-progress attempts" \
	|| bad "the ride parks behind two no-progress attempts"
st="$(pc status)"
assert_contains "status names the running engine" "$st" "running (pid"
assert_contains "running status reports the live failed streak" "$st" "failed runs: 2"
assert_eq "the persisted count reads two mid-ride" "2" "$(cat "$STATE/failed.count")"
pc stop >/dev/null 2>&1
wait_for 5 engine_idle && ok "the stalled ride stops on request" \
	|| bad "the stalled ride stops on request"

fresh failedrestart
# a fresh run zeroes the stale count from an earlier killed ride
printf 'ok\n' >"$FAKE_STATE/plan"
printf '%s\n' 7 >"$STATE/failed.count"
pc run reopen cleanly >/dev/null 2>&1
wait_for 10 engine_idle && ok "the reopening run completes" \
	|| bad "the reopening run completes"
assert_eq "the fresh start zeroed the stale failed count" "0" \
	"$(cat "$STATE/failed.count")"

echo "== per-session retention =="
fresh retain
printf 'productive\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=2)
pc run -n 2 keep going >/dev/null 2>&1
PC_ENV=()
# waiting on the fake's stderr line proves the merged 2>&1 stream, not
# just stdout, lands live in last.out through the multios tee
wait_for 10 grep -q "Error 429: rate limit exceeded" "$STATE/last.out" \
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
assert_contains "retained session 1 opens with its timestamped start stamp" \
	"$(head -n 1 "$STATE/last.1.out")" "pi-continue: invoking pi (session 1, "
stamp_line="$(head -n 1 "$STATE/last.2.out")"
assert_contains "retained session 2 opens with its own session stamp" \
	"$stamp_line" "pi-continue: invoking pi (session 2, "
if [[ "$stamp_line" =~ ^pi-continue:\ invoking\ pi\ \(session\ 2,\ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
	ok "the session stamp carries an ISO-8601 timestamp"
else
	bad "the session stamp carries an ISO-8601 timestamp (got [$stamp_line])"
fi
st="$(pc status)"
assert_contains "status lists the retained outputs" "$st" \
	"retained session output: last.1.out last.2.out"
clean_out="$(pc clean)"
assert_contains "clean reports the wiped state" "$clean_out" "cleaned"
[[ ! -d "$STATE" ]] && ok "clean removes the retained set with the state dir" \
	|| bad "clean removes the retained set with the state dir"

fresh prune
: >"$STATE/last.2.out"
pc run -n 1 fresh start >/dev/null 2>&1
wait_for 10 engine_idle && ok "prune-probe run completes" || bad "prune-probe run completes"
st="$(pc status)"
assert_contains "status presents the new run's session" "$st" "retained session output: last.1.out"
assert_not_contains "a stale longer run's sessions are pruned at start" "$st" "last.2.out"
[[ ! -f "$STATE/last.2.out" ]] && ok "the stale last.2.out is gone from the state dir" \
	|| bad "the stale last.2.out is gone from the state dir"

echo "== session-id lockstep =="
fresh lockstep
# one session id per ride: every invocation of a ride passes the same
# --session-id, it is persisted in session.id, it matches pi's
# documented id pattern, and the flagless ride's first invocation is
# exactly -p --session-id <id> -- <prompt>
printf 'productive\nok\n' >"$FAKE_STATE/plan"
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=0.5)
pc run -n 2 lockstep ride >/dev/null 2>&1
PC_ENV=()
wait_for 15 engine_idle && ok "the lockstep ride finishes" || bad "the lockstep ride finishes"
ride="$(ride_id)"
if [[ "$ride" =~ ^pi-continue-[0-9]{8}T[0-9]{6}-[0-9]+$ ]]; then
	ok "the ride id matches pi's documented session id pattern"
else
	bad "the ride id matches pi's documented session id pattern (got [$ride])"
fi
assert_eq "every invocation of the ride carried one session id" "$ride" \
	"$(awk -F'\t' '{for (i = 1; i <= NF; i++) if ($i == "--session-id") { print $(i+1); break }}' "$FAKE_STATE/args" | sort -u)"
assert_invocation "the first invocation is exactly -p --session-id <id> -- <prompt>" 1 \
	-p --session-id "$ride" -- "$(with_marker "lockstep ride")"
st="$(pc status)"
assert_contains "status shows the ride's session id" "$st" "pi-continue: session id: $ride"

echo "== run --follow: consumed flag, Ctrl-C kills the follower only =="
fresh follow
printf 'slow\n' >"$FAKE_STATE/plan"
follow_out="$ROOT/follow/follow.out"
if ((${#reset_int[@]})); then
	"${reset_int[@]}" env PI_CONTINUE_BIN="$FAKE" PI_CONTINUE_STATE_DIR="$STATE" FAKE_SLOW=6 \
		"$PC" run --model zhipu/glm-5.3 --follow -n 2 ship it >"$follow_out" 2>&1 &
else
	env PI_CONTINUE_BIN="$FAKE" PI_CONTINUE_STATE_DIR="$STATE" FAKE_SLOW=6 \
		"$PC" run --model zhipu/glm-5.3 --follow -n 2 ship it >"$follow_out" 2>&1 &
fi
follower=$!
wait_for 10 grep -q "following live output" "$follow_out" \
	&& ok "launcher announces follow mode" || bad "launcher announces follow mode"
engine_pid="$(cat "$STATE/run.pid" 2>/dev/null)"
[[ "$engine_pid" =~ ^[0-9]+$ ]] && ok "engine armed its pid" || bad "engine armed its pid"
wait_for 10 grep -q "slow line one" "$follow_out" \
	&& ok "follower tails the live engine output" || bad "follower tails the live engine output"
assert_invocation "--follow and -n are consumed after a passthrough flag, never forwarded" 1 \
	-p --session-id "$(ride_id)" --model zhipu/glm-5.3 -- "$(with_marker "ship it")"
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
st="$(pc status | head -1)"
assert_contains "status still shows the run after follower death" "$st" "running (pid"
stop_out="$(pc stop)"
assert_contains "stop still cancels the engine" "$stop_out" "stopped (pid"
wait_for 5 proc_gone "$engine_pid" && ok "stopped engine process is gone" \
	|| bad "stopped engine process is gone"
follower=""

echo "== passthrough isolation =="
fresh pass_known
pc run --provider openai --model gpt-4o-mini --tools 'read,edit' -e ./ext.js --thinking high \
	fix it now >/dev/null 2>&1
wait_for 10 engine_idle && ok "flag-heavy run completes" || bad "flag-heavy run completes"
assert_invocation "value flags pair with their tokens, long and short forms alike" 1 \
	-p --session-id "$(ride_id)" --provider openai --model gpt-4o-mini --tools read,edit \
	-e ./ext.js --thinking high -- "$(with_marker "fix it now")"

fresh pass_equals
pc run --model=zhipu/glm fix >/dev/null 2>&1
wait_for 10 engine_idle && ok "equals-form run completes" || bad "equals-form run completes"
assert_invocation "an equals-form flag forwards verbatim as one token" 1 \
	-p --session-id "$(ride_id)" --model=zhipu/glm -- "$(with_marker fix)"

fresh pass_after
# a synchronous case must never carry --follow: the launcher execs into
# tail -F and would hang the suite, so bool-after-passthrough coverage
# lives in the backgrounded follower scenario above and this pins the
# trailing declared value flag instead, through the same dispatch arm
printf 'productive\nok\n' >"$FAKE_STATE/plan"
# timing invariant: the armed-pidfile window (park plus the two session
# durations) must reach into the launcher's poll grid (READY_POLLS x
# READY_POLL_INTERVAL in the script); a single instant-ok plan or a park
# under ~0.2s would reintroduce poll-grid misses and flake "failed to
# start" on slow machines
PC_ENV=(PI_CONTINUE_WAIT_SECONDS=1)
pass_out="$(pc run --model zhipu/glm-5.3 -n 3 fix it 2>&1)"
PC_ENV=()
assert_contains "declared-after-passthrough launcher detaches cleanly" "$pass_out" "detached (pid"
wait_for 10 engine_idle && ok "declared-after-passthrough run completes" \
	|| bad "declared-after-passthrough run completes"
assert_invocation "a trailing declared value flag after a passthrough flag is consumed with its pair" 1 \
	-p --session-id "$(ride_id)" --model zhipu/glm-5.3 -- "$(with_marker "fix it")"

fresh pass_unknown
pc run --bogus --nonsense=1 fix >/dev/null 2>&1
wait_for 10 engine_idle && ok "unknown-flag run completes" || bad "unknown-flag run completes"
assert_invocation "unknown dash tokens pass through verbatim" 1 \
	-p --session-id "$(ride_id)" --bogus --nonsense=1 -- "$(with_marker fix)"

fresh pass_unknown_val
pc run --flavor spicy fix >/dev/null 2>&1
wait_for 10 engine_idle && ok "unknown bare-flag run completes" \
	|| bad "unknown bare-flag run completes"
assert_invocation "unknown bare flags do not steal the next token" 1 \
	-p --session-id "$(ride_id)" --flavor -- "$(with_marker "spicy fix")"

fresh pass_dashdash
pc run -- --weird -n 2 >/dev/null 2>&1
wait_for 10 engine_idle && ok "dash-forced prompt run completes" \
	|| bad "dash-forced prompt run completes"
assert_invocation "bare -- forces everything after it to be prompt" 1 \
	-p --session-id "$(ride_id)" -- "$(with_marker "--weird -n 2")"

fresh pass_mode_hazard
# pins the parser-trap guard: a rejection-hazard token after a bare --
# rides as prompt text instead of tripping the preflight rejection
pc run -- --mode json fix >/dev/null 2>&1
wait_for 10 engine_idle && ok "dash-forced rejection-hazard prompt run completes" \
	|| bad "dash-forced rejection-hazard prompt run completes"
assert_invocation "a --mode json after bare -- rides as prompt text" 1 \
	-p --session-id "$(ride_id)" -- "$(with_marker "--mode json fix")"

fresh pass_prompt_first
pc run fix --session ID >/dev/null 2>&1
wait_for 10 engine_idle && ok "prompt-first run completes" || bad "prompt-first run completes"
assert_invocation "flags after the first prompt word stay prompt" 1 \
	-p --session-id "$(ride_id)" -- "$(with_marker "fix --session ID")"

fresh pass_default
pc run >/dev/null 2>&1
wait_for 10 engine_idle && ok "default-prompt run completes" || bad "default-prompt run completes"
assert_invocation "no prompt falls back to the truthful default plus the marker line" 1 \
	-p --session-id "$(ride_id)" -- "$(with_marker "$default_prompt")"
assert_not_contains "the ride default never claims your quota is fresh" \
	"$(invocation_args 1)" "your quota is fresh"

fresh pass_mode_text
# --mode text is legal: the output shape the classifiers assume
pc run --mode text fix it >/dev/null 2>&1
wait_for 10 engine_idle && ok "text-mode passthrough run completes" \
	|| bad "text-mode passthrough run completes"
assert_invocation "--mode text pairs with its value and forwards" 1 \
	-p --session-id "$(ride_id)" --mode text -- "$(with_marker "fix it")"

fresh pass_fork
# pi allows --fork with --session-id (it forks into the given id), so
# the supervisor pairs and forwards it; this pins the corrected plan
# note against the review's suggestion 1
pc run --fork origin-123 fix >/dev/null 2>&1
wait_for 10 engine_idle && ok "fork passthrough run completes" || bad "fork passthrough run completes"
assert_invocation "--fork pairs with its value and forwards, never rejected" 1 \
	-p --session-id "$(ride_id)" --fork origin-123 -- "$(with_marker fix)"

echo "== no model injection =="
fresh model_absent
pc run pin me >/dev/null 2>&1
wait_for 10 engine_idle && ok "default run completes" || bad "default run completes"
assert_not_contains "no model flag is ever injected by the supervisor" \
	"$(invocation_args 1)" "--model"

fresh model_explicit
pc run --model other/model pin me >/dev/null 2>&1
wait_for 10 engine_idle && ok "explicit-model run completes" || bad "explicit-model run completes"
assert_eq "an explicit --model passes through exactly once, never duplicated" \
	"$(printf '%s\n' --model other/model)" \
	"$(invocation_args 1 | grep -A1 '^--model$')"

fresh model_explicit_equals
pc run --model=other/model pin me >/dev/null 2>&1
wait_for 10 engine_idle && ok "equals-form explicit-model run completes" \
	|| bad "equals-form explicit-model run completes"
assert_eq "an equals-form --model forwards verbatim, never appended to" "1" \
	"$(invocation_args 1 | grep -c '^--model=other/model$')"

echo "== refusals =="
fresh refuse_usage
refuse "run refuses a non-numeric budget" run -n abc fix it
refuse "run refuses a valueless trailing -n" run -n
refuse "run refuses a valueless trailing --model" run --model
err="$(pc run -n abc fix it 2>&1 >/dev/null || true)"
assert_contains "non-numeric budget refusal says why" "$err" "-n needs a number"
assert_eq "usage refusals spawn no invocation" "" "$(cat "$FAKE_STATE/args")"
[[ ! -f "$STATE/run.pid" ]] && ok "usage refusals arm no pid file" \
	|| bad "usage refusals arm no pid file"

fresh refuse_modes
# Pins the hazard's enforcement split: the preflight rejects --mode
# json/rpc outright, while after a bare `--` it stays prompt text (the
# pass_mode_hazard case above).
refuse_rc 2 "run rejects --mode json" run --mode json fix it
refuse_rc 2 "run rejects --mode=json" run --mode=json fix it
refuse_rc 2 "run rejects --mode rpc" run --mode rpc fix it
refuse_rc 2 "run rejects --mode=rpc" run --mode=rpc fix it
refuse_rc 2 "run rejects --mode mid-passthrough" run --provider openai --mode json fix it
refuse_rc 2 "run rejects a bare trailing --mode" run --mode
err="$(pc run --mode json fix it 2>&1 >/dev/null || true)"
assert_contains "mode refusal names the output-shape hazard" "$err" \
	"non-text modes change the output shape"
assert_eq "mode refusals spawn no invocation" "" "$(cat "$FAKE_STATE/args")"
[[ ! -f "$STATE/run.pid" ]] && ok "mode refusals arm no pid file" \
	|| bad "mode refusals arm no pid file"

fresh refuse_session
refuse_rc 2 "run rejects --session X" run --session X fix it
refuse_rc 2 "run rejects --session-id Y" run --session-id Y fix it
refuse_rc 2 "run rejects -c" run -c
refuse_rc 2 "run rejects --continue" run --continue fix it
refuse_rc 2 "run rejects -r" run -r
refuse_rc 2 "run rejects --resume" run --resume fix it
refuse_rc 2 "run rejects --no-session" run --no-session fix it
refuse_rc 2 "run rejects -p" run -p fix it
err="$(pc run --session-id Y fix it 2>&1 >/dev/null || true)"
assert_contains "session-identity refusal names the lockstep ownership" "$err" \
	"owns session identity"
err="$(pc run -p fix it 2>&1 >/dev/null || true)"
assert_contains "print-mode refusal names the forced print invocation" "$err" \
	"already invokes pi in print mode"
assert_eq "session-identity refusals spawn no invocation" "" "$(cat "$FAKE_STATE/args")"
[[ ! -f "$STATE/run.pid" ]] && ok "session-identity refusals arm no pid file" \
	|| bad "session-identity refusals arm no pid file"

echo "== value-flag parity against the real pi binary =="
if real_pi="$(command -v pi)"; then
	# pi help layout, pinned to live `pi --help`: one option per line,
	# long flag first with an optional `, -x` short after it, then for
	# value-taking options a <...> placeholder (pi prints bare names for
	# booleans and [brackets] for optional values, and --list-models'
	# optional search stays boolean for pairing).
	opt_re='^[[:space:]]*(--[a-zA-Z0-9-]+)(,[[:space:]]+(-[a-zA-Z0-9]+))?([[:space:]]+(<[^>]+>))?'
	declare -A opt_takes_value=() opt_short=()
	opt_order=()
	while IFS= read -r line; do
		# user extension flags register below their own boundary and must
		# not pollute the documented set
		[[ "$line" == "Extension CLI Flags:"* ]] && break
		[[ "$line" =~ $opt_re ]] || continue
		cur="${BASH_REMATCH[1]}"
		[[ -z "${opt_takes_value[$cur]+x}" ]] && opt_order+=("$cur")
		opt_short["$cur"]="${BASH_REMATCH[3]:-}"
		if [[ -n "${BASH_REMATCH[5]:-}" ]]; then
			opt_takes_value["$cur"]=1
		else
			opt_takes_value["$cur"]=0
		fi
	done < <("$real_pi" --help 2>&1)
	# An unrecognized help layout must fail loudly here, never pass
	# vacuously through an empty derived set.
	(( ${#opt_order[@]} > 0 )) || bad "help parses to a non-empty option set"
	# Sentinels for the drift classes parity cannot see: it proves table
	# equals derived, never derived equals the truth.
	for sentinel in --model --session-id --extension; do
		[[ "${opt_takes_value[$sentinel]:-}" == 1 ]] && ok "derived set keeps $sentinel as value-taking" \
			|| bad "derived set lost $sentinel as value-taking; help layout or placeholder vocabulary drifted"
	done
	[[ "${opt_takes_value[--list-models]:-}" == 0 ]] \
		&& ok "derived set keeps optional-value --list-models boolean (the pairing contract)" \
		|| bad "derived set flipped optional-value --list-models to value-taking; the pairing contract drifted"
	# The -n carve-out's target: pi spells session naming --name, -n, and
	# on overlap the supervisor wins, so -n stays out of PI_VALUE_FLAGS.
	[[ "${opt_short[--name]:-}" == "-n" ]] \
		&& ok "pi still spells session naming --name, -n (the carve-out's target)" \
		|| bad "pi's session-naming short is no longer -n (got [${opt_short[--name]:-}]); the -n carve-out needs retraining"
	derived_value=()
	derived_all=()
	for opt in "${opt_order[@]}"; do
		derived_all+=("$opt")
		[[ -n "${opt_short[$opt]}" ]] && derived_all+=("${opt_short[$opt]}")
		if [[ "${opt_takes_value[$opt]}" == 1 ]]; then
			derived_value+=("$opt")
			[[ -n "${opt_short[$opt]}" ]] && derived_value+=("${opt_short[$opt]}")
		fi
	done
	carved_value=()
	for flag in "${derived_value[@]}"; do
		[[ "$flag" == "-n" ]] || carved_value+=("$flag")
	done
	script_value_flags="$(sed -n 's/^PI_VALUE_FLAGS=(\(.*\))$/\1/p' "$PC" \
		| tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort)"
	assert_eq "PI_VALUE_FLAGS equals the help-derived value-taking set minus the -n carve-out" \
		"$(printf '%s\n' "${carved_value[@]}" | LC_ALL=C sort)" "$script_value_flags"
	run_value_line="$(sed -n 's/^PI_RUN_VALUE_FLAGS=(\(.*\))$/\1/p' "$PC")"
	run_bool_line="$(sed -n 's/^PI_RUN_BOOL_FLAGS=(\(.*\))$/\1/p' "$PC")"
	assert_eq "declared value table is exactly the supervisor's -n" "-n" "$run_value_line"
	assert_eq "declared bool table is exactly --follow" "--follow" "$run_bool_line"
	declare -A documented=()
	for flag in "${derived_all[@]}"; do documented["$flag"]=1; done
	overlap=""
	for flag in $run_value_line $run_bool_line; do
		[[ -n "${documented[$flag]+x}" ]] && overlap="$overlap $flag"
	done
	assert_eq "the declared tables overlap the documented pi set in exactly the -n carve-out" \
		" -n" "$overlap"
else
	skip_test "PI_VALUE_FLAGS parity (no real pi on PATH)"
	skip_test "declared-table disjointness (no real pi on PATH)"
fi

print_result
((fail == 0)) || exit 1
