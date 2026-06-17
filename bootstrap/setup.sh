#!/bin/bash
#
# Complete development environment setup
# Idempotent — safe to run multiple times from any directory.
#
# Usage:
#   ./bootstrap/setup.sh
#   make bootstrap
#

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

# ── Session PATH ──────────────────────────────────────────────────────────────
export PATH="$HOME/.fzf/bin:$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"   # load NVM if already installed

# ── Shared helpers ────────────────────────────────────────────────────────────

# Clone a repo if the destination is absent, otherwise pull.
# Extra args after <dest> are forwarded to git clone (e.g. --depth 1).
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

# Fetch the latest release tag for a GitHub repo, falling back to <fallback>.
gh_latest_tag() {
    local repo="$1" fallback="$2"
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -n "$tag" ] && echo "$tag" || echo "$fallback"
}

_install_nvim() {
    local version="$1"
    echo "  Installing NeoVim $version..."
    local tmp; tmp=$(mktemp -d)
    (
        cd "$tmp"
        curl -fLO "https://github.com/neovim/neovim/releases/download/${version}/nvim-linux-x86_64.appimage"
        chmod u+x nvim-linux-x86_64.appimage
        ./nvim-linux-x86_64.appimage --appimage-extract
        sudo rm -rf /opt/nvim
        sudo mv squashfs-root /opt/nvim
        sudo ln -sf /opt/nvim/AppRun /usr/local/bin/nvim
    )
    rm -rf "$tmp"
}

_install_eza() {
    local version="$1" arch="$2"
    local tmp; tmp=$(mktemp -d)
    (
        cd "$tmp"
        if curl -fLO "https://github.com/eza-community/eza/releases/download/${version}/eza_${arch}.tar.gz"; then
            tar -xzf "eza_${arch}.tar.gz"
            sudo mv eza /usr/local/bin/
            echo "  eza $version installed"
        else
            echo "  eza download failed — skipping"
        fi
    )
    rm -rf "$tmp"
}

# ──────────────────────────────────────────────────────────────────────────────
# Steps
# ──────────────────────────────────────────────────────────────────────────────

step_stow() {
    if ! command -v stow &>/dev/null; then
        echo "  Installing stow..."
        sudo apt-get update -q
        sudo apt-get install -y stow
    fi

    echo "  Stowing dotfiles packages..."
    make -C "$DOTFILES_DIR" clean-stow
    make -C "$DOTFILES_DIR" stow
}

step_system_packages() {
    sudo apt-get update -q
    sudo apt-get install -y \
        git curl wget zip unzip tree stow \
        zsh tmux \
        gcc python3 python3-venv python3-dev python3-pip default-jdk \
        ripgrep fd-find bat

    # Debian/Ubuntu ship bat as batcat
    if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
        sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
        echo "  Created bat -> batcat symlink"
    fi
}

step_nvim_python() {
    local venv="$HOME/.local/share/nvim/venv"
    if [ ! -d "$venv" ]; then
        echo "  Creating NeoVim Python venv..."
        mkdir -p "$HOME/.local/share/nvim"
        python3 -m venv "$venv"
    fi
    if "$venv/bin/python" -c "import pip" 2>/dev/null; then
        "$venv/bin/pip" install --quiet --upgrade pip pynvim
    else
        echo "  pip unavailable in venv — skipping pynvim (recreate venv manually if needed)"
    fi
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

    # oh-my-zsh --unattended replaces ~/.zshrc with a real file; delegate
    # removal to clean-stow (the single authoritative place) before restowing.
    make -C "$DOTFILES_DIR" clean-stow
    make -C "$DOTFILES_DIR" restow-shell

    if [ "$SHELL" != "$(command -v zsh)" ]; then
        echo "  Setting zsh as default shell..."
        chsh -s "$(command -v zsh)"
    fi
}

step_fzf() {
    git_clone_or_pull "fzf" "https://github.com/junegunn/fzf.git" "$HOME/.fzf" --depth 1
    if ! command -v fzf &>/dev/null; then
        yes | "$HOME/.fzf/install" --no-update-rc
    fi
}

step_tmux() {
    local tpm="$HOME/.tmux/plugins/tpm"
    mkdir -p "$HOME/.tmux/plugins"
    git_clone_or_pull "TPM" "https://github.com/tmux-plugins/tpm" "$tpm"

    if command -v tmux &>/dev/null; then
        echo "  Installing tmux plugins..."
        "$tpm/bin/install_plugins" || true
    fi
}

step_nvm() {
    local target="0.40.3"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    if [ "$(nvm --version 2>/dev/null)" != "$target" ]; then
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${target}/install.sh" | bash
        \. "$NVM_DIR/nvm.sh"
    fi
    echo "  Installing Node.js LTS..."
    nvm install --lts
    nvm install-latest-npm
    npm install -g neovim tree-sitter-cli
}

step_neovim() {
    local latest current=""
    latest=$(gh_latest_tag "neovim/neovim" "v0.10.2")
    command -v nvim &>/dev/null \
        && current=$(nvim --version 2>/dev/null | sed -nE 's/NVIM (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p')

    if [ "$current" = "$latest" ]; then
        echo "  NeoVim $current is up to date"
    else
        [ -n "$current" ] && echo "  Upgrading NeoVim $current → $latest..." \
                          || echo "  Installing NeoVim $latest..."
        _install_nvim "$latest"
    fi

    mkdir -p "$HOME/.config"
    git_clone_or_pull "NeoVim config" "https://github.com/ThoDHa/nvim.git" "$HOME/.config/nvim"
}

step_eza() {
    local latest arch
    latest=$(gh_latest_tag "eza-community/eza" "v0.20.8")

    case "$(uname -m)" in
        x86_64)  arch="x86_64-unknown-linux-gnu" ;;
        aarch64) arch="aarch64-unknown-linux-gnu" ;;
        armv7l)  arch="arm-unknown-linux-gnueabihf" ;;
        *)
            echo "  Unsupported arch for eza — skipping"
            return 0
            ;;
    esac

    if ! command -v eza &>/dev/null; then
        _install_eza "$latest" "$arch"
    else
        local current
        current=$(eza --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^/v/')
        if [ "$current" = "$latest" ]; then
            echo "  eza $current is up to date"
        else
            echo "  Upgrading eza $current → $latest..."
            _install_eza "$latest" "$arch"
        fi
    fi
}

step_opencode() {
    if ! command -v opencode &>/dev/null; then
        echo "  Installing opencode..."
        curl -fsSL https://opencode.ai/install | bash
        return
    fi
    local current latest
    current=$(opencode --version 2>/dev/null | head -1)
    latest=$(curl -fsSL https://api.github.com/repos/sst/opencode/releases/latest 2>/dev/null \
        | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' | head -1)
    if [ -z "$latest" ]; then
        echo "  Could not fetch opencode version — skipping update"
    elif [ "$current" = "$latest" ]; then
        echo "  opencode $current is up to date"
    else
        echo "  Upgrading opencode $current → $latest..."
        curl -fsSL https://opencode.ai/install | bash
    fi
}

step_claude() {
    if ! command -v claude &>/dev/null; then
        echo "  Installing claude..."
        curl -fsSL https://claude.ai/install.sh | bash
        return
    fi
    local current latest
    current=$(claude --version 2>/dev/null | awk '{print $1}')
    latest=$(curl -fsSL https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null \
        | grep -o '"version":"[^"]*"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$latest" ]; then
        echo "  Could not fetch claude version — skipping update"
    elif [ "$current" = "$latest" ]; then
        echo "  claude $current is up to date"
    else
        echo "  Upgrading claude $current → $latest..."
        curl -fsSL https://claude.ai/install.sh | bash
    fi
}

step_claude_stow() {
    if [ -d "$DOTFILES_DIR/claudecode" ]; then
        make -C "$DOTFILES_DIR" stow-claudecode
    else
        echo "  claudecode package not found in dotfiles — skipping"
    fi
}

step_docker() {
    . /etc/os-release

    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL "https://download.docker.com/linux/$ID/gpg" \
            | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi

    sudo apt-get update -q
    sudo apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    if ! id -nG "$USER" | grep -qw docker; then
        sudo usermod -aG docker "$USER"
        echo "  Added $USER to docker group (run 'newgrp docker' or log out/in)"
    else
        echo "  $USER already in docker group"
    fi

    sudo systemctl enable --now docker 2>/dev/null \
        || sudo service docker start 2>/dev/null \
        || echo "  Could not auto-start docker — start manually if needed"
}

step_verify() {
    local tools=(git zsh tmux nvim node fzf rg fdfind bat eza stow tree docker opencode claude)
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
    _check_link() { [ -L "$1" ] && echo "    ✓ $2" || { echo "    ✗ $2 — NOT A SYMLINK"; missing+=("$2"); }; }

    _check_dir  "$HOME/.config/nvim"           "nvim config"
    _check_dir  "$HOME/.oh-my-zsh"             "oh-my-zsh"
    _check_dir  "$HOME/.tmux/plugins/tpm"      "TPM"
    _check_dir  "$HOME/.local/share/nvim/venv" "nvim python venv"
    _check_link "$HOME/.zshrc"                 ".zshrc symlink"

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
echo -e "${GREEN}║               Dev Environment Setup & Update                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

run_step "Stow dotfiles"          step_stow
run_step "System packages"        step_system_packages
run_step "NeoVim Python provider" step_nvim_python
run_step "Zsh + oh-my-zsh"       step_zsh
run_step "fzf"                    step_fzf
run_step "Tmux + TPM"            step_tmux
run_step "NVM + Node.js"         step_nvm

# Reload NVM in this shell so verification and later steps can use node/npm
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

run_step "NeoVim"                 step_neovim
run_step "eza"                    step_eza
run_step "OpenCode"               step_opencode
run_step "Claude Code"            step_claude
run_step "Claude Code config"     step_claude_stow
run_step "Docker"                 step_docker
run_step "Verification"           step_verify

echo ""
if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Setup Complete! 🎉                         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║            Setup completed with failures                       ║${NC}"
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
echo "  1. Restart your shell:         exec zsh"
echo "  2. Open tmux and press:        prefix + I  (install plugins)"
echo "  3. Open nvim:                  Lazy will auto-install plugins"
echo "  4. Activate docker (if new):   newgrp docker  (or log out and back in)"
echo ""

[ ${#FAILED_STEPS[@]} -eq 0 ]
