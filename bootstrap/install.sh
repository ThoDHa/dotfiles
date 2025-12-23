#!/bin/bash
#
# Complete development environment bootstrap
# Installs all tools needed for the dotfiles setup
#
# Usage:
#   ./bootstrap/install.sh
#
# Prerequisites:
#   1. Clone repo:    git clone https://github.com/ThoDHa/dotfiles.git ~/dotfiles
#   2. Stow configs:  cd ~/dotfiles && make stow
#   3. Run this:      ./bootstrap/install.sh
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
echo -e "${GREEN}║                 Dev Environment Bootstrap                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if configs are stowed
if [ ! -L "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc" ]; then
    print_error "Configs not found! Run 'make stow' first."
    echo ""
    echo "  cd ~/dotfiles"
    echo "  make stow"
    echo "  ./bootstrap/install.sh"
    echo ""
    exit 1
fi

# Step 1: System packages
print_step "Installing system packages..."
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y \
    git curl wget zip unzip tree stow \
    zsh tmux \
    gcc python3 python3-venv python3-dev default-jdk \
    ripgrep fd-find bat
print_success "System packages installed"

# Step 2: oh-my-zsh and plugins
print_step "Setting up Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "  Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "  oh-my-zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Install plugins if not present
for plugin in "zsh-syntax-highlighting" "zsh-completions" "zsh-autosuggestions"; do
    if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        echo "  Installing $plugin..."
        git clone "https://github.com/zsh-users/$plugin.git" "$ZSH_CUSTOM/plugins/$plugin"
    else
        echo "  $plugin already installed"
    fi
done

# Set zsh as default shell
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "  Setting zsh as default shell..."
    chsh -s "$(which zsh)"
fi
print_success "Zsh configured"

# Step 3: fzf
print_step "Installing fzf..."
if [ ! -d "$HOME/.fzf" ]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    yes | "$HOME/.fzf/install" --no-update-rc
else
    echo "  fzf already installed"
fi
print_success "fzf installed"

# Step 4: tmux and TPM
print_step "Setting up Tmux..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    echo "  Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
    echo "  TPM already installed"
fi

# Install plugins if tmux is available
if command -v tmux &> /dev/null; then
    echo "  Installing tmux plugins..."
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" || true
fi
print_success "Tmux configured"

# Step 5: NVM and Node.js
print_step "Installing NVM..."
export NVM_DIR="$HOME/.nvm"

if [ ! -d "$NVM_DIR" ]; then
    echo "  Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
else
    echo "  NVM already installed"
fi

# Load NVM
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! command -v node &> /dev/null; then
    echo "  Installing Node.js LTS..."
    nvm install --lts
    nvm install-latest-npm
else
    echo "  Node.js already installed: $(node --version)"
fi
print_success "NVM configured"

# Step 6: NeoVim
print_step "Installing NeoVim..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v0.10.2")

if command -v nvim &> /dev/null; then
    CURRENT_VERSION=$(nvim --version | head -1 | sed -E 's/NVIM (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/' || echo "unknown")
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "  NeoVim $CURRENT_VERSION already installed"
    else
        echo "  NeoVim $CURRENT_VERSION found, but $LATEST_VERSION available"
        echo "  Skipping upgrade (run manually if needed)"
    fi
else
    echo "  Installing NeoVim $LATEST_VERSION..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    curl -LO "https://github.com/neovim/neovim/releases/download/${LATEST_VERSION}/nvim-linux-x86_64.appimage"
    chmod u+x nvim-linux-x86_64.appimage
    ./nvim-linux-x86_64.appimage --appimage-extract
    
    sudo rm -rf /opt/nvim
    sudo mv squashfs-root /opt/nvim
    sudo ln -sf /opt/nvim/AppRun /usr/local/bin/nvim
    
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    echo "  NeoVim installed to /opt/nvim"
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

# Step 7: eza (modern ls replacement)
print_step "Installing eza..."
if ! command -v eza &> /dev/null; then
    echo "  Installing eza from GitHub..."
    EZA_VERSION=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v0.20.8")
    
    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  EZA_ARCH="x86_64-unknown-linux-gnu" ;;
        aarch64) EZA_ARCH="aarch64-unknown-linux-gnu" ;;
        armv7l)  EZA_ARCH="arm-unknown-linux-gnueabihf" ;;
        *)
            print_error "Unsupported architecture for eza: $ARCH"
            echo "  Skipping eza installation"
            EZA_ARCH=""
            ;;
    esac
    
    if [ -n "$EZA_ARCH" ]; then
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        
        if curl -fLO "https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_${EZA_ARCH}.tar.gz"; then
            tar -xzf "eza_${EZA_ARCH}.tar.gz"
            sudo mv eza /usr/local/bin/
            echo "  eza installed to /usr/local/bin/eza"
        else
            print_error "Failed to download eza"
            echo "  Continuing without eza..."
        fi
        
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
    fi
else
    echo "  eza already installed"
fi
print_success "eza configured"

# Step 8: OpenCode configuration
print_step "Setting up OpenCode..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/opencode-install.sh" ]; then
    "$SCRIPT_DIR/opencode-install.sh"
else
    echo "  opencode-install.sh not found, skipping"
fi
print_success "OpenCode configured"

# Step 9: Post-install verification
print_step "Verifying installation..."
echo "  Checking installed tools..."

# Check critical tools
TOOLS_TO_CHECK=("git" "zsh" "tmux" "nvim" "node" "fzf" "rg" "fdfind" "batcat" "eza" "stow" "tree")
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

if [ ${#FAILED_TOOLS[@]} -eq 0 ]; then
    print_success "All tools verified successfully!"
else
    print_error "Some tools failed verification: ${FAILED_TOOLS[*]}"
    echo "  You may need to restart your shell or check the installation logs above"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Bootstrap Complete! 🎉                     ║${NC}"
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