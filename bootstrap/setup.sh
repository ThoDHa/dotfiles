#!/bin/bash
#
# Complete development environment setup
# Idempotent — safe to run multiple times from any directory.
#
# Usage:
#   ./bootstrap/setup.sh
#   make bootstrap
#

# Fail loudly on unset variables and failed pipelines. -e is safe at top
# level: run_step runs each step in an if-guarded subshell with its own
# `set -e`, so one failed step is reported and the remaining steps still run.
set -euo pipefail

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

# Ask a yes/no question. Args: <question> [default:y|n]
# Non-interactive stdin falls back to the default so scripted runs keep working.
prompt_yes_no() {
    local question="$1" default="${2:-y}" hint answer
    [ "$default" = "y" ] && hint="[Y/n]" || hint="[y/N]"
    if [ ! -t 0 ]; then
        echo "  $question $hint — non-interactive, using default"
        [ "$default" = "y" ] && return 0 || return 1
    fi
    read -r -p "  $question $hint " answer
    answer="${answer:-$default}"
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

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
    if ! tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'); then
        echo "  WARNING: could not fetch latest tag for $repo — falling back to $fallback" >&2
    fi
    [ -n "$tag" ] && echo "$tag" || echo "$fallback"
}

_install_nvim() {
    local version="$1"
    echo "  Installing NeoVim $version..."
    (
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        cd "$tmp"
        curl -fLO "https://github.com/neovim/neovim/releases/download/${version}/nvim-linux-x86_64.appimage"
        chmod u+x nvim-linux-x86_64.appimage
        ./nvim-linux-x86_64.appimage --appimage-extract
        sudo rm -rf /opt/nvim
        sudo mv squashfs-root /opt/nvim
        sudo ln -sf /opt/nvim/AppRun /usr/local/bin/nvim
    )
}

_install_eza() {
    local version="$1" arch="$2"
    (
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        cd "$tmp"
        if curl -fLO "https://github.com/eza-community/eza/releases/download/${version}/eza_${arch}.tar.gz"; then
            tar -xzf "eza_${arch}.tar.gz"
            sudo mv eza /usr/local/bin/
            echo "  eza $version installed"
        else
            echo "  eza download failed — skipping"
        fi
    )
}

# Checksum of the carried tmux patches; part of the build stamp so that a
# patch change triggers a rebuild even when the tmux version is unchanged.
_tmux_patch_sum() {
    local sum
    if ! sum=$(cat "$DOTFILES_DIR"/bootstrap/patches/tmux-*.patch 2>/dev/null | md5sum | awk '{print $1}'); then
        echo "  No tmux patches found in $DOTFILES_DIR/bootstrap/patches" >&2
        return 1
    fi
    echo "$sum"
}

_install_tmux() {
    local version="$1" p
    echo "  Building tmux $version from source..."
    local -a tmux_patches=()
    for p in "$DOTFILES_DIR"/bootstrap/patches/tmux-*.patch; do
        if [ -e "$p" ]; then tmux_patches+=("$p"); fi
    done
    if [ ${#tmux_patches[@]} -eq 0 ]; then
        echo "  No tmux patches found in $DOTFILES_DIR/bootstrap/patches — refusing to build unpatched" >&2
        return 1
    fi
    (
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        cd "$tmp"
        curl -fLO "https://github.com/tmux/tmux/releases/download/${version}/tmux-${version}.tar.gz"
        tar -xzf "tmux-${version}.tar.gz"
        cd "tmux-${version}"
        for p in "${tmux_patches[@]}"; do
            echo "  Applying $(basename "$p")..."
            patch -p1 < "$p"
        done
        ./configure
        make -j"$(nproc)"
        sudo make install
    )
    mkdir -p "$HOME/.local/state/dotfiles"
    echo "$version $(_tmux_patch_sum)" > "$HOME/.local/state/dotfiles/tmux-build-stamp"
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
    local force_flags=()
    [ "$WANT_OPENCODE" = "1" ] && force_flags+=(FORCE_OPENCODE=1)
    [ "$WANT_CLAUDE"   = "1" ] && force_flags+=(FORCE_CLAUDECODE=1)
    make -C "$DOTFILES_DIR" stow "${force_flags[@]}"
}

step_system_packages() {
    sudo apt-get update -q
    # util-linux provides flock, used by the tasks board tool's dashboard lock.
    # libevent-dev/libncurses-dev/bison/pkg-config are tmux build deps: tmux is
    # built from source in step_tmux rather than installed from apt.
    sudo apt-get install -y \
        git curl wget zip unzip tree stow patch \
        zsh \
        gcc make python3 python3-venv python3-dev python3-pip default-jdk \
        ripgrep fd-find bat util-linux \
        libevent-dev libncurses-dev bison pkg-config

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

    # SKIP_CHSH=1 (set by the Docker build) opts out: chsh does not work
    # inside a container.
    if [ "${SKIP_CHSH:-0}" != "1" ] && [ "${SHELL:-}" != "$(command -v zsh)" ]; then
        echo "  Setting zsh as default shell..."
        chsh -s "$(command -v zsh)"
    fi
}

step_fzf() {
    git_clone_or_pull "fzf" "https://github.com/junegunn/fzf.git" "$HOME/.fzf" --depth 1
    if ! command -v fzf &>/dev/null; then
        # The installer exits once it has its answers, so `yes` dies by
        # SIGPIPE (141) on success; keep pipefail from reporting that as
        # an installer failure.
        local status=0
        yes | "$HOME/.fzf/install" --no-update-rc || status=$?
        [ "$status" -eq 141 ] && status=0
        return "$status"
    fi
}

step_tmux() {
    # Built from source for two reasons:
    #   1. Ubuntu ships tmux 3.6, which leaks fragmented OSC color replies
    #      into panes as literal keystrokes over slow links (SSH). Fixed
    #      upstream in 3.7 (tmux/tmux#4749).
    #   2. bootstrap/patches/ carries fixes not yet upstream (duplicate DA
    #      replies from ConPTY/Windows Terminal leaking into panes), so the
    #      source build stays even once the distro package reaches 3.7+.
    local latest current="" stamp="" want
    latest=$(gh_latest_tag "tmux/tmux" "3.7b")
    command -v tmux &>/dev/null && current=$(tmux -V 2>/dev/null | awk '{print $2}' || true)
    want="$latest $(_tmux_patch_sum)"
    [ -f "$HOME/.local/state/dotfiles/tmux-build-stamp" ] \
        && stamp=$(cat "$HOME/.local/state/dotfiles/tmux-build-stamp")

    if [ "$current" = "$latest" ] && [ "$stamp" = "$want" ]; then
        echo "  tmux $current is up to date (patches applied)"
    else
        [ -n "$current" ] && echo "  Upgrading tmux $current → $latest..." \
                          || echo "  Installing tmux $latest..."
        _install_tmux "$latest"
    fi

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
        && current=$(nvim --version 2>/dev/null | sed -nE 's/NVIM (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p' || true)

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
        current=$(eza --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^/v/' || true)
        if [ "$current" = "$latest" ]; then
            echo "  eza $current is up to date"
        else
            echo "  Upgrading eza $current → $latest..."
            _install_eza "$latest" "$arch"
        fi
    fi
}

# Fetch <url> to a temp file and execute it. The floating installers always
# install the latest release; the temp file keeps nothing piped straight from
# the network into a shell.
_run_floating_installer() {
    (
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        cd "$tmp"
        curl -fsSL "$1" -o install.sh
        bash install.sh
    )
}

step_opencode() {
    if ! command -v opencode &>/dev/null; then
        echo "  Installing opencode..."
        _run_floating_installer "https://opencode.ai/install"
        return
    fi
    local current latest
    current=$(opencode --version 2>/dev/null | head -1 | awk '{print $1}' || true)
    latest=$(curl -fsSL https://api.github.com/repos/sst/opencode/releases/latest 2>/dev/null \
        | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' | head -1 || true)
    if [ -z "$latest" ]; then
        echo "  Could not fetch opencode version — skipping update"
    elif [ "$current" = "$latest" ]; then
        echo "  opencode $current is up to date"
    else
        echo "  Upgrading opencode $current → $latest..."
        _run_floating_installer "https://opencode.ai/install"
    fi
}

step_claude() {
    if ! command -v claude &>/dev/null; then
        echo "  Installing claude..."
        _run_floating_installer "https://claude.ai/install.sh"
        return
    fi
    local current latest
    current=$(claude --version 2>/dev/null | awk '{print $1}' || true)
    latest=$(curl -fsSL https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null \
        | grep -o '"version":"[^"]*"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -z "$latest" ]; then
        echo "  Could not fetch claude version — skipping update"
    elif [ "$current" = "$latest" ]; then
        echo "  claude $current is up to date"
    else
        echo "  Upgrading claude $current → $latest..."
        _run_floating_installer "https://claude.ai/install.sh"
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

    # USER is not exported in non-interactive contexts (Docker builds), so
    # resolve the invoking user from the process instead of the environment.
    local user="${USER:-$(id -un)}"

    if ! id -nG "$user" | grep -qw docker; then
        sudo usermod -aG docker "$user"
        echo "  Added $user to docker group (run 'newgrp docker' or log out/in)"
    else
        echo "  $user already in docker group"
    fi

    sudo systemctl enable --now docker 2>/dev/null \
        || sudo service docker start 2>/dev/null \
        || echo "  Could not auto-start docker — start manually if needed"
}

step_verify() {
    local tools=(git zsh tmux nvim node fzf rg fdfind bat eza stow tree docker)
    local optional_tools=()
    [ "$WANT_OPENCODE" = "1" ] && optional_tools+=(opencode)
    [ "$WANT_CLAUDE"   = "1" ] && optional_tools+=(claude)
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
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo "    ✓ $tool"
        else
            echo "    ○ $tool — not installed (optional, was not selected or install failed)"
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

print_step "Optional tools"
if command -v opencode &>/dev/null; then q="Update OpenCode?"; else q="Install OpenCode?"; fi
if prompt_yes_no "$q"; then WANT_OPENCODE=1; else WANT_OPENCODE=0; fi
if command -v claude &>/dev/null; then q="Update Claude Code?"; else q="Install Claude Code?"; fi
if prompt_yes_no "$q"; then WANT_CLAUDE=1; else WANT_CLAUDE=0; fi
echo ""
echo "  OpenCode:    $([ "$WANT_OPENCODE" = "1" ] && echo yes || echo no)"
echo "  Claude Code: $([ "$WANT_CLAUDE" = "1" ] && echo yes || echo no)"
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
if [ "$WANT_OPENCODE" = "1" ]; then run_step "OpenCode"           step_opencode; else echo "  Skipping OpenCode (not selected)"; fi
if [ "$WANT_CLAUDE"   = "1" ]; then run_step "Claude Code"        step_claude;    else echo "  Skipping Claude Code (not selected)"; fi
if [ "$WANT_CLAUDE"   = "1" ]; then run_step "Claude Code config" step_claude_stow; else echo "  Skipping Claude Code config (not selected)"; fi
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
