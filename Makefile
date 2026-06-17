CURRENT_DIR := $(notdir $(CURDIR))
CONTAINER   := base_dev

# Stow packages (Linux dotfiles)
STOW_PACKAGES := shell tmux isort opencode claudecode
STOW_TARGET   := $(HOME)

# OpenCode personality paths
OPENCODE_SRC_RULES := $(CURDIR)/opencode/.config/opencode/rules
# Target paths (after stow) — used for testing
OPENCODE_RULES := $(STOW_TARGET)/.config/opencode/rules

# Claude Code paths
CLAUDECODE_SRC       := $(CURDIR)/claudecode/.claude
CLAUDECODE_GENERATOR := $(CLAUDECODE_SRC)/generate-claude-md.sh

.PHONY: all stow unstow restow install uninstall run build help bootstrap
.PHONY: personality-none clean-stow test test-links test-rules
.PHONY: sync-claudecode stow-claudecode

# Default target
all: help

# ── Loop macro ────────────────────────────────────────────────────────────────
# $(call stow_all, STOW_FLAGS, VERB) — iterate $(STOW_PACKAGES) with given flags
define stow_all
@for pkg in $(STOW_PACKAGES); do \
    echo "  $(2)ing $$pkg..."; \
    stow -v $(1) -t $(STOW_TARGET) $$pkg; \
done
endef

# Stow all packages to home directory
stow:
	@echo "Stowing packages to $(STOW_TARGET)..."
	$(call stow_all,--no-folding,Stow)
	@echo "Done! All packages stowed."

# Unstow all packages
unstow:
	@echo "Unstowing packages from $(STOW_TARGET)..."
	$(call stow_all,-D,Unstow)
	@echo "Done! All packages unstowed."

# Restow (unstow then stow) - useful for updating
restow:
	@echo "Restowing packages to $(STOW_TARGET)..."
	$(call stow_all,--no-folding -R,Restow)
	@echo "Done! All packages restowed."

# Stow / unstow / restow individual packages
stow-%:
	@echo "Stowing $*..."
	stow -v --no-folding -t $(STOW_TARGET) $*

unstow-%:
	@echo "Unstowing $*..."
	stow -v -D -t $(STOW_TARGET) $*

restow-%:
	@echo "Restowing $*..."
	stow -v --no-folding -R -t $(STOW_TARGET) $*

# Dry run - preview what would be stowed
dry-run:
	@echo "Dry run - showing what would be stowed..."
	@for pkg in $(STOW_PACKAGES); do \
		printf '\n=== %s ===\n' "$$pkg"; \
		stow -n -v --no-folding -t $(STOW_TARGET) $$pkg 2>&1 || true; \
	done

# Clean up files that external tools are known to clobber before stowing.
# Each entry is intentional — do not remove without understanding the conflict:
#   .zshrc                     — overwritten by oh-my-zsh --unattended installer
#   .tmux.conf                 — may exist from a prior manual tmux setup
#   tmux-sessionizer/windowizer — may exist from a prior manual install
#   isort config               — may exist from a prior isort install
#   .config/opencode           — may exist from a prior opencode install
#   .claude/{...}              — targeted removal: ~/.claude also holds runtime data
clean-stow:
	@echo "Cleaning up conflicting files for stow..."
	@rm -f \
		$(STOW_TARGET)/.zshrc \
		$(STOW_TARGET)/.tmux.conf \
		$(STOW_TARGET)/.local/bin/tmux-sessionizer \
		$(STOW_TARGET)/.local/bin/tmux-windowizer \
		$(STOW_TARGET)/.config/isort/config.toml \
		$(STOW_TARGET)/.claude/generate-claude-md.sh \
		$(STOW_TARGET)/.claude/settings.json \
		$(STOW_TARGET)/.claude/.gitignore
	@rm -rf $(STOW_TARGET)/.config/opencode
	@echo "Done! Conflicting files removed. Run 'make stow' to create fresh symlinks."

# ── OpenCode Personality ──────────────────────────────────────────────────────

# Set active personality by name — must match a file in reference/
personality-%:
	@echo "Setting $* as active personality..."
	@ln -sf ../reference/$*.md $(OPENCODE_SRC_RULES)/personality.md
	@echo "Done! $* is now the active personality."

personality-none:
	@echo "Removing personality (using default OpenCode)..."
	@rm -f $(OPENCODE_SRC_RULES)/personality.md
	@echo "Done! Default OpenCode will be used (no personality)."

# ── Claude Code Configuration ─────────────────────────────────────────────────

# Sync Claude Code config with opencode rules
sync-claudecode:
	@echo "Syncing Claude Code with opencode rules..."
	@test -f $(CLAUDECODE_GENERATOR) || (echo "ERROR: Generator script not found at $(CLAUDECODE_GENERATOR)" && exit 1)
	@$(CLAUDECODE_GENERATOR)
	@echo "Done! Claude Code now shares opencode configuration."

# Stow claudecode package then sync.
# $(MAKE) sync-claudecode is a recipe command (not a prerequisite) because stow
# must complete before sync writes to the stowed symlink target.
stow-claudecode:
	@echo "Stowing claudecode..."
	stow -v --no-folding -t $(STOW_TARGET) claudecode
	@echo "Done! Claude Code configuration stowed."
	@$(MAKE) sync-claudecode

# Full bootstrap - install/update all dev tools
bootstrap:
	@./bootstrap/setup.sh

# Aliases
install: stow
uninstall: unstow

# Docker commands
run:
	docker run -it --rm -v .:/root/$(CURRENT_DIR) -w /root/$(CURRENT_DIR) $(CONTAINER):latest

build:
	docker build -t $(CONTAINER) --no-cache -f bootstrap/Dockerfile .

# ── Testing ───────────────────────────────────────────────────────────────────

# Discover expected rules from the source directory automatically
EXPECTED_RULES := $(notdir $(wildcard opencode/.config/opencode/rules/*.md))

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
	@echo "  make stow-PKG    - Stow a single package   (e.g., make stow-shell)"
	@echo "  make unstow-PKG  - Unstow a single package (e.g., make unstow-shell)"
	@echo "  make restow-PKG  - Restow a single package (e.g., make restow-shell)"
	@echo ""
	@echo "OpenCode Personality:"
	@echo "  make personality-THEME  - Set personality (e.g., make personality-wukong)"
	@echo "  make personality-none   - Remove personality (use default)"
	@echo ""
	@echo "Claude Code Configuration:"
	@echo "  make sync-claudecode    - Sync CLAUDE.md with opencode rules"
	@echo "  make stow-claudecode    - Stow claudecode package (auto-syncs)"
	@echo "  make unstow-claudecode  - Unstow claudecode package"
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
