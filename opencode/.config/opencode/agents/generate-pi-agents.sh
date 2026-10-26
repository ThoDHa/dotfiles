#!/bin/bash
# Generate pi agent files from the opencode fleet agents.
#
# Single source of truth: the opencode agent .md files in this directory.
# Each dual-harness source carries a "# pi: model=<bare-id> tools=<list>"
# comment in its frontmatter; this script compiles that comment together
# with the name, description, and body into a real pi agent file under
# ~/.pi/agent/agents. An optional trailing "detach=false" token (after the
# tools list) additionally emits a "detach: false" frontmatter key, which
# bars the agent from detached (background) subagent dispatch in pi. The pi
# frontmatter is constructed, never copied
# wholesale: pi's loader requires name and description, resolves bare
# model ids against its default provider, and whitelists tools, while
# opencode's per-file schema is closed (unknown keys, tools included,
# make it silently drop the agent), so neither side can consume the
# other's frontmatter verbatim. Source files without a "# pi:" comment
# are opencode-only and are skipped.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Paths: sources sit next to this script, resolved through any stow
# symlink so a repo-side invocation reads the same directory it lives in.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENT_SRC_DIR="$SCRIPT_DIR"

# Output location: an optional first argument redirects the generated
# files into a scratch directory (used by the sync test to regenerate
# off-host); empty (or whitespace-only) and extra arguments are rejected
# so a typo can never silently retarget the write.
OUTPUT_DIR="$HOME/.pi/agent/agents"
if (( $# > 1 )); then
    echo "Usage: $(basename "$0") [output-dir]" >&2
    exit 1
fi
if [[ $# -eq 1 ]]; then
    # A whitespace-only path would drop output into the cwd, so it is
    # treated exactly like the empty argument.
    if [[ -z "${1//[[:space:]]/}" ]]; then
        echo "Error: output path must not be empty" >&2
        exit 1
    fi
    OUTPUT_DIR="$1"
fi

echo -e "${YELLOW}Generating pi agents from the opencode fleet...${NC}"
echo "  Agent sources: $AGENT_SRC_DIR"
echo "  Output: $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

generated=0
skipped=0
for src in "$AGENT_SRC_DIR"/*.md; do
    base="$(basename "$src" .md)"

    # Frontmatter is the block between the first two '---' lines.
    close_line="$(awk 'NR > 1 && /^---[[:space:]]*$/ {print NR; exit}' "$src")"
    if [[ -z "$close_line" ]]; then
        echo -e "${RED}  Error: $base.md has no closing frontmatter delimiter${NC}" >&2
        exit 1
    fi

    # The "# pi:" compile directive; sources without it stay opencode-only.
    pi_line="$(awk -v stop="$close_line" 'NR < stop && /^# pi: / {print; exit}' "$src")"
    if [[ -z "$pi_line" ]]; then
        echo "  Skipping $base.md (opencode-only, no # pi: directive)"
        skipped=$((skipped + 1))
        continue
    fi

    name="$base"
    description="$(awk -v stop="$close_line" 'NR < stop && /^description: / {sub(/^description: /, ""); print; exit}' "$src")"
    model="$(sed -n 's/^# pi: model=\([^ ]*\).*$/\1/p' <<<"$pi_line")"
    tools="$(sed -n 's/^# pi: model=[^ ]* tools=//p' <<<"$pi_line")"

    # Optional trailing "detach=false" directive token; it must be the last
    # token, so anything else after "tools=" belongs to the tools list.
    detach="true"
    if [[ "$tools" == *" detach=false" ]]; then
        detach="false"
        tools="${tools%" detach=false"}"
    fi

    missing=()
    if [[ -z "$description" ]]; then missing+=("description"); fi
    if [[ -z "$model" ]]; then missing+=("model (in # pi: directive)"); fi
    if [[ -z "$tools" ]]; then missing+=("tools (in # pi: directive)"); fi
    if (( ${#missing[@]} > 0 )); then
        echo -e "${RED}  Error: $base.md is missing: ${missing[*]}${NC}" >&2
        exit 1
    fi

    # Atomic write: mktemp in the output dir keeps mv on the same
    # filesystem, and mv over an existing symlink replaces the link
    # itself rather than writing through it.
    out="$OUTPUT_DIR/$base.md"
    tmp="$(mktemp "$OUTPUT_DIR/.${base}.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    {
        echo "---"
        echo "name: $name"
        echo "description: $description"
        echo "model: $model"
        echo "tools: $tools"
        if [[ "$detach" == "false" ]]; then
            echo "detach: false"
        fi
        echo "---"
        tail -n +"$((close_line + 1))" "$src"
    } > "$tmp"
    mv "$tmp" "$out"
    trap - EXIT

    echo "  $base.md -> $out (model=$model, tools=$tools)"
    generated=$((generated + 1))
done

if (( generated == 0 )); then
    echo -e "${RED}  Error: no dual-harness agent sources found in $AGENT_SRC_DIR${NC}" >&2
    exit 1
fi

echo -e "${GREEN}✓ Generated $generated pi agent file(s)${NC} ($skipped opencode-only skipped)"
echo ""
