CURRENT_DIR := $(shell basename $$PWD)
CONTAINER := base_dev

# Stow packages (Linux dotfiles)
STOW_PACKAGES := shell tmux scripts cursor isort opencode
STOW_TARGET := $(HOME)

# OpenCode personality paths (resolved after stow)
OPENCODE_RULES := $(STOW_TARGET)/.config/opencode/rules
OPENCODE_REF := $(STOW_TARGET)/.config/opencode/reference

.PHONY: all stow unstow restow install uninstall run build help bootstrap
.PHONY: personality-wukong personality-carl personality-naruto

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

# ============================================================================
# OpenCode Personality Switching
# ============================================================================
# Usage:
#   make personality-wukong   # Set Wukong as active personality
#   make personality-carl     # Set Carl as active personality
#   make personality-naruto   # Set Naruto as active personality
#
# The personality is set by symlinking rules/personality.md to the desired
# reference file. OpenCode loads all rules/*.md files, including the symlink.
# ============================================================================

personality-wukong:
	@echo "Setting Wukong as active personality..."
	@ln -sf $(OPENCODE_REF)/wukong.md $(OPENCODE_RULES)/personality.md
	@echo "Done! Wukong is now the active personality."

personality-carl:
	@echo "Setting Carl as active personality..."
	@ln -sf $(OPENCODE_REF)/carl.md $(OPENCODE_RULES)/personality.md
	@echo "Done! Carl is now the active personality."

personality-naruto:
	@echo "Setting Naruto as active personality..."
	@ln -sf $(OPENCODE_REF)/naruto.md $(OPENCODE_RULES)/personality.md
	@echo "Done! Naruto is now the active personality."

# Override stow-opencode to also set default personality
stow-opencode:
	@echo "Stowing opencode..."
	stow -v --no-folding -t $(STOW_TARGET) opencode
	@echo "Setting Wukong as default personality..."
	@ln -sf $(OPENCODE_REF)/wukong.md $(OPENCODE_RULES)/personality.md
	@echo "Done! OpenCode stowed with Wukong as default personality."

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
	@echo "  make stow-PKG    - Stow a single package (e.g., make stow-shell)"
	@echo "  make unstow-PKG  - Unstow a single package"
	@echo ""
	@echo "OpenCode Personality:"
	@echo "  make stow-opencode       - Stow opencode + set Wukong as default"
	@echo "  make personality-wukong  - Switch to Wukong personality"
	@echo "  make personality-carl    - Switch to Carl personality"
	@echo "  make personality-naruto  - Switch to Naruto personality"
	@echo ""
	@echo "Available stow packages: $(STOW_PACKAGES)"
	@echo ""
	@echo "Docker Commands:"
	@echo "  make build       - Build the dev container"
	@echo "  make run         - Run the dev container"
