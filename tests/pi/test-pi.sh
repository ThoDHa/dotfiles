#!/usr/bin/env bash
#
# Structural and behavioral tests for the pi coding agent integration.
# Hermetic throughout: the update-feed and installed-version parsers are
# the real setup.sh functions, extracted and eval'd in subshells with a
# fake curl / fake pi shim prepended to PATH, so the feed endpoint and
# the binary are never touched. The seed config repo (ThoDHa/pi) is
# replicated as a local fixture in a mktemp sandbox, and its whitelist
# .gitignore and pre-commit secrets guard are probed with git
# check-ignore and direct hook invocation against a corrupt
# GIT_INDEX_FILE for the fail-closed path. The real origin is probed
# with a byte-fidelity comparison at the settled seed commit only when
# the network is reachable; offline runs (make verify is network-off)
# announce that section as skipped, which keeps the whole suite green
# and container-safe.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP_SH="$REPO_ROOT/bootstrap/setup.sh"
ZSHRC="$REPO_ROOT/shell/.zshrc"
SEED_ORIGIN="https://github.com/ThoDHa/pi.git"
SEED_COMMIT="3431439"

source "$REPO_ROOT/tests/lib/harness.sh"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# Print a top-level shell function's text (name at column zero, closing
# brace alone on its last line, the setup.sh layout). Empty output means
# the function is gone, which every consumer asserts loudly.
extract_fn() { # function-name file
	awk -v fn="$1" '
		index($0, fn "() {") == 1 { found = 1 }
		found { print }
		found && $0 == "}" { exit }
	' "$2"
}

echo "== setup.sh: pi functions and gates =="
setup="$(cat "$SETUP_SH")"
for fn in _pi_latest_version _pi_installed_version step_pi; do
	assert_contains "setup.sh defines $fn()" "$setup" "$fn()"
done

# WANT_PI is force-set to 0 when SKIP_CHSH=1 (the container-build
# marker): the equality check's very next line must be the forced
# assignment, so a prompt that can fire inside a container build fails.
forced_off="$(awk '/\[ "\$\{SKIP_CHSH:-0\}" = "1" \]/{
	getline nxt
	if (nxt ~ /^[[:space:]]*WANT_PI=0[[:space:]]*$/) print NR
}' "$SETUP_SH")"
if [[ -n "$forced_off" ]]; then
	ok "WANT_PI is force-set to 0 when SKIP_CHSH=1 (line $forced_off)"
else
	bad "WANT_PI is force-set to 0 when SKIP_CHSH=1"
fi

clone_ln="$(grep -nF 'git_clone_or_pull "pi config" "https://github.com/ThoDHa/pi.git"' "$SETUP_SH" | head -1 | cut -d: -f1)"
hooks_ln="$(grep -nF 'config core.hooksPath .githooks' "$SETUP_SH" | cut -d: -f1 | awk -v c="${clone_ln:-0}" '$1 > c {print $1; exit}')"
assert_contains "config clone target is ~/.pi/agent" "$setup" 'pi_agent="$HOME/.pi/agent"'
if [[ -n "$clone_ln" ]]; then
	ok "config step clones ThoDHa/pi (line $clone_ln)"
else
	bad "config step clones ThoDHa/pi"
fi
if [[ -n "$clone_ln" && -n "$hooks_ln" ]] && ((hooks_ln - clone_ln <= 3)); then
	ok "clone is followed by a core.hooksPath .githooks activation (line $hooks_ln)"
else
	bad "clone is followed by a core.hooksPath .githooks activation"
fi
assert_contains "step_verify's pi block is gated on WANT_PI=1 and the deployed clone" "$setup" \
	'[ "$WANT_PI" = "1" ] && [ -e "$HOME/.pi/agent/.git" ]'

echo "== update-feed parser (real function, fake curl) =="
latest_fn="$(extract_fn _pi_latest_version "$SETUP_SH")"
if [[ -n "$latest_fn" ]]; then
	ok "feed parser is extractable for behavioral probing"
else
	bad "feed parser is extractable for behavioral probing"
fi
assert_contains "feed parser fetches the documented endpoint" "$latest_fn" "https://pi.dev/api/latest-version"
assert_contains "feed parser picks the first version key" "$latest_fn" "grep -o '\"version\":\"[^\"]*\"'"
assert_contains "feed parser takes one line" "$latest_fn" "head -1"
assert_contains "feed parser strips to the bare value" "$latest_fn" "sed -E 's/.*\"([^\"]+)\".*/\\1/'"

# Fake curl: cats a fixture payload file, so a missing file doubles as
# the fetch-failure case (its stderr is eaten by the function's own
# 2>/dev/null, mirroring a real network error).
feed_bin="$ROOT/feedbin"
mkdir -p "$feed_bin"
printf '#!/bin/sh\ncat "%s"\n' "$ROOT/feed.json" >"$feed_bin/curl"
chmod +x "$feed_bin/curl"

run_feed_parser() { # payload; prints the real _pi_latest_version output
	printf '%s\n' "$1" >"$ROOT/feed.json"
	(
		PATH="$feed_bin:$PATH"
		eval "$(extract_fn _pi_latest_version "$SETUP_SH")"
		_pi_latest_version
	)
}

assert_eq "feed parser reads a plain payload" "1.2.3" "$(run_feed_parser '{"version":"1.2.3"}')"
assert_eq "feed parser survives sibling keys" "4.5.6" \
	"$(run_feed_parser '{"ok":true,"version":"4.5.6","url":"https://pi.dev"}')"
assert_eq "feed parser takes the first version when several are present" "7.0.0" \
	"$(run_feed_parser $'{"version":"7.0.0"}\n{"version":"8.0.0"}')"
rm -f "$ROOT/feed.json"
[[ -z "$(run_feed_parser 'unused')" ]] \
	&& ok "feed parser degrades to empty on a fetch failure" \
	|| bad "feed parser degrades to empty on a fetch failure"
printf 'no version key here\n' >"$ROOT/feed.json"
[[ -z "$(run_feed_parser 'unused')" ]] \
	&& ok "feed parser degrades to empty on an unparseable payload" \
	|| bad "feed parser degrades to empty on an unparseable payload"

echo "== installed-version parser (real function, fake pi) =="
installed_fn="$(extract_fn _pi_installed_version "$SETUP_SH")"
if [[ -n "$installed_fn" ]]; then
	ok "installed-version parser is extractable for behavioral probing"
else
	bad "installed-version parser is extractable for behavioral probing"
fi
assert_contains "installed-version parser probes pi --version" "$installed_fn" "pi --version"
assert_contains "installed-version parser keeps the first token only" "$installed_fn" "awk '{print \$1}'"

pi_bin="$ROOT/pibin"
mkdir -p "$pi_bin"
cat >"$pi_bin/pi" <<EOF
#!/bin/sh
printf '%s\n' "\$FAKE_PI_VERSION"
EOF
chmod +x "$pi_bin/pi"

# A PATH with awk but no pi anywhere on it, so the missing-binary case
# stays silent instead of leaking "command not found" noise.
no_pi_bin="$ROOT/nopibin"
mkdir -p "$no_pi_bin"
ln -s "$(command -v awk)" "$no_pi_bin/awk"

run_installed_parser() { # simulated `pi --version` output, or "missing" for no binary
	local simulated="$1"
	(
		if [[ "$simulated" == "missing" ]]; then
			PATH="$no_pi_bin"
		else
			PATH="$pi_bin:$PATH"
			export FAKE_PI_VERSION="$simulated"
		fi
		eval "$(extract_fn _pi_installed_version "$SETUP_SH")"
		_pi_installed_version
	)
}

assert_eq "installed-version parser reads a bare version" "1.2.3" "$(run_installed_parser '1.2.3')"
assert_eq "installed-version parser keeps only the leading token" "2.0.0" "$(run_installed_parser '2.0.0 beta extra')"
[[ -z "$(run_installed_parser 'missing')" ]] \
	&& ok "installed-version parser degrades to empty without the pi binary" \
	|| bad "installed-version parser degrades to empty without the pi binary"

echo "== .zshrc: session-dir export =="
zshrc="$(cat "$ZSHRC")"
assert_eq "zshrc carries exactly one pi export" "1" "$(grep -cF 'PI_CODING_AGENT_SESSION_DIR' "$ZSHRC")"
assert_contains "the pi export pins the session dir under ~/.local/share" "$zshrc" \
	'export PI_CODING_AGENT_SESSION_DIR="$HOME/.local/share/pi/sessions"'

echo "== upstream-vendor isolation =="
leaks="$(grep -rIl 'mariozechner' "$REPO_ROOT/bootstrap" "$REPO_ROOT/shell" 2>/dev/null || true)"
if [[ -z "$leaks" ]]; then
	ok "mariozechner appears nowhere in bootstrap/ or shell/"
else
	bad "mariozechner appears nowhere in bootstrap/ or shell/ (found in: $leaks)"
fi

echo "== seed fixture: whitelist and secrets guard =="
# Local replica of the ThoDHa/pi seed at the settled commit: a
# default-deny whitelist .gitignore plus the pre-commit guard, byte-for-
# byte (the origin section below cross-checks the bytes against the real
# clone, so a drifted replica fails there too).
build_seed_fixture() { # dir
	local dir="$1"
	git init -q -b main "$dir"
	cat >"$dir/.gitignore" <<'EOF'
/*
!/.gitignore
!/README.md
!/settings.json
!/.githooks/
EOF
	mkdir -p "$dir/.githooks"
	cat >"$dir/.githooks/pre-commit" <<'HOOKEOF'
#!/bin/sh
# Second layer of the secrets guard (the whitelist .gitignore default-deny is
# the first): fails when any staged path is a credential file (auth.json,
# models.json, mcp.json, mcp-auth.json) or under sessions/. Deletions stay
# exempt so an accidentally tracked secrets file can still be removed.

paths=$(git diff --cached --name-only --diff-filter=d) || {
	printf 'pre-commit: git diff failed; refusing to skip the guard\n' >&2
	exit 1
}

fail=0
while IFS= read -r path; do
	case "$path" in
	auth.json | */auth.json | models.json | */models.json | mcp.json | */mcp.json | mcp-auth.json | */mcp-auth.json | sessions/* | */sessions/*)
		printf 'pre-commit: refusing "%s"\n' "$path" >&2
		fail=1
		;;
	esac
done <<EOF
$paths
EOF

if [ "$fail" -ne 0 ]; then
	printf 'pre-commit: credentials (auth.json, models.json, mcp.json, mcp-auth.json) and transcripts (sessions/) must not be committed; the whitelist default-deny is the first layer\n' >&2
	printf 'pre-commit: unstage the listed files with: git restore --staged <path>\n' >&2
fi
exit $fail
HOOKEOF
	chmod 755 "$dir/.githooks/pre-commit"
	printf '# pi\n\nSeed config for the pi coding agent.\n' >"$dir/README.md"
	cat >"$dir/settings.json" <<'EOF'
{
  "$schema": "https://pi.dev/schemas/settings.schema.json"
}
EOF
	git -C "$dir" add -A
	git -C "$dir" -c user.name=test -c user.email=test@example.com commit -q -m seed
	git -C "$dir" config core.hooksPath .githooks
}

probe_seed_repo() { # repo label; runs the whitelist and guard battery
	local repo="$1" label="$2" p mode keys
	for p in auth.json models.json mcp.json mcp-auth.json sessions/2026-01-01.jsonl transcript.txt \
		deep/nested/auth.json sub/sessions/t.jsonl nested/models.json; do
		if git -C "$repo" check-ignore -q "$p"; then
			ok "$label: whitelist ignores $p"
		else
			bad "$label: whitelist ignores $p"
		fi
	done
	for p in .gitignore README.md settings.json .githooks/pre-commit .githooks/new-hook.sh; do
		if git -C "$repo" check-ignore -q "$p"; then
			bad "$label: whitelist keeps $p addable"
		else
			ok "$label: whitelist keeps $p addable"
		fi
	done
	mode="$(git -C "$repo" ls-files -s .githooks/pre-commit | awk '{print $1}')"
	assert_eq "$label: pre-commit hook is tracked executable (100755)" "100755" "$mode"

	if [[ -x "$repo/.githooks/pre-commit" ]]; then
		ok "$label: hook file is executable on disk"
	else
		bad "$label: hook file is executable on disk"
		return
	fi

	# Hook runs must resolve git inside the fixture repo, so each one is
	# a subshell cd (the hook has no repo argument of its own).
	run_hook() ( # repo-dir; git resolves against the cd'd repo
		cd "$1" && "./.githooks/pre-commit"
	)

	# Direct invocation against force-added secrets: the whitelist layer
	# denies the plain add, so a staged secret is exactly the bypass the
	# hook layer exists to catch.
	for p in auth.json deep/nested/auth.json models.json a/b/models.json mcp.json x/y/mcp.json \
		mcp-auth.json q/mcp-auth.json sessions/s.jsonl deep/sub/sessions/t.jsonl; do
		mkdir -p "$repo/$(dirname "$p")"
		printf 'secret\n' >"$repo/$p"
		git -C "$repo" add -f "$p"
		if run_hook "$repo" 2>"$ROOT/hook.err"; then
			bad "$label: guard blocks staged $p"
		else
			ok "$label: guard blocks staged $p"
		fi
		assert_contains "$label: guard refusal names $p" "$(cat "$ROOT/hook.err")" "$p"
		git -C "$repo" reset -q
	done

	# A whitelisted change sails through.
	printf '# pi\n\nSeed config for the pi coding agent.\n\nprobed\n' >"$repo/README.md"
	git -C "$repo" add README.md
	if run_hook "$repo" 2>"$ROOT/hook.err"; then
		ok "$label: guard allows a staged whitelist change"
	else
		bad "$label: guard allows a staged whitelist change ($(cat "$ROOT/hook.err"))"
	fi
	git -C "$repo" reset -q
	git -C "$repo" checkout -q README.md

	# Deletion exemption: an accidentally tracked secret can be removed.
	printf 'x\n' >"$repo/auth.json"
	git -C "$repo" add -f auth.json
	git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q --no-verify -m 'probed: accidentally tracked'
	git -C "$repo" rm -q auth.json
	if run_hook "$repo" 2>"$ROOT/hook.err"; then
		ok "$label: guard exempts a staged secret deletion"
	else
		bad "$label: guard exempts a staged secret deletion ($(cat "$ROOT/hook.err"))"
	fi
	git -C "$repo" -c user.name=test -c user.email=test@example.com commit -q --no-verify -m 'probed: remove it'

	# Fail closed: a corrupt index makes git diff fail, and the guard
	# must refuse to wave the commit through.
	printf 'junk' >"$ROOT/junk-index"
	if GIT_INDEX_FILE="$ROOT/junk-index" run_hook "$repo" 2>"$ROOT/hook.err"; then
		bad "$label: guard fails closed when git diff fails"
	else
		ok "$label: guard fails closed when git diff fails"
	fi
	assert_contains "$label: fail-closed message explains the refusal" "$(cat "$ROOT/hook.err")" "git diff failed"

	# settings.json carries the schema reference and nothing else.
	keys="$(grep -oE '"[^"]+"[[:space:]]*:' "$repo/settings.json" | grep -vF '"$schema"' || true)"
	if [[ -z "$keys" ]]; then
		ok "$label: settings.json carries only the \$schema key"
	else
		bad "$label: settings.json carries only the \$schema key (extra keys: $keys)"
	fi
	assert_contains "$label: settings.json references the pi schema" "$(cat "$repo/settings.json")" '"$schema"'
}

FIXTURE="$ROOT/pi-seed-fixture"
build_seed_fixture "$FIXTURE"
probe_seed_repo "$FIXTURE" "fixture"

echo "== origin fidelity (network-gated) =="
if timeout 20 git ls-remote "$SEED_ORIGIN" >/dev/null 2>&1; then
	origin="$ROOT/pi-seed-origin"
	if git clone -q "$SEED_ORIGIN" "$origin" && git -C "$origin" checkout -q "$SEED_COMMIT"; then
		ok "origin serves the settled seed commit $SEED_COMMIT"
		for f in .gitignore .githooks/pre-commit settings.json; do
			if cmp -s "$origin/$f" "$FIXTURE/$f"; then
				ok "origin $f matches the fixture byte-for-byte"
			else
				bad "origin $f matches the fixture byte-for-byte"
			fi
		done
		assert_eq "origin hook is tracked executable (100755)" "100755" \
			"$(git -C "$origin" ls-files -s .githooks/pre-commit | awk '{print $1}')"
	else
		bad "origin serves the settled seed commit $SEED_COMMIT"
		skip_test "origin byte-fidelity (seed commit unreachable)"
	fi
else
	skip_test "origin fidelity battery (network unreachable; verify-inner runs network-off)"
fi

print_result
((fail == 0)) || exit 1
