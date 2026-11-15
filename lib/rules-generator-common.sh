#!/bin/bash
# Shared scaffold for the compilers that render dotfiles sources into
# deployed agent instruction files: the color palette, the
# stowed-versus-repo rules directory resolution, and the output-path
# argument contract. A rules compiler sources this file from the
# repository's lib directory, then calls rules_generator_init with its
# default output path and forwards its own arguments; init resolves
# RULES_DIR and OUTPUT_FILE and exits nonzero on an invalid argument
# list, after which the compiler proceeds with its own rendering and
# success messaging. The fleet compiler shares the palette and takes
# the output contract through rules_generator_parse_output_arg instead
# of init: its sources sit next to the script, so it never resolves a
# rules directory.
#
# Sourcing context: the caller runs under `set -e` and locates this file
# through the repository root, so the root is always this file's parent
# directory.
#
# Globals set on source: RED, GREEN, YELLOW, NC, DOTFILES_REPO
# Globals set by rules_generator_parse_output_arg: OUTPUT_PATH
# Globals set by rules_generator_init: RULES_DIR, OUTPUT_FILE

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# The library sits directly under the repository root, so the root is one
# level up from this file whichever compiler sourced it, including a
# compiler running through a stow symlink.
DOTFILES_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Resolve the rules directory into RULES_DIR: prefer the stowed location
# (what opencode actually uses); fall back to the repo copy when the
# opencode package is not stowed (opencode absent).
rules_generator_resolve_rules_dir() {
    RULES_DIR="$HOME/.config/opencode/rules"
    if [ ! -d "$RULES_DIR" ]; then
        RULES_DIR="$DOTFILES_REPO/opencode/.config/opencode/rules"
        echo "  opencode rules not stowed — using repo copy: $RULES_DIR"
    fi
}

# Apply the output-location contract into OUTPUT_PATH: an optional first
# argument redirects the output (a file for the rules compilers, a
# directory for the fleet compiler; used by the sync tests to regenerate
# into a scratch location); empty (or whitespace-only) and extra
# arguments are rejected so a typo can never silently retarget the
# default. usage_word completes the "Usage: cmd [word]" line, so each
# caller keeps its own wording. Exits 1 with a usage or empty-path
# message on violation.
rules_generator_parse_output_arg() { # default_output usage_word [output_path]
    local default_output="$1"
    local usage_word="$2"
    shift 2
    if (( $# > 1 )); then
        echo "Usage: $(basename "$0") [$usage_word]" >&2
        exit 1
    fi
    OUTPUT_PATH="$default_output"
    if [[ $# -eq 1 ]]; then
        # A whitespace-only path would drop a stray entry named " " in
        # the cwd, so it is treated exactly like the empty argument.
        if [[ -z "${1//[[:space:]]/}" ]]; then
            echo "Error: output path must not be empty" >&2
            exit 1
        fi
        OUTPUT_PATH="$1"
    fi
}

# Append the rule bodies verbatim to OUTPUT in the given order: exactly
# one blank line between files and none after the last, so the result
# carries the AGENTS.md body contract (each rules source ends with a
# single trailing newline, the separator adds one more, and the last
# body adds no separator, leaving no trailing blank at EOF). The fleet
# compiler and the smoke harness's rules-body builders share this one
# implementation so the generated artifact and the injected corpus
# cannot desync. The caller owns any truncation of OUTPUT (the fleet
# compiler writes its header first, the harness starts from an empty
# file). Returns nonzero on a missing source; fatal handling is the
# caller's.
rules_generator_join_rules() { # output file...
    local out="$1"
    shift
    local f idx=0
    for f in "$@"; do
        if [ ! -f "$f" ]; then
            echo "  rules source missing: $f" >&2
            return 1
        fi
        if [ "$idx" -gt 0 ]; then
            echo "" >> "$out"
        fi
        cat "$f" >> "$out"
        idx=$((idx + 1))
    done
}

# Full init contract for the rules compilers: resolve RULES_DIR and
# OUTPUT_FILE and exit nonzero on an invalid argument list. Composes the
# two functions above so each half stays independently callable.
rules_generator_init() { # default_output [output_path]
    local default_output="$1"
    shift
    rules_generator_resolve_rules_dir
    rules_generator_parse_output_arg "$default_output" "output-path" "$@"
    OUTPUT_FILE="$OUTPUT_PATH"
}
