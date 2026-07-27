#!/usr/bin/env bash
#
# Termux (Android) development environment setup.
# Idempotent — safe to run multiple times from any directory.
#
# Scope: NeoVim + Python + tmux + zsh as one seamless environment.
# Deliberately absent: the AI tooling and container steps from setup.sh,
# which either cannot run on Android or are excluded from this platform.
#
# Usage:
#   ./bootstrap/termux.sh

# ── Termux guard ──────────────────────────────────────────────────────────────
if [ -z "${TERMUX_VERSION:-}" ] && ! echo "${PREFIX:-}" | grep -q com.termux; then
    echo "This script is for Termux on Android only. Use bootstrap/setup.sh elsewhere." >&2
    exit 1
fi

# ── Resolve dotfiles root regardless of call site ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step()    { echo -e "\n${YELLOW}▶  $1${NC}"; }
print_success() { echo -e "${GREEN}✓  $1${NC}"; }
print_error()   { echo -e "${RED}✗  $1${NC}" >&2; }

# ── Failure tracking ──────────────────────────────────────────────────────────
FAILED_STEPS=()

# Run a named step in an isolated subshell.
# Errors inside the step are caught; the main script never aborts.
run_step() {
    local label="$1"
    local fn="$2"
    print_step "$label"
    if ( set -e; "$fn" ); then
        print_success "$label"
    else
        print_error "FAILED — $label"
        FAILED_STEPS+=("$label")
    fi
}

# ── Shared helpers ────────────────────────────────────────────────────────────

# Clone a repo if the destination is absent, otherwise pull.
git_clone_or_pull() {
    local label="$1" url="$2" dest="$3"
    shift 3
    if [ ! -d "$dest" ]; then
        echo "  Installing $label..."
        git clone "$@" "$url" "$dest"
    else
        echo "  Updating $label..."
        git -C "$dest" pull --ff-only 2>/dev/null || echo "  $label pull skipped"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Steps
# ──────────────────────────────────────────────────────────────────────────────

step_packages() {
    pkg update -y

    # Core: everything Tier 1 needs. clang/make/binutils are the toolchain
    # for pip source builds and treesitter parser compilation.
    pkg install -y \
        git curl wget zip unzip tree stow \
        zsh tmux \
        neovim python \
        clang make binutils pkg-config \
        nodejs \
        ripgrep fd bat fzf jq \
        openssh termux-api termux-tools
}

step_candidate_packages() {
    # Packages expected in the Termux repo but unverified by name; each is
    # installed independently so one miss doesn't fail the rest. A miss is
    # reported, not fatal — the nvim config degrades gracefully without them.
    local candidates=(eza lua-language-server stylua ruff)
    local missing=()
    for p in "${candidates[@]}"; do
        if pkg install -y "$p" 2>/dev/null; then
            echo "  installed: $p"
        else
            echo "  not available in pkg: $p"
            missing+=("$p")
        fi
    done
    [ ${#missing[@]} -gt 0 ] && echo "  Missing candidates: ${missing[*]} (find alternatives or drop)"
    return 0
}

step_font() {
    # NeoVim devicons and `eza --icons` need a Nerd Font or they render tofu.
    # Termux picks up ~/.termux/font.ttf automatically.
    if [ -f "$HOME/.termux/font.ttf" ]; then
        echo "  font.ttf already installed"
        return 0
    fi
    echo "  Installing JetBrainsMono Nerd Font..."
    local tmp; tmp=$(mktemp -d)
    (
        cd "$tmp"
        curl -fLO "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
        unzip -o JetBrainsMono.zip "JetBrainsMonoNerdFont-Regular.ttf"
        mkdir -p "$HOME/.termux"
        mv JetBrainsMonoNerdFont-Regular.ttf "$HOME/.termux/font.ttf"
    )
    rm -rf "$tmp"
    command -v termux-reload-settings &>/dev/null && termux-reload-settings
}

step_termux_properties() {
    # On-screen keyboard needs ESC/CTRL for vim and the tmux prefix.
    local props="$HOME/.termux/termux.properties"
    mkdir -p "$HOME/.termux"
    if [ -f "$props" ] && grep -q '^extra-keys' "$props"; then
        echo "  extra-keys already configured"
        return 0
    fi
    echo "  Adding extra-keys row..."
    cat >> "$props" <<'EOF'

# Keys vim/tmux need that the stock keyboard lacks
extra-keys = [['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]
EOF
    command -v termux-reload-settings &>/dev/null && termux-reload-settings
}

step_stow() {
    echo "  Stowing dotfiles packages (shell, tmux, isort)..."
    make -C "$DOTFILES_DIR" clean-stow
    make -C "$DOTFILES_DIR" stow-shell stow-tmux stow-isort
}

step_zsh() {
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo "  Installing oh-my-zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        echo "  Updating oh-my-zsh..."
        git -C "$HOME/.oh-my-zsh" pull --ff-only 2>/dev/null || echo "  oh-my-zsh pull skipped (local changes)"
    fi

    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    for plugin in zsh-syntax-highlighting zsh-completions zsh-autosuggestions; do
        git_clone_or_pull "$plugin" "https://github.com/zsh-users/$plugin.git" "$zsh_custom/plugins/$plugin"
    done

    # oh-my-zsh --unattended replaces ~/.zshrc with a real file; restow ours.
    make -C "$DOTFILES_DIR" clean-stow
    make -C "$DOTFILES_DIR" stow-shell stow-tmux stow-isort

    # Termux has no /etc/passwd; termux-tools ships its own chsh.
    if [ "$(basename "${SHELL:-}")" != "zsh" ]; then
        echo "  Setting zsh as login shell..."
        chsh -s zsh
    fi
}

step_nvim_config() {
    mkdir -p "$HOME/.config"
    git_clone_or_pull "NeoVim config" "https://github.com/ThoDHa/nvim.git" "$HOME/.config/nvim"
}

step_nvim_python() {
    # set.lua points python3_host_prog at this exact venv path.
    local venv="$HOME/.local/share/nvim/venv"
    if [ ! -d "$venv" ]; then
        echo "  Creating NeoVim Python venv..."
        mkdir -p "$HOME/.local/share/nvim"
        python -m venv "$venv"
    fi
    "$venv/bin/pip" install --quiet --upgrade pip pynvim
}

step_python_tools() {
    # The nvim config runs black+isort on every save (conform format_on_save)
    # and expects debugpy for DAP. djlint covers the HTML template chain.
    pip install --quiet --upgrade black isort debugpy djlint
}

step_node_tools() {
    # pyright is the Python LSP on this platform (`ty` has no bionic wheels).
    # The rest feed bash/JS/markdown lint+LSP wiring in the nvim config.
    npm install -g pyright || return 1
    local extras=(bash-language-server eslint_d markdownlint-cli tree-sitter-cli)
    for p in "${extras[@]}"; do
        npm install -g "$p" || echo "  npm install failed (non-fatal): $p"
    done
    return 0
}

step_tmux_plugins() {
    local tpm="$HOME/.tmux/plugins/tpm"
    mkdir -p "$HOME/.tmux/plugins"
    git_clone_or_pull "TPM" "https://github.com/tmux-plugins/tpm" "$tpm"
    echo "  Installing tmux plugins..."
    "$tpm/bin/install_plugins" || true
}

step_git_auth() {
    # A fresh Termux install has no key; grind75 (and this repo) need one.
    local key="$HOME/.ssh/id_ed25519"
    if [ -f "$key" ] || [ -f "$HOME/.ssh/id_rsa" ]; then
        echo "  SSH key already present"
        return 0
    fi
    echo "  Generating SSH key (ed25519, no passphrase)..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -f "$key" -C "termux-$(date +%Y%m%d)"
    echo ""
    echo "  Add this public key to GitHub (Settings → SSH keys):"
    echo "  ────────────────────────────────────────────────────"
    cat "$key.pub"
    echo "  ────────────────────────────────────────────────────"
}

step_verify() {
    local tools=(git zsh tmux nvim node npm fzf rg fd bat jq stow tree python pip pyright)
    local missing=()

    echo "  Tools:"
    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo "    ✓ $tool"
        else
            echo "    ✗ $tool — NOT FOUND"
            missing+=("$tool")
        fi
    done

    echo "  Configs:"
    _check_dir()  { [ -d "$1" ] && echo "    ✓ $2" || { echo "    ✗ $2 — NOT FOUND";     missing+=("$2"); }; }
    _check_file() { [ -f "$1" ] && echo "    ✓ $2" || { echo "    ✗ $2 — NOT FOUND";     missing+=("$2"); }; }
    _check_link() { [ -L "$1" ] && echo "    ✓ $2" || { echo "    ✗ $2 — NOT A SYMLINK"; missing+=("$2"); }; }

    _check_dir  "$HOME/.config/nvim"           "nvim config"
    _check_dir  "$HOME/.oh-my-zsh"             "oh-my-zsh"
    _check_dir  "$HOME/.tmux/plugins/tpm"      "TPM"
    _check_dir  "$HOME/.local/share/nvim/venv" "nvim python venv"
    _check_link "$HOME/.zshrc"                 ".zshrc symlink"
    _check_link "$HOME/.tmux.conf"             ".tmux.conf symlink"
    _check_file "$HOME/.termux/font.ttf"       "Nerd Font"

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing: ${missing[*]}"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             Termux Dev Environment Setup & Update             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

run_step "Core packages"          step_packages
run_step "Candidate packages"     step_candidate_packages
run_step "Nerd Font"              step_font
run_step "Termux extra keys"      step_termux_properties
run_step "Stow dotfiles"          step_stow
run_step "Zsh + oh-my-zsh"        step_zsh
run_step "NeoVim config"          step_nvim_config
run_step "NeoVim Python provider" step_nvim_python
run_step "Python tools"           step_python_tools
run_step "Node tools + LSP"       step_node_tools
run_step "Tmux plugins"           step_tmux_plugins
run_step "Git authentication"     step_git_auth
run_step "Verification"           step_verify

echo ""
if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Setup Complete! 🎉                         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║             Setup completed with failures                     ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}Failed steps:${NC}"
    for s in "${FAILED_STEPS[@]}"; do
        echo "  • $s"
    done
    echo ""
    echo "Fix the issues above and re-run to retry."
fi

echo ""
echo "Next steps:"
echo "  1. Restart Termux (so the font, keys, and login shell apply)"
echo "  2. Add the SSH public key above to GitHub, then:"
echo "       git clone git@github.com:ThoDHa/grind75.git"
echo "  3. Open tmux and press:   prefix + I  (install plugins)"
echo "  4. Open nvim:             Lazy will auto-install plugins"
echo ""

[ ${#FAILED_STEPS[@]} -eq 0 ]
