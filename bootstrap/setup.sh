#!/bin/bash
#
# Complete development environment setup
# Installs and updates all tools needed for the dotfiles setup
#
# Usage:
#   ./bootstrap/setup.sh
#
# Prerequisites:
#   1. Clone repo:    git clone https://github.com/ThoDHa/dotfiles.git ~/dotfiles
#   2. Stow configs:  cd ~/dotfiles && make stow
#   3. Run this:      ./bootstrap/setup.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║               Dev Environment Setup & Update                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if configs are stowed
if [ ! -L "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc" ]; then
    print_error "Configs not found! Run 'make stow' first."
    echo ""
    echo "  cd ~/dotfiles"
    echo "  make stow"
    echo "  ./bootstrap/setup.sh"
    echo ""
    exit 1
fi

# Step 1: System packages
print_step "Installing/updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y \
    git curl wget zip unzip tree stow \
    zsh tmux \
    gcc python3 python3-venv python3-dev python3-pip default-jdk \
    ripgrep fd-find bat
print_success "System packages up to date"

# Step 2: NeoVim Python provider
print_step "Setting up NeoVim Python provider..."
NVIM_VENV="$HOME/.local/share/nvim/venv"
if [ ! -d "$NVIM_VENV" ]; then
    echo "  Creating NeoVim Python venv..."
    mkdir -p "$HOME/.local/share/nvim"
    python3 -m venv "$NVIM_VENV"
    "$NVIM_VENV/bin/pip" install --upgrade pip
    "$NVIM_VENV/bin/pip" install pynvim
else
    echo "  NeoVim Python venv already exists"
    # Ensure pynvim is installed (only if pip works)
    if "$NVIM_VENV/bin/python" -c "import pip" 2>/dev/null; then
        "$NVIM_VENV/bin/pip" install --quiet --upgrade pynvim
    else
        echo "  Skipping pynvim installation (pip is broken, recreate venv manually if needed)"
    fi
fi
print_success "NeoVim Python provider configured"

# Step 3: oh-my-zsh and plugins
print_step "Setting up Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "  Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "  Updating oh-my-zsh..."
    git -C "$HOME/.oh-my-zsh" pull --ff-only || echo "  oh-my-zsh update skipped (local changes)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Install or update plugins
for plugin in "zsh-syntax-highlighting" "zsh-completions" "zsh-autosuggestions"; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        echo "  Installing $plugin..."
        git clone "https://github.com/zsh-users/$plugin.git" "$ZSH_CUSTOM/plugins/$plugin"
    else
        echo "  Updating $plugin..."
        git -C "$ZSH_CUSTOM/plugins/$plugin" pull --ff-only || echo "  $plugin update skipped (local changes)"
    fi
done

# Set zsh as default shell
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "  Setting zsh as default shell..."
    chsh -s "$(which zsh)"
fi
print_success "Zsh configured"

# Restow shell package to ensure PATH updates take effect
if [ -d "$HOME/.dotfiles" ]; then
    print_step "Restowing shell package for PATH updates..."
    make restow-shell
    print_success "Shell package restowed"
fi

# Step 4: fzf
print_step "Installing/updating fzf..."
if [ ! -d "$HOME/.fzf" ]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    yes | "$HOME/.fzf/install" --no-update-rc
else
    echo "  Updating fzf..."
    git -C "$HOME/.fzf" pull --ff-only || echo "  fzf git update skipped (local changes)"
    yes | "$HOME/.fzf/install" --no-update-rc
fi
print_success "fzf installed"

# Step 5: tmux and TPM
print_step "Setting up Tmux..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "  Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
    echo "  Updating TPM..."
    git -C "$HOME/.tmux/plugins/tpm" pull --ff-only || echo "  TPM update skipped (local changes)"
fi

# Install/update plugins if tmux is available
if command -v tmux &> /dev/null; then
    echo "  Installing tmux plugins..."
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" || true
fi
print_success "Tmux configured"

# Step 6: NVM and Node.js
print_step "Installing/updating NVM..."
export NVM_DIR="$HOME/.nvm"

if [ ! -d "$NVM_DIR" ]; then
    echo "  Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
else
    echo "  Updating NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

# Load NVM
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo "  Ensuring Node.js LTS is current..."
nvm install --lts
nvm install-latest-npm

# Install/update global npm packages for Neovim
echo "  Installing/updating neovim npm package..."
npm install -g neovim
echo "  Installing/updating tree-sitter-cli..."
npm install -g tree-sitter-cli
print_success "NVM configured"

# Step 7: NeoVim
print_step "Installing/updating NeoVim..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v0.10.2")

install_nvim() {
    local version="$1"
    echo "  Installing NeoVim $version..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    curl -LO "https://github.com/neovim/neovim/releases/download/${version}/nvim-linux-x86_64.appimage"
    chmod u+x nvim-linux-x86_64.appimage
    ./nvim-linux-x86_64.appimage --appimage-extract

    sudo rm -rf /opt/nvim
    sudo mv squashfs-root /opt/nvim
    sudo ln -sf /opt/nvim/AppRun /usr/local/bin/nvim

    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    echo "  NeoVim $version installed to /opt/nvim"
}

if command -v nvim &> /dev/null; then
    CURRENT_VERSION=$(nvim --version | head -1 | sed -E 's/NVIM (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/' || echo "unknown")
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "  NeoVim $CURRENT_VERSION is already up to date"
    else
        echo "  NeoVim $CURRENT_VERSION found, upgrading to $LATEST_VERSION..."
        install_nvim "$LATEST_VERSION"
    fi
else
    install_nvim "$LATEST_VERSION"
fi

# Clone nvim config if not present
if [ ! -d "$HOME/.config/nvim" ]; then
    echo "  Cloning NeoVim config..."
    mkdir -p "$HOME/.config"
    git clone https://github.com/ThoDHa/nvim.git "$HOME/.config/nvim"
else
    echo "  NeoVim config already exists"
fi

print_success "NeoVim installed (plugins will install on first run)"

# Step 8: eza (modern ls replacement)
print_step "Installing/updating eza..."

get_eza_version() {
    curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v0.20.8"
}

install_eza() {
    local version="$1"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  EZA_ARCH="x86_64-unknown-linux-gnu" ;;
        aarch64) EZA_ARCH="aarch64-unknown-linux-gnu" ;;
        armv7l)  EZA_ARCH="arm-unknown-linux-gnueabihf" ;;
        *)
            print_error "Unsupported architecture for eza: $ARCH"
            echo "  Skipping eza installation"
            return 1
            ;;
    esac

    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    if curl -fLO "https://github.com/eza-community/eza/releases/download/${version}/eza_${EZA_ARCH}.tar.gz"; then
        tar -xzf "eza_${EZA_ARCH}.tar.gz"
        sudo mv eza /usr/local/bin/
        echo "  eza $version installed to /usr/local/bin/eza"
    else
        print_error "Failed to download eza"
        echo "  Continuing without eza..."
    fi

    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

EZA_LATEST=$(get_eza_version)

if ! command -v eza &> /dev/null; then
    install_eza "$EZA_LATEST"
else
    EZA_CURRENT=$(eza --version 2>&1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^/v/')
    if [ "$EZA_CURRENT" = "$EZA_LATEST" ]; then
        echo "  eza $EZA_CURRENT is already up to date"
    else
        echo "  eza $EZA_CURRENT found, upgrading to $EZA_LATEST..."
        install_eza "$EZA_LATEST"
    fi
fi
print_success "eza configured"

# Step 9: OpenCode installation
print_step "Setting up OpenCode..."
echo "  Installing/updating opencode..."
curl -fsSL https://opencode.ai/install | bash
print_success "OpenCode installed"

# Step 10: Claude Code installation
print_step "Setting up Claude Code..."
echo "  Installing/updating claude..."
curl -fsSL https://claude.ai/install.sh | bash
print_success "Claude Code installed"

# Step 11: Stow claudecode package and sync config
print_step "Stowing Claude Code configuration..."

if [ -d "$HOME/.dotfiles/claudecode" ]; then
    echo "  Stowing claudecode package..."
    make stow-claudecode
else
    echo "  Claude Code config not found in dotfiles (this is OK)"
fi

print_success "Claude Code configuration set up"

# Step 12: Post-install verification
print_step "Verifying installation..."
echo "  Checking installed tools..."

# Check critical tools
TOOLS_TO_CHECK=("git" "zsh" "tmux" "nvim" "node" "fzf" "rg" "fdfind" "batcat" "eza" "stow" "tree" "opencode" "claude")
FAILED_TOOLS=()

for tool in "${TOOLS_TO_CHECK[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "  ✓ $tool: $(command -v "$tool")"
    else
        echo "  ✗ $tool: NOT FOUND"
        FAILED_TOOLS+=("$tool")
    fi
done

# Check key directories/files
echo "  Checking configurations..."
if [ -d "$HOME/.config/nvim" ]; then
    echo "  ✓ NeoVim config: $HOME/.config/nvim"
else
    echo "  ✗ NeoVim config: NOT FOUND"
    FAILED_TOOLS+=("nvim-config")
fi

if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "  ✓ oh-my-zsh: $HOME/.oh-my-zsh"
else
    echo "  ✗ oh-my-zsh: NOT FOUND"
    FAILED_TOOLS+=("oh-my-zsh")
fi

if [ -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "  ✓ TPM: $HOME/.tmux/plugins/tpm"
else
    echo "  ✗ TPM: NOT FOUND"
    FAILED_TOOLS+=("tpm")
fi

if [ -d "$HOME/.local/share/nvim/venv" ]; then
    echo "  ✓ NeoVim Python venv: $HOME/.local/share/nvim/venv"
else
    echo "  ✗ NeoVim Python venv: NOT FOUND"
    FAILED_TOOLS+=("nvim-python-venv")
fi

if [ ${#FAILED_TOOLS[@]} -eq 0 ]; then
    print_success "All tools verified successfully!"
else
    print_error "Some tools failed verification: ${FAILED_TOOLS[*]}"
    echo "  You may need to restart your shell or check the installation logs above"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete! 🎉                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart your shell:         exec zsh"
echo "  2. Open tmux and press:        prefix + I (to install plugins)"
echo "  3. Open nvim:                  Lazy will auto-install plugins"
echo ""
echo "All Node.js tools are now available for NeoVim plugins!"
echo "Modern tools installed: stow, eza (ls replacement), fzf, ripgrep, fd, bat, tree"
echo ""
