#!/bin/bash
# Generate ~/.pi/agent/AGENTS.md from opencode rules
# Combines the four rule files into a single document for pi

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
# Output location: an optional first argument redirects the file (used by
# the sync test to regenerate into a scratch dir); empty (or
# whitespace-only) and extra arguments are rejected so a typo can never
# silently retarget $HOME.
OUTPUT_FILE="$HOME/.pi/agent/AGENTS.md"
if (( $# > 1 )); then
    echo "Usage: $(basename "$0") [output-path]" >&2
    exit 1
fi
if [[ $# -eq 1 ]]; then
    # A whitespace-only path would drop a stray file named " " in the
    # cwd, so it is treated exactly like the empty argument.
    if [[ -z "${1//[[:space:]]/}" ]]; then
        echo "Error: output path must not be empty" >&2
        exit 1
    fi
    OUTPUT_FILE="$1"
fi

echo -e "${YELLOW}Generating AGENTS.md for pi...${NC}"
echo "  Rules source: $RULES_DIR"
echo "  Output: $OUTPUT_FILE"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Fixed four-file list in the order the provenance paragraph documents;
# unlike CLAUDE.md, new rule files are not picked up automatically, so a
# rule set change is a deliberate AGENTS.md spec change.
RULE_FILES=(core.md coding-standards.md execution-standards.md qhaway-memory.md)

for rule_file in "${RULE_FILES[@]}"; do
    if [ ! -f "$RULES_DIR/$rule_file" ]; then
        echo -e "${RED}  Error: rule file not found: $RULES_DIR/$rule_file${NC}"
        exit 1
    fi
done

# Header: title, blank, provenance paragraph naming both make targets, blank
cat > "$OUTPUT_FILE" << 'EOF'
# User Instructions (AGENTS.md)

Generated from the dotfiles opencode rules by `make sync-agents-md`; verify with `make test-agents-md`. Source of truth: `~/.config/opencode/rules/core.md`, `coding-standards.md`, `execution-standards.md`, and `qhaway-memory.md`; the four sections below are their full verbatim text in that order.

EOF

# Rule bodies verbatim, joined by exactly one blank line: each rule file
# ends with a single trailing newline and the separator adds one more, so
# the last body must not be followed by a separator (no trailing blank at EOF).
for ((i = 0; i < ${#RULE_FILES[@]}; i++)); do
    cat "$RULES_DIR/${RULE_FILES[$i]}" >> "$OUTPUT_FILE"
    if ((i < ${#RULE_FILES[@]} - 1)); then
        echo "" >> "$OUTPUT_FILE"
    fi
done

echo -e "${GREEN}✓ AGENTS.md generated successfully${NC}"
echo ""
echo "Rules included:"
printf '  - %s\n' "${RULE_FILES[@]}"
