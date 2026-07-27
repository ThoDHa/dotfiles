#!/usr/bin/env bash
#
# Host-side tests for bootstrap/termux.sh. The script's runtime behavior can
# only be verified on a device, so these tests cover what is checkable here:
# syntax, the Termux guard, absence of Debian-isms, step structure, and the
# exclusion of tools that must not appear on the Termux path.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bootstrap/termux.sh"

pass=0
fail=0

ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=$((fail + 1)); }

assert_file()         { [[ -f "$SCRIPT" ]] && ok "$1" || bad "$1"; }
assert_grep()         { grep -qE -- "$2" "$SCRIPT" && ok "$1" || bad "$1 (missing pattern [$2])"; }
assert_not_grep()     { grep -qE -- "$2" "$SCRIPT" && bad "$1 (found forbidden pattern [$2])" || ok "$1"; }

echo "termux.sh tests:"

# ── Existence and syntax ──────────────────────────────────────────────────────
assert_file "script exists"
if [[ -f "$SCRIPT" ]]; then
	if bash -n "$SCRIPT" 2>/dev/null; then ok "bash syntax valid"; else bad "bash syntax valid"; fi
	[[ -x "$SCRIPT" ]] && ok "script is executable" || bad "script is executable"
else
	# Nothing else is checkable without the file
	echo ""
	echo "Results: $pass passed, $fail failed"
	exit 1
fi

# ── Termux guard ──────────────────────────────────────────────────────────────
assert_grep "guards against non-Termux hosts" 'TERMUX_VERSION'

# ── No Debian-isms or root assumptions ────────────────────────────────────────
assert_not_grep "no sudo anywhere" '(^|[^a-zA-Z-])sudo '
assert_not_grep "no apt-get" 'apt-get'
assert_not_grep "no AppImage installs" '[Aa]pp[Ii]mage'
assert_not_grep "no nvm (glibc node binaries)" 'nvm-sh|NVM_DIR.*install'
assert_not_grep "no hardcoded /usr/local paths" '/usr/local/'

# ── Excluded tools stay excluded ──────────────────────────────────────────────
assert_not_grep "no opencode install" 'opencode\.ai|step_opencode'
assert_not_grep "no claude install" 'claude\.ai/install|step_claude'
assert_not_grep "no docker" 'docker'

# ── Step structure mirrors setup.sh contract ─────────────────────────────────
assert_grep "per-step failure tracking (run_step)" 'run_step'
assert_grep "failure accumulator (FAILED_STEPS)" 'FAILED_STEPS'
assert_grep "verification step present" 'step_verify'

# ── Required installs are present ─────────────────────────────────────────────
assert_grep "installs core packages via pkg" 'pkg install'
assert_grep "installs neovim" '\bneovim\b'
assert_grep "installs python" '\bpython\b'
assert_grep "installs tmux" '\btmux\b'
assert_grep "installs zsh" '\bzsh\b'
assert_grep "installs nodejs" '\bnodejs\b'
assert_grep "installs openssh for git auth" '\bopenssh\b'
assert_grep "installs termux-api for clipboard" 'termux-api'
assert_grep "installs ripgrep (telescope live grep)" '\bripgrep\b'
assert_grep "installs the clang toolchain" '\bclang\b'
assert_grep "creates the nvim provider venv" 'venv'
assert_grep "installs pynvim" 'pynvim'
assert_grep "installs the format-on-save chain (black)" '\bblack\b'
assert_grep "installs isort" '\bisort\b'
assert_grep "installs a Python LSP" 'pyright|python-lsp-server'
assert_grep "installs a Nerd Font" 'font\.ttf'
assert_grep "configures the extra-keys row" 'extra-keys'
assert_grep "clones the nvim config" 'ThoDHa/nvim'
assert_grep "installs TPM" 'tmux-plugins/tpm'
assert_grep "installs oh-my-zsh" 'oh-my-zsh'

# ── Idempotency markers ───────────────────────────────────────────────────────
assert_grep "re-run safe: existence checks present" 'command -v|\[ ! -d|\[ ! -f|\[ -d|\[ -f'

# ── Optional: shellcheck when available ───────────────────────────────────────
if command -v shellcheck &>/dev/null; then
	if shellcheck -S error "$SCRIPT" >/dev/null 2>&1; then
		ok "shellcheck (errors only)"
	else
		bad "shellcheck (errors only)"
	fi
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
