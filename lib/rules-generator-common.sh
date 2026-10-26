#!/bin/bash
# Shared scaffold for the rules compilers that render the opencode rules
# into agent instruction files: the color palette, the stowed-versus-repo
# rules directory resolution, and the output-path argument contract. A
# compiler sources this file from the repository's lib directory, then
# calls rules_generator_init with its default output path and forwards
# its own arguments; init resolves RULES_DIR and OUTPUT_FILE and exits
# nonzero on an invalid argument list, after which the compiler proceeds
# with its own rendering and success messaging.
#
# Sourcing context: the caller runs under `set -e` and locates this file
# through the repository root, so the root is always this file's parent
# directory.
#
# Globals set on source: RED, GREEN, YELLOW, NC, DOTFILES_REPO
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
rules_generator_rules_dir() {
    RULES_DIR="$HOME/.config/opencode/rules"
    if [ ! -d "$RULES_DIR" ]; then
        RULES_DIR="$DOTFILES_REPO/opencode/.config/opencode/rules"
        echo "  opencode rules not stowed — using repo copy: $RULES_DIR"
    fi
}

# Apply the output-path contract into OUTPUT_FILE: an optional first
# argument redirects the output file (used by the sync tests to
# regenerate into a scratch dir); empty (or whitespace-only) and extra
# arguments are rejected so a typo can never silently retarget the
# default. Exits 1 with a usage or empty-path message on violation.
rules_generator_init() { # default_output [output_path]
    local default_output="$1"
    shift
    rules_generator_rules_dir
    OUTPUT_FILE="$default_output"
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
}
