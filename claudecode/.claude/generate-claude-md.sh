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

# Source rules from stowed location (what opencode actually uses)
RULES_DIR="$HOME/.config/opencode/rules"
OUTPUT_FILE="$HOME/.claude/CLAUDE.md"

# Personality reference
PERSONALITY_LINK="$RULES_DIR/personality.md"
if [ -L "$PERSONALITY_LINK" ]; then
    PERSONALITY_FILE="$(readlink -f "$PERSONALITY_LINK")"
    PERSONALITY_NAME="$(basename "$PERSONALITY_FILE" .md)"
else
    PERSONALITY_NAME="default"
fi

echo -e "${YELLOW}Generating CLAUDE.md for Claude Code...${NC}"
echo "  Rules source: $RULES_DIR"
echo "  Personality: $PERSONALITY_NAME"
echo "  Output: $OUTPUT_FILE"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Generate header
cat > "$OUTPUT_FILE" << 'EOF'
# Claude Code Instructions

*This file is auto-generated from opencode rules. Run `make sync-claudecode` to regenerate.*

This document combines all opencode behavioral rules, coding standards, and configuration into a single Claude Code instruction file.

EOF

# Add personality first (if not none)
if [ "$PERSONALITY_NAME" != "default" ] && [ -f "$PERSONALITY_FILE" ]; then
    echo "" >> "$OUTPUT_FILE"
    echo "## Personality: $PERSONALITY_NAME" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    cat "$PERSONALITY_FILE" >> "$OUTPUT_FILE"
fi

# Add all other rule files (in order of importance)
for rule_file in \
    "core.md" \
    "execution-standards.md" \
    "coding-standards.md" \
    "git-protocol.md" \
    "delegation.md" \
    "task-files.md" \
    "documentation-standards.md"
do
    rule_path="$RULES_DIR/$rule_file"
    if [ -f "$rule_path" ]; then
        echo "" >> "$OUTPUT_FILE"
        echo "## Rule File: $rule_file" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        cat "$rule_path" >> "$OUTPUT_FILE"
    else
        echo -e "${YELLOW}  Warning: $rule_file not found${NC}"
    fi
done

echo -e "${GREEN}✓ CLAUDE.md generated successfully${NC}"
echo ""
echo "Rules included:"
ls -1 "$RULES_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/^/  - /' || echo "  (no rules found)"
