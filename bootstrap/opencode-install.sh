#!/bin/bash
#
# OpenCode configuration symlink setup
#
# Creates symlinks for opencode config files.
# Cannot use stow because ~/.opencode contains runtime files (node_modules, etc.)
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Determine script and repo location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

print_step "Setting up OpenCode symlinks..."

# Create ~/.local/bin if needed
mkdir -p "$HOME/.local/bin"

# Create ~/.opencode if needed (opencode may not have run yet)
mkdir -p "$HOME/.opencode"

# Symlink opencode binary
ln -sf "$REPO_DIR/opencode/.local/bin/opencode" "$HOME/.local/bin/opencode"
echo "  Linked: ~/.local/bin/opencode"

# Symlink rules directory
ln -sf "$REPO_DIR/opencode/.opencode/rules" "$HOME/.opencode/rules"
echo "  Linked: ~/.opencode/rules"

# Symlink opencode.json
ln -sf "$REPO_DIR/opencode/.opencode/opencode.json" "$HOME/.opencode/opencode.json"
echo "  Linked: ~/.opencode/opencode.json"

print_success "OpenCode symlinks created!"
