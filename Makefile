CURRENT_DIR := $(notdir $(CURDIR))
CONTAINER   := base_dev

# Stow packages (Linux dotfiles)
STOW_PACKAGES_ALL := shell tmux isort agents opencode claudecode
STOW_TARGET   := $(HOME)

# Optional tool packages are stowed only when the tool is installed.
# FORCE_OPENCODE=1 / FORCE_CLAUDECODE=1 override detection; bootstrap uses
# these to stow config before its tool install steps have run.
OPENCODE_PRESENT  := $(shell command -v opencode >/dev/null 2>&1 && echo 1)
CLAUDE_PRESENT    := $(shell command -v claude >/dev/null 2>&1 && echo 1)
OPENCODE_STOW     := $(if $(or $(FORCE_OPENCODE),$(OPENCODE_PRESENT)),opencode)
CLAUDECODE_STOW   := $(if $(or $(FORCE_CLAUDECODE),$(CLAUDE_PRESENT)),claudecode)
STOW_PACKAGES     := shell tmux isort agents $(OPENCODE_STOW) $(CLAUDECODE_STOW)
SKIPPED_PACKAGES  := $(filter-out $(STOW_PACKAGES),$(STOW_PACKAGES_ALL))
CLAUDE_SYNC       := $(or $(FORCE_CLAUDECODE),$(CLAUDE_PRESENT))

# Rules target path (after stow) — used by tests
OPENCODE_RULES := $(STOW_TARGET)/.config/opencode/rules

# Claude Code paths
CLAUDECODE_SRC       := $(CURDIR)/claudecode/.claude
CLAUDECODE_GENERATOR := $(CLAUDECODE_SRC)/generate-claude-md.sh

.PHONY: all stow unstow restow install uninstall run build help bootstrap
.PHONY: clean-stow test test-links test-rules test-tasks test-termux
.PHONY: sync-claudecode stow-claudecode

# Default target
all: help

# ── Loop macro ────────────────────────────────────────────────────────────────
# $(call stow_all, PKGS, STOW_FLAGS, VERB) — iterate PKGS with given flags
define stow_all
@for pkg in $(1); do \
    echo "  $(3)ing $$pkg..."; \
    stow -v $(2) -t $(STOW_TARGET) $$pkg || exit 1; \
done
endef

# Announce packages skipped because their tool is not installed
define announce_skips
@for pkg in $(SKIPPED_PACKAGES); do \
    echo "  Skipping $$pkg (tool not installed)"; \
done
endef

# Stow all applicable packages to home directory
stow:
	@echo "Stowing packages to $(STOW_TARGET)..."
	$(call announce_skips)
	$(call stow_all,$(STOW_PACKAGES),--no-folding,Stow)
	@echo "Done! All packages stowed."
ifneq ($(CLAUDE_SYNC),)
	@$(MAKE) sync-claudecode
else
	@echo "Skipping Claude Code sync (claude not installed)"
endif

# Unstow all packages (full list, so configs of uninstalled tools are removed)
unstow:
	@echo "Unstowing packages from $(STOW_TARGET)..."
	$(call stow_all,$(STOW_PACKAGES_ALL),-D,Unstow)
	@echo "Done! All packages unstowed."

# Restow (unstow everything, then stow only applicable packages)
restow:
	@echo "Restowing packages to $(STOW_TARGET)..."
	@for pkg in $(SKIPPED_PACKAGES); do \
        echo "  Dropping links for $$pkg (tool not installed)"; \
    done
	$(call stow_all,$(STOW_PACKAGES_ALL),-D,Unstow)
	$(call announce_skips)
	$(call stow_all,$(STOW_PACKAGES),--no-folding,Stow)
ifneq ($(CLAUDE_SYNC),)
	@$(MAKE) sync-claudecode
else
	@echo "Skipping Claude Code sync (claude not installed)"
endif
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
	$(call announce_skips)
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

# Discover expected rules and skills from the source directories automatically
EXPECTED_RULES := $(notdir $(wildcard opencode/.config/opencode/rules/*.md))
EXPECTED_SKILLS := $(foreach d,$(wildcard agents/.agents/skills/*),$(notdir $(d)))

# Test all symlinks exist and opencode loads rules
test: test-links test-rules test-tasks test-termux
	@echo ""
	@echo "All tests passed!"

# Test that all expected symlinks exist
test-links:
	@echo "Testing opencode symlinks..."
ifneq ($(OPENCODE_PRESENT),)
	@echo "  Checking rules directory exists..."
	@test -d $(OPENCODE_RULES) || (echo "FAIL: $(OPENCODE_RULES) directory missing" && exit 1)
	@echo "  Checking rules files..."
	@for file in $(EXPECTED_RULES); do \
		test -L $(OPENCODE_RULES)/$$file || (echo "FAIL: $$file symlink missing" && exit 1); \
		echo "    $$file OK"; \
	done
	@test -f $(STOW_TARGET)/.config/opencode/plugin/lru-context.ts || (echo "FAIL: lru-context plugin missing" && exit 1)
	@echo "    lru-context plugin OK"
else
	@echo "  Skipping opencode checks (opencode not installed)"
endif
	@echo "  Checking skills..."
	@for skill in $(EXPECTED_SKILLS); do \
		test -f $(STOW_TARGET)/.agents/skills/$$skill/SKILL.md || (echo "FAIL: $$skill skill missing" && exit 1); \
		echo "    $$skill OK"; \
	done
ifneq ($(CLAUDE_PRESENT),)
	@test -d $(STOW_TARGET)/.claude/skills || (echo "FAIL: ~/.claude/skills link missing" && exit 1)
	@echo "    ~/.claude/skills OK"
else
	@echo "  Skipping claudecode checks (claude not installed)"
endif
	@echo "Symlink tests passed!"

# Test that opencode loads all rules files correctly
test-rules:
	@echo "Testing opencode rules loading..."
ifneq ($(OPENCODE_PRESENT),)
	@echo "  Running opencode to verify rules are loaded..."
	@opencode run "List the rules files you have loaded and the skills available to you. Just names, one per line." 2>&1 | \
		tee /tmp/opencode-rules-test.txt | \
		grep -qiE "coding-standards|core|delegation|execution-standards|git-protocol|task-files" || \
		(echo "FAIL: Rules files not detected in response. Output:" && cat /tmp/opencode-rules-test.txt && exit 1)
	@echo "  Rules loading confirmed!"
	@echo "Rules test passed!"
else
	@echo "  Skipping rules test (opencode not installed)"
endif

# Test the tasks board tool (render, atomic claim, lane placement)
test-tasks:
	@echo "Testing tasks board tool..."
	@bash tests/tasks/test-tasks.sh

# Host-side checks for the Termux bootstrap (syntax, guard, no Debian-isms)
test-termux:
	@echo "Testing termux bootstrap script..."
	@bash tests/termux/test-termux.sh

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
	@echo "Claude Code Configuration:"
	@echo "  make sync-claudecode    - Sync CLAUDE.md with opencode rules"
	@echo "  make stow-claudecode    - Stow claudecode package (auto-syncs)"
	@echo "  make unstow-claudecode  - Unstow claudecode package"
	@echo ""
	@echo "Testing:"
	@echo "  make test        - Run all tests (symlinks + rules loading)"
	@echo "  make test-links  - Verify all symlinks exist"
	@echo "  make test-rules  - Verify opencode loads all rules files"
	@echo "  make test-tasks  - Verify the tasks board tool"
	@echo ""
	@echo "Available stow packages: $(STOW_PACKAGES_ALL)"
	@echo "opencode/claudecode are stowed only when the tool is installed"
	@echo "(override with FORCE_OPENCODE=1 / FORCE_CLAUDECODE=1)"
	@echo ""
	@echo "Docker Commands:"
	@echo "  make build       - Build the dev container"
	@echo "  make run         - Run the dev container"
