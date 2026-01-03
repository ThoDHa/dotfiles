CURRENT_DIR := $(shell basename $$PWD)
CONTAINER := base_dev

# Stow packages (Linux dotfiles)
STOW_PACKAGES := shell tmux isort opencode
STOW_TARGET := $(HOME)

# OpenCode personality paths
# Source paths (in dotfiles repo) - used for personality switching
OPENCODE_SRC_RULES := $(CURDIR)/opencode/.config/opencode/rules
OPENCODE_SRC_REF := $(CURDIR)/opencode/.config/opencode/reference
# Target paths (after stow) - used for testing
OPENCODE_RULES := $(STOW_TARGET)/.config/opencode/rules
OPENCODE_REF := $(STOW_TARGET)/.config/opencode/reference

.PHONY: all stow unstow restow install uninstall run build help bootstrap
.PHONY: personality-wukong clean-stow test test-links test-rules

# Default target
all: help

# Stow all packages to home directory
stow:
	@echo "Stowing packages to $(STOW_TARGET)..."
	@for pkg in $(STOW_PACKAGES); do \
		echo "  Stowing $$pkg..."; \
		stow -v --no-folding -t $(STOW_TARGET) $$pkg; \
	done
	@echo "Done! All packages stowed."

# Unstow all packages
unstow:
	@echo "Unstowing packages from $(STOW_TARGET)..."
	@for pkg in $(STOW_PACKAGES); do \
		echo "  Unstowing $$pkg..."; \
		stow -v -D -t $(STOW_TARGET) $$pkg; \
	done
	@echo "Done! All packages unstowed."

# Restow (unstow then stow) - useful for updating
restow:
	@echo "Restowing packages to $(STOW_TARGET)..."
	@for pkg in $(STOW_PACKAGES); do \
		echo "  Restowing $$pkg..."; \
		stow -v --no-folding -R -t $(STOW_TARGET) $$pkg; \
	done
	@echo "Done! All packages restowed."

# Stow individual packages
stow-%:
	@echo "Stowing $*..."
	stow -v --no-folding -t $(STOW_TARGET) $*

# Unstow individual packages
unstow-%:
	@echo "Unstowing $*..."
	stow -v -D -t $(STOW_TARGET) $*

# Dry run - preview what would be stowed
dry-run:
	@echo "Dry run - showing what would be stowed..."
	@for pkg in $(STOW_PACKAGES); do \
		echo "\n=== $$pkg ==="; \
		stow -n -v --no-folding -t $(STOW_TARGET) $$pkg 2>&1 || true; \
	done

# Clean up conflicting files/symlinks before stowing
# Removes any existing files that would conflict with stow
clean-stow:
	@echo "Cleaning up conflicting files for stow..."
	@# shell package
	@rm -f $(STOW_TARGET)/.zshrc
	@# tmux package
	@rm -f $(STOW_TARGET)/.tmux.conf
	@# tmux scripts
	@rm -f $(STOW_TARGET)/.local/bin/tmux-sessionizer
	@rm -f $(STOW_TARGET)/.local/bin/tmux-windowizer
	@# isort package
	@rm -f $(STOW_TARGET)/.config/isort/config.toml
	@# opencode package
	@rm -rf $(STOW_TARGET)/.config/opencode
	@echo "Done! Conflicting files removed. Run 'make stow' to create fresh symlinks."

# ============================================================================
# OpenCode Personality Switching
# ============================================================================
# Usage:
#   make personality-wukong   # Set Wukong as active personality
#   make personality-none     # Remove personality (use default OpenCode)
#
# The personality is set by symlinking rules/personality.md to the desired
# reference file in the SOURCE dotfiles. OpenCode loads all rules/*.md files.
# ============================================================================

personality-wukong:
	@echo "Setting Wukong as active personality..."
	@ln -sf ../reference/wukong.md $(OPENCODE_SRC_RULES)/personality.md
	@echo "Done! Wukong is now the active personality."

# Override stow-opencode (just stows, personality is already in source)
stow-opencode:
	@echo "Stowing opencode..."
	stow -v --no-folding -t $(STOW_TARGET) opencode
	@echo "Done! OpenCode stowed."

# Full bootstrap - install all dev tools
bootstrap:
	@./bootstrap/install.sh

# Aliases
install: stow
uninstall: unstow

# Docker commands
run:
	docker run -it --rm -v .:/root/$(CURRENT_DIR) -w /root/$(CURRENT_DIR) $(CONTAINER):latest

build:
	docker build -t $(CONTAINER) --no-cache -f bootstrap/Dockerfile .

# ============================================================================
# Testing
# ============================================================================

# Expected rules files (all *.md files in rules directory)
EXPECTED_RULES := coding-standards.md core.md delegation.md documentation-standards.md execution-standards.md git-protocol.md task-files.md personality.md

# Test all symlinks exist and opencode loads rules
test: test-links test-rules
	@echo ""
	@echo "All tests passed!"

# Test that all expected symlinks exist
test-links:
	@echo "Testing opencode symlinks..."
	@echo "  Checking rules directory exists..."
	@test -d $(OPENCODE_RULES) || (echo "FAIL: $(OPENCODE_RULES) directory missing" && exit 1)
	@echo "  Checking rules files..."
	@for file in $(EXPECTED_RULES); do \
		test -L $(OPENCODE_RULES)/$$file || (echo "FAIL: $$file symlink missing" && exit 1); \
		echo "    $$file OK"; \
	done
	@echo "  Checking personality symlink resolves to wukong.md..."
	@readlink -f $(OPENCODE_RULES)/personality.md | grep -q "wukong.md" || \
		(echo "FAIL: personality.md does not resolve to wukong.md" && exit 1)
	@echo "    personality.md -> wukong.md OK"
	@echo "Symlink tests passed!"

# Test that opencode loads all rules files correctly
test-rules:
	@echo "Testing opencode rules loading..."
	@echo "  Running opencode to verify rules are loaded..."
	@opencode run "List the rules files you have loaded. Just list filenames, one per line." 2>&1 | \
		tee /tmp/opencode-rules-test.txt | \
		grep -qiE "coding-standards|core|delegation|execution-standards|git-protocol|task-files|personality|wukong" || \
		(echo "FAIL: Rules files not detected in response. Output:" && cat /tmp/opencode-rules-test.txt && exit 1)
	@echo "  Rules loading confirmed!"
	@echo "Rules test passed!"

# Help
help:
	@echo "Dotfiles Management"
	@echo "==================="
	@echo ""
	@echo "Setup Commands:"
	@echo "  make install     - Symlink all configs"
	@echo "  make bootstrap   - Full dev environment setup (tools + configs)"
	@echo "  make uninstall   - Remove all symlinks"
	@echo ""
	@echo "Stow Commands:"
	@echo "  make stow        - Symlink stow packages"
	@echo "  make unstow      - Remove stow symlinks"
	@echo "  make restow      - Update symlinks (unstow + stow)"
	@echo "  make dry-run     - Preview what would be stowed"
	@echo "  make clean-stow  - Remove conflicting files before stowing"
	@echo "  make stow-PKG    - Stow a single package (e.g., make stow-shell)"
	@echo "  make unstow-PKG  - Unstow a single package"
	@echo ""
	@echo "OpenCode Personality:"
	@echo "  make stow-opencode       - Stow opencode + set Wukong as default"
	@echo "  make personality-wukong  - Switch to Wukong personality"
	@echo "  make personality-none    - Remove personality (use default)"
	@echo ""
	@echo "Testing:"
	@echo "  make test        - Run all tests (symlinks + rules loading)"
	@echo "  make test-links  - Verify all symlinks exist"
	@echo "  make test-rules  - Verify opencode loads all rules files"
	@echo ""
	@echo "Available stow packages: $(STOW_PACKAGES)"
	@echo ""
	@echo "Docker Commands:"
	@echo "  make build       - Build the dev container"
	@echo "  make run         - Run the dev container"
