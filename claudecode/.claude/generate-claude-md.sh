#!/bin/bash
# Generate CLAUDE.md from opencode rules
# Combines all rule files into a single document for Claude Code

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Paths - detect if we're in repo or stowed location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.dotfiles")"

# Source rules from stowed location (what opencode actually uses); fall back
# to the repo copy when the opencode package is not stowed (opencode absent).
RULES_DIR="$HOME/.config/opencode/rules"
if [ ! -d "$RULES_DIR" ]; then
    RULES_DIR="$DOTFILES_REPO/opencode/.config/opencode/rules"
    echo "  opencode rules not stowed — using repo copy: $RULES_DIR"
fi
OUTPUT_FILE="$HOME/.claude/CLAUDE.md"

echo -e "${YELLOW}Generating CLAUDE.md for Claude Code...${NC}"
echo "  Rules source: $RULES_DIR"
echo "  Output: $OUTPUT_FILE"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Generate header
cat > "$OUTPUT_FILE" << 'EOF'
# Claude Code Instructions

*This file is auto-generated from opencode rules. Run `make sync-claudecode` to regenerate.*

This document combines all opencode behavioral rules, coding standards, and configuration into a single Claude Code instruction file.

EOF

# Add all rule files: core.md first, then the rest alphabetically (auto-discovered)
RULE_FILES=$(ls -1 "$RULES_DIR"/*.md 2>/dev/null | xargs -n1 basename | sort)
if [ -f "$RULES_DIR/core.md" ]; then
    RULE_FILES="core.md $(echo "$RULE_FILES" | grep -v '^core.md$')"
fi

if [ -z "$RULE_FILES" ]; then
    echo -e "${RED}  Error: no rule files found in $RULES_DIR${NC}"
    exit 1
fi

for rule_file in $RULE_FILES; do
    rule_path="$RULES_DIR/$rule_file"
    echo "" >> "$OUTPUT_FILE"
    echo "## Rule File: $rule_file" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    cat "$rule_path" >> "$OUTPUT_FILE"
done

echo -e "${GREEN}✓ CLAUDE.md generated successfully${NC}"
echo ""
echo "Rules included:"
ls -1 "$RULES_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/^/  - /' || echo "  (no rules found)"
