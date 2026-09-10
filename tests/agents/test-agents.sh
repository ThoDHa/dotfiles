#!/usr/bin/env bash
#
# Structural tests for the agent suite. Base invariants (deny-by-default
# manager allow-list, subagents cannot dispatch) always run. The PII-safe
# checks (pinning policy, preamble, bidirectional isolation, derivation
# parity) run only when the safe files exist: the safe suite is deleted
# until the LiteLLM gateway goes live, and `make generate-safe-agents`
# recreates it, at which point these checks reactivate automatically.
# Invariants are documented in opencode/PII-SAFE.md.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS="$REPO_ROOT/opencode/.config/opencode/agents"

pass=0
fail=0

ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }

assert_file() { [[ -f "$1" ]] && ok "$2" || bad "$2"; }
assert_grep() { grep -qE -- "$2" "$3" && ok "$1" || bad "$1 (missing pattern [$2] in $(basename "$3"))"; }
assert_not_grep() { grep -qE -- "$2" "$3" && bad "$1 (found forbidden pattern [$2] in $(basename "$3"))" || ok "$1"; }

echo "agent suite tests:"

# ── Base invariants (always) ──────────────────────────────────────────────────
assert_grep "base manager is deny-by-default" '"\*": "deny"' "$AGENTS/manager.md"
assert_grep "base manager allows worker" '^    "worker": "allow"$' "$AGENTS/manager.md"
assert_grep "base manager allows verifier" '^    "verifier": "allow"$' "$AGENTS/manager.md"
assert_grep "base manager allows reviewer" '^    "reviewer": "allow"$' "$AGENTS/manager.md"
assert_not_grep "base manager allows no -safe agent" '"-safe": "allow"' "$AGENTS/manager.md"
for f in worker verifier reviewer; do
	assert_grep "$f cannot spawn subagents" 'task: deny' "$AGENTS/$f.md"
done

# ── PII-safe suite (only when deployed) ───────────────────────────────────────
SAFE_PRESENT=1
for f in manager-safe worker-safe verifier-safe reviewer-safe; do
	[[ -f "$AGENTS/$f.md" ]] || SAFE_PRESENT=0
done

if [[ $SAFE_PRESENT -eq 0 ]]; then
	echo "  (PII-safe suite absent: safe checks skipped; restore with make generate-safe-agents)"
	[[ $fail -eq 0 ]] && exit 0
fi

for f in manager-safe worker-safe verifier-safe reviewer-safe; do
	assert_file "$AGENTS/$f.md" "$f.md exists"
done

assert_grep "worker-safe pins paid flash" '^model: zai-coding-plan/glm-5\.3-flash$' "$AGENTS/worker-safe.md"
assert_grep "verifier-safe pins paid flash" '^model: zai-coding-plan/glm-5\.3-flash$' "$AGENTS/verifier-safe.md"
assert_not_grep "manager-safe inherits session model (no pin)" '^model:' "$AGENTS/manager-safe.md"
assert_not_grep "reviewer-safe inherits session model (no pin)" '^model:' "$AGENTS/reviewer-safe.md"

# manager-safe may name gateway/cascade only inside its prohibition sentence,
# so its check targets any model pin; the subagents have no reason to
# mention the gateway at all.
assert_not_grep "manager-safe pins no gateway model" '^model:.*gateway' "$AGENTS/manager-safe.md"
for f in worker-safe verifier-safe reviewer-safe; do
	assert_not_grep "$f references no gateway model" 'gateway/' "$AGENTS/$f.md"
done

for f in manager-safe worker-safe verifier-safe reviewer-safe; do
	assert_grep "$f carries the PII-safe preamble" 'PII-safe' "$AGENTS/$f.md"
done

assert_grep "manager-safe is deny-by-default" '"\*": "deny"' "$AGENTS/manager-safe.md"
assert_grep "manager-safe allows worker-safe" '^    "worker-safe": "allow"$' "$AGENTS/manager-safe.md"
assert_grep "manager-safe allows verifier-safe" '^    "verifier-safe": "allow"$' "$AGENTS/manager-safe.md"
assert_grep "manager-safe allows reviewer-safe" '^    "reviewer-safe": "allow"$' "$AGENTS/manager-safe.md"
assert_not_grep "manager-safe allows no bare worker" '^    "worker": "allow"$' "$AGENTS/manager-safe.md"
assert_not_grep "manager-safe allows no bare verifier" '^    "verifier": "allow"$' "$AGENTS/manager-safe.md"
assert_not_grep "manager-safe allows no bare reviewer" '^    "reviewer": "allow"$' "$AGENTS/manager-safe.md"
assert_grep "manager-safe prompt forbids base dispatch" 'MUST NOT dispatch worker, verifier, or reviewer' "$AGENTS/manager-safe.md"

for f in worker-safe verifier-safe reviewer-safe; do
	assert_grep "$f cannot spawn subagents" 'task: deny' "$AGENTS/$f.md"
done

tmp_agents="$(mktemp -d)"
trap 'rm -rf "$tmp_agents"' EXIT
for f in manager worker verifier reviewer; do
	cp "$AGENTS/$f.md" "$tmp_agents/$f.md"
done
AGENTS_DIR="$tmp_agents" "$REPO_ROOT/opencode/.local/bin/generate-safe-agents"
for f in manager-safe worker-safe verifier-safe reviewer-safe; do
	if diff -q "$tmp_agents/$f.md" "$AGENTS/$f.md" >/dev/null; then
		ok "$f.md matches generator output (no hand drift)"
	else
		bad "$f.md matches generator output (run: make generate-safe-agents)"
	fi
done

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
