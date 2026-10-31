#!/bin/bash
# Generate ~/.pi/agent/AGENTS.md from opencode rules
# Combines the four rule files into a single document for pi

set -e

# Shared scaffold (colors, rules-dir fallback, output-path contract).
# Resolve this script through any stow symlink, then locate the repo-root
# library from its git toplevel, falling back to the conventional clone
# location for a copy running outside any repository.
SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
source "$(git -C "$(dirname "$SCRIPT_FILE")" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.dotfiles")/lib/rules-generator-common.sh"

rules_generator_init "$HOME/.pi/agent/AGENTS.md" "$@"

echo -e "${YELLOW}Generating AGENTS.md for pi...${NC}"
echo "  Rules source: $RULES_DIR"
echo "  Output: $OUTPUT_FILE"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Fixed four-file list in the order the provenance paragraph documents;
# new rule files are not picked up automatically, so a rule set change
# is a deliberate AGENTS.md spec change.
RULE_FILES=(core.md coding-standards.md execution-standards.md qhaway-memory.md)

for rule_file in "${RULE_FILES[@]}"; do
    if [ ! -f "$RULES_DIR/$rule_file" ]; then
        echo -e "${RED}  Error: rule file not found: $RULES_DIR/$rule_file${NC}"
        exit 1
    fi
done

# Header: title, blank, provenance paragraph naming both make targets plus
# the edit-routing sentence, blank
cat > "$OUTPUT_FILE" << 'EOF'
# User Instructions (AGENTS.md)

Generated from the dotfiles opencode rules by `make sync-agents-md`; verify with `make test-agents-md`. Source of truth: `~/.config/opencode/rules/core.md`, `coding-standards.md`, `execution-standards.md`, and `qhaway-memory.md`; the four sections below are their full verbatim text in that order. This single artifact serves pi directly and Claude Code through the `~/.claude/CLAUDE.md` symlink; memory or content edits belong in the opencode rules source files, never in this generated artifact.

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
