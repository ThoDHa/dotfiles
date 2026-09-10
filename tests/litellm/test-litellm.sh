#!/usr/bin/env bash
#
# Tests for the litellm stow package: file presence, syntax, the managed
# pool markers, the compose security posture, and the merge semantics of
# generate-models.sh (preserve kept entries verbatim, drop decommissioned
# ids, append new free ids, exclude muse-spark, idempotence).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG="$REPO_ROOT/litellm/.config/litellm"

pass=0
fail=0

ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }

assert_file() { [[ -f "$1" ]] && ok "$2" || bad "$2"; }
assert_grep() { grep -qE -- "$2" "$3" && ok "$1" || bad "$1 (missing pattern [$2] in $3)"; }
assert_not_grep() { grep -qE -- "$2" "$3" && bad "$1 (found forbidden pattern [$2] in $3)" || ok "$1"; }

echo "litellm package tests:"

# ── Presence and syntax ───────────────────────────────────────────────────────
for f in config.yaml docker-compose.yaml env.example generate-models.sh; do
	assert_file "$PKG/$f" "$f exists"
done
if bash -n "$PKG/generate-models.sh" 2>/dev/null; then ok "generator bash syntax valid"; else bad "generator bash syntax valid"; fi
[[ -x "$PKG/generate-models.sh" ]] && ok "generator is executable" || bad "generator is executable"

# ── config.yaml structure ─────────────────────────────────────────────────────
assert_grep "managed block begin marker" '^  # BEGIN MANAGED BLOCK$' "$PKG/config.yaml"
assert_grep "managed block end marker" '^  # END MANAGED BLOCK$' "$PKG/config.yaml"
assert_grep "flash terminal tier present" 'model_name: flash' "$PKG/config.yaml"
assert_grep "flash points at z.ai coding plan" 'api_base: https://api\.z\.ai/api/coding/paas/v4' "$PKG/config.yaml"
assert_not_grep "no muse-spark in pool" 'muse-spark' "$PKG/config.yaml"
assert_grep "fallback chain cascade to flash" 'cascade: \["flash"\]' "$PKG/config.yaml"
assert_not_grep "no groq in active pool" 'groq/' "$PKG/config.yaml"

# ── docker-compose.yaml posture ───────────────────────────────────────────────
assert_grep "localhost-only publish" '127\.0\.0\.1:4000:4000' "$PKG/docker-compose.yaml"
assert_grep "memory limit set" 'mem_limit: 512m' "$PKG/docker-compose.yaml"
assert_grep "restart policy" 'restart: unless-stopped' "$PKG/docker-compose.yaml"
assert_grep "official image" 'ghcr\.io/berriai/litellm' "$PKG/docker-compose.yaml"

# ── Secrets hygiene ───────────────────────────────────────────────────────────
assert_grep "env template lists ZEN_API_KEY" '^ZEN_API_KEY=$' "$PKG/env.example"
if git -C "$REPO_ROOT" check-ignore -q litellm/.config/litellm/env; then
	ok "env file is gitignored"
else
	bad "env file is gitignored"
fi

# ── generate-models.sh merge semantics ────────────────────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/catalog.json" <<'JSON'
{"data":[{"id":"big-pickle"},{"id":"new-free-thing"},{"id":"muse-spark-1.3-contributor-free"},{"id":"paid-model"}]}
JSON

cat > "$tmp/config.yaml" <<'YAML'
model_list:
  # BEGIN MANAGED BLOCK
  - model_name: cascade
    litellm_params:
      model: openai/big-pickle
      api_base: https://opencode.ai/zen/v1
      api_key: os.environ/ZEN_API_KEY
    model_info:
      max_input_tokens: 99000
  - model_name: cascade
    litellm_params:
      model: openai/ling-3.0-flash-fin-free
      api_base: https://opencode.ai/zen/v1
      api_key: os.environ/ZEN_API_KEY
  # END MANAGED BLOCK
  - model_name: flash
    litellm_params:
      model: openai/glm-5.3-flash
      api_base: https://api.z.ai/api/coding/paas/v4
      api_key: os.environ/ZAI_API_KEY
YAML

run_gen() {
	CONFIG_PATH="$tmp/config.yaml" \
	ZEN_MODELS_URL="file://$tmp/catalog.json" \
	ZEN_API_KEY=dummy \
	"$PKG/generate-models.sh" "$@"
}

gen_out="$(run_gen --yes 2>&1)"
gen_status=$?
if [[ $gen_status -eq 0 ]]; then ok "generator run succeeds"; else bad "generator run succeeds (exit $gen_status, output: $gen_out)"; fi

assert_grep "new free id appended" 'model: openai/new-free-thing' "$tmp/config.yaml"
assert_not_grep "decommissioned id dropped" 'ling-3\.0-flash-fin-free' "$tmp/config.yaml"
assert_grep "kept entry preserved verbatim (model_info survives)" 'max_input_tokens: 99000' "$tmp/config.yaml"
assert_not_grep "muse-spark excluded despite free suffix" 'muse-spark' "$tmp/config.yaml"
assert_not_grep "paid model excluded" 'paid-model' "$tmp/config.yaml"
assert_grep "flash entry untouched outside markers" 'model: openai/glm-5\.3-flash' "$tmp/config.yaml"

second_out="$(run_gen --yes 2>&1)"
if grep -q "nothing to change" <<<"$second_out"; then
	ok "second run is a no-op (idempotent)"
else
	bad "second run is a no-op (output: $second_out)"
fi

# ── Stow safety: a symlinked config must stay a symlink after refresh ────────
mkdir -p "$tmp/stowed-target" "$tmp/stow-home"
cp "$tmp/config.yaml" "$tmp/stowed-target/config.yaml"
ln -s "$tmp/stowed-target/config.yaml" "$tmp/stow-home/config.yaml"
CONFIG_PATH="$tmp/stow-home/config.yaml" \
ZEN_MODELS_URL="file://$tmp/catalog.json" \
ZEN_API_KEY=dummy \
"$PKG/generate-models.sh" --yes >/dev/null 2>&1
if [[ -L "$tmp/stow-home/config.yaml" ]]; then
	ok "stow symlink preserved after refresh"
else
	bad "stow symlink preserved after refresh"
fi
assert_grep "refresh wrote through to the repo target" 'model: openai/new-free-thing' "$tmp/stowed-target/config.yaml"

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
