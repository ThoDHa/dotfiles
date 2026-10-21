CURRENT_DIR := $(notdir $(CURDIR))
CONTAINER   := base_dev

# Stow packages (Linux dotfiles)
STOW_PACKAGES_ALL := shell tmux isort agents opencode claudecode
STOW_TARGET   := $(HOME)

# Optional tool packages are stowed only when the tool is installed. If PATH
# cannot resolve opencode but the canonical ~/.opencode/bin/opencode exists
# (non-interactive shells may lack that dir on PATH), PATH is extended first
# so detection and every recipe resolve the same binary.
# FORCE_OPENCODE=1 / FORCE_CLAUDECODE=1 override detection; bootstrap uses
# these to stow config before its tool install steps have run.
ifeq ($(shell command -v opencode >/dev/null 2>&1 && echo 1),)
ifneq ($(wildcard $(HOME)/.opencode/bin/opencode),)
PATH := $(HOME)/.opencode/bin$(if $(PATH),:$(PATH))
endif
endif
OPENCODE_PRESENT  := $(shell command -v opencode >/dev/null 2>&1 && echo 1)
CLAUDE_PRESENT    := $(shell command -v claude >/dev/null 2>&1 || test -x "$(HOME)/.local/bin/claude" && echo 1)
OPENCODE_STOW     := $(if $(or $(FORCE_OPENCODE),$(OPENCODE_PRESENT)),opencode)
CLAUDECODE_STOW   := $(if $(or $(FORCE_CLAUDECODE),$(CLAUDE_PRESENT)),claudecode)
STOW_PACKAGES     := shell tmux isort agents $(OPENCODE_STOW) $(CLAUDECODE_STOW)
SKIPPED_PACKAGES  := $(filter-out $(STOW_PACKAGES),$(STOW_PACKAGES_ALL))
CLAUDE_SYNC       := $(or $(FORCE_CLAUDECODE),$(CLAUDE_PRESENT))
PI_PRESENT        := $(shell command -v pi >/dev/null 2>&1 && echo 1)
PI_SYNC           := $(or $(FORCE_PI),$(PI_PRESENT))

# Rules target path (after stow): used by tests
OPENCODE_RULES := $(STOW_TARGET)/.config/opencode/rules

# Top-level opencode config files that must stay symlinks: external tools
# overwrite them in place, which silently breaks stow without failing
# existence-only deployment checks
OPENCODE_CONFIG := $(STOW_TARGET)/.config/opencode

# Claude Code paths
CLAUDECODE_SRC       := $(CURDIR)/claudecode/.claude
CLAUDECODE_GENERATOR := $(CLAUDECODE_SRC)/generate-claude-md.sh

# pi agent generator (compiled from the opencode fleet agents)
PI_AGENTS_GENERATOR := $(CURDIR)/opencode/.config/opencode/agents/generate-pi-agents.sh

# pi AGENTS.md generator (compiled from the opencode rules)
AGENTS_MD_GENERATOR := $(CURDIR)/pi/generate-agents-md.sh

.PHONY: all stow unstow restow dry-run install uninstall run build help bootstrap verify
.PHONY: clean-stow readopt test test-links test-rules test-tasks test-oc-continue test-claudecode test-pi lint-corpus check verify-inner
.PHONY: sync-claudecode stow-claudecode sync-pi-agents test-pi-agents pin-manager-body sync-agents-md test-agents-md

# Default target
all: help

# ── Loop macro ────────────────────────────────────────────────────────────────
# $(call stow_all, PKGS, STOW_FLAGS, VERB): iterate PKGS with given flags
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
ifneq ($(PI_SYNC),)
	@$(MAKE) sync-pi-agents
else
	@echo "Skipping pi agents sync (pi not installed)"
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
ifneq ($(PI_SYNC),)
	@$(MAKE) sync-pi-agents
else
	@echo "Skipping pi agents sync (pi not installed)"
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
# Each entry is intentional. Do not remove without understanding the conflict:
#   .zshrc: overwritten by oh-my-zsh --unattended installer
#   .tmux.conf: may exist from a prior manual tmux setup
#   tmux-sessionizer/windowizer: may exist from a prior manual install
#   isort config: may exist from a prior isort install
#   .config/opencode/{opencode.json,tui.json,rules/*,agents/*}: stow-owned
#     links that external tools overwrite in place; only these paths are
#     removed so unmanaged runtime data (qhaway-memory DB, node_modules,
#     scripts, *.bak) survives cleanup. A legacy folded dir symlink is
#     dropped as a whole.
#   .claude/{...}: targeted removal (~/.claude also holds runtime data)
#   .agents: whole tree is stow-owned; drops links to a moved repo
#   DESIGN/GATEWAY/PII-SAFE.md: legacy links from before these docs were ignored
clean-stow:
	@echo "Cleaning up conflicting files for stowing..."
	@rm -f \
		$(STOW_TARGET)/.zshrc \
		$(STOW_TARGET)/.tmux.conf \
		$(STOW_TARGET)/.local/bin/tmux-sessionizer \
		$(STOW_TARGET)/.local/bin/tmux-windowizer \
		$(STOW_TARGET)/.config/isort/config.toml \
		$(STOW_TARGET)/.claude/generate-claude-md.sh \
		$(STOW_TARGET)/.claude/settings.json \
		$(STOW_TARGET)/.claude/.gitignore \
		$(STOW_TARGET)/DESIGN.md \
		$(STOW_TARGET)/GATEWAY.md \
		$(STOW_TARGET)/PII-SAFE.md
	@if [ -L $(STOW_TARGET)/.config/opencode ]; then \
		rm -f $(STOW_TARGET)/.config/opencode; \
	else \
		rm -f $(STOW_TARGET)/.config/opencode/opencode.json \
			$(STOW_TARGET)/.config/opencode/tui.json \
			$(STOW_TARGET)/.config/opencode/rules/* \
			$(STOW_TARGET)/.config/opencode/agents/*; \
	fi
	@rm -rf $(STOW_TARGET)/.agents
	@echo "Done! Conflicting files removed. Run 'make stow' to create fresh symlinks."

# Repo-side opencode.json and the canned commit message for readopt
OPENCODE_JSON := opencode/.config/opencode/opencode.json
READOPT_MSG   := chore: readopt opencode.json after runtime rewrite

# Re-adopt opencode.json after the running opencode process rewrites it:
# the rewrite is a rename-replace, which swaps the stow symlink for a
# real file and silently breaks the deployment. Adopt restores the link
# and pulls any drift into the repo copy. Drift is committed for exactly
# that one file (pathspec commit, so an unrelated staged change can
# never ride along); with no drift, nothing is committed. Both branches
# end by warning about any residual adopted drift left uncommitted
# elsewhere in the package. Meant for the main checkout, which owns
# the live deployment; from any other checkout, stow aborts with its
# not-owned error by design.
readopt:
	@echo "Re-adopting opencode.json from $(STOW_TARGET)..."
	stow --adopt --no-folding -v -t $(STOW_TARGET) opencode
	@drift=$$(git status --porcelain -- $(OPENCODE_JSON)) || \
	{ echo "ERROR: git status failed for $(OPENCODE_JSON); cannot check readopt drift" >&2; exit 1; }; \
	if [ -n "$$drift" ]; then \
		git commit -m "$(READOPT_MSG)" -- $(OPENCODE_JSON) || exit $$?; \
	else \
		echo "No drift found in opencode.json: it matches the repo copy."; \
	fi; \
	residual=$$(git status --porcelain -- opencode/) || \
	{ echo "ERROR: git status failed for opencode/; cannot check for adopted drift" >&2; exit 1; }; \
	if [ -n "$$residual" ]; then \
		echo "WARNING: adopted drift outside the one-file commit contract (left uncommitted):"; \
		echo "$$residual"; \
	fi

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

# Compile ~/.pi/agent/agents from the opencode fleet agents (single source
# of truth; the pi frontmatter is constructed from each source's
# "# pi:" directive, name, description, and body).
sync-pi-agents:
	@echo "Syncing pi agents from the opencode fleet..."
	@test -f $(PI_AGENTS_GENERATOR) || (echo "ERROR: Generator script not found at $(PI_AGENTS_GENERATOR)" && exit 1)
	@$(PI_AGENTS_GENERATOR)
	@echo "Done! pi agents compiled from the opencode fleet."

# Generate ~/.pi/agent/AGENTS.md from the opencode rules
sync-agents-md:
	@echo "Syncing pi AGENTS.md with opencode rules..."
	@test -f $(AGENTS_MD_GENERATOR) || (echo "ERROR: Generator script not found at $(AGENTS_MD_GENERATOR)" && exit 1)
	@$(AGENTS_MD_GENERATOR)
	@echo "Done! pi now shares opencode configuration."

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

# Designated scratch for verifier dispatches: the only host path a verify
# container may write. Unique per make invocation so concurrent verifier
# dispatches never share a scratch dir; evaluated once at parse time so
# the mkdir and the docker mount bind the same directory. Override to
# relocate the family.
ifeq ($(origin FLEET_VERIFY_SCRATCH),undefined)
FLEET_VERIFY_SCRATCH := /tmp/opencode/fleet-verify-$(shell date +%s%N)
endif

# A linked worktree's .git file points at the main .git by absolute path, so
# git inside the container resolves only when the common dir exists at that
# same path. A main checkout carries .git inside the repo mount and needs no
# extra mount.
GIT_COMMON_DIR := $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
ifeq ($(GIT_COMMON_DIR),$(CURDIR)/.git)
DOCKER_WORKTREE_GIT_MOUNT :=
else ifneq ($(GIT_COMMON_DIR),)
DOCKER_WORKTREE_GIT_MOUNT := -v $(GIT_COMMON_DIR):$(GIT_COMMON_DIR):ro
else
DOCKER_WORKTREE_GIT_MOUNT :=
endif

# Containerized verification entry for verifier subagent dispatches. The
# payload runs inside base_dev: the repo mounts read-only, the network is
# off, and writes are bounded to the designated scratch, so recipe code
# cannot mutate the repo or the host and cannot reach remote endpoints.
# The suite's exit code survives the trailing cleanup, which removes the
# run's root-owned scratch files in-container; the host user could not
# delete them. The verifier's permission-layer allowlist stays as
# defense-in-depth.
verify:
	@mkdir -p $(FLEET_VERIFY_SCRATCH)
	@echo "Running the container verification suite (repo read-only, network off)..."
	docker run --rm --network none -v $(CURDIR):/root/dotfiles:ro $(DOCKER_WORKTREE_GIT_MOUNT) -v $(FLEET_VERIFY_SCRATCH):/scratch -e TMPDIR=/scratch -w /root/dotfiles $(CONTAINER):latest sh -c 'make verify-inner; rc=$$?; rm -rf /scratch/* /scratch/.[!.]* /scratch/..?* 2>/dev/null; exit $$rc'

# ── Testing ───────────────────────────────────────────────────────────────────

# Discover expected rules and skills from the source directories automatically
EXPECTED_RULES := $(notdir $(wildcard opencode/.config/opencode/rules/*.md))
EXPECTED_SKILLS := $(foreach d,$(wildcard agents/.agents/skills/*),$(notdir $(d)))

# GNU stow's built-in default ignore list (man stow, "Ignore Lists") plus
# .stow-local-ignore control files: stow never deploys these, so the
# deployment completeness walk must skip them too. The trailing (/|$) makes
# a match cover the whole subtree beneath an ignored directory, not just the
# directory entry itself.
STOW_DEFAULT_IGNORE_REGEX := (^|/)(\.stow-local-ignore|CVS|RCS|SCCS|\.git|\.gitignore|\.gitmodules|\.gitattributes|\.cvsignore|\.cvsrc|\.svn|\.arch-ids|\{arch\}|=BUILD|=DEPS|=CHECKIN|=template|\.bzr|\.bzrignore|\.hg|\.hgignore|_darcs)(/|$$)

# Check deployment completeness: every file stow would deploy from the
# stowed packages must exist under the stow target. Repo-to-target
# direction only, so pre-existing unmanaged files at the target never
# fail this check. Honors each package's .stow-local-ignore regexes,
# scoped to that package's own walk, alongside stow's default ignores.
# $(call check_deploy_completeness, PACKAGES)
define check_deploy_completeness
@echo "  Checking deployment completeness..."; \
for pkg in $(1); do \
    [ -d "$$pkg" ] || { echo "FAIL: package directory '$$pkg' missing from the repo"; exit 1; }; \
    local_ignores=''; \
    if [ -f $$pkg/.stow-local-ignore ]; then \
        local_ignores=$$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$$/d' $$pkg/.stow-local-ignore | paste -sd '|' -); \
    fi; \
    ignore_re="$(STOW_DEFAULT_IGNORE_REGEX)$${local_ignores:+|$$local_ignores}"; \
    echo '' | grep -E "$$ignore_re" >/dev/null 2>&1; \
    if [ $$? -gt 1 ]; then \
        echo "FAIL: invalid ignore regex for $$pkg: $$ignore_re" && exit 1; \
    fi; \
    find $$pkg \( -type f -o -type l \) | sed "s|^$$pkg/||" | grep -Ev "$$ignore_re" | \
    while IFS= read -r rel; do \
        deployed=$(STOW_TARGET)/$$rel; \
        if [ ! -e "$$deployed" ] && [ ! -L "$$deployed" ]; then \
            echo "FAIL: $$deployed missing from deployment (repo: $$pkg/$$rel; stale stow links)"; \
            echo "      Run 'make stow' or 'make restow' to deploy it."; \
            exit 1; \
        fi; \
    done || exit 1; \
    echo "    $$pkg OK"; \
done
endef

# Test deployment completeness, symlinks, and opencode rules loading
test: lint-corpus test-links test-rules test-tasks test-oc-continue test-claudecode test-agents-md test-pi-agents test-pi
	@echo ""
	@echo "All tests passed!"

# Full check flow: the complete test suite
check: test

# In-container suite behind make verify: the repo content checks, which
# need no network and no host deployment state. The host deployment checks
# (test-links, test-rules) stay host-only in test.
verify-inner: lint-corpus test-tasks test-oc-continue test-claudecode test-agents-md test-pi-agents test-pi
	@echo ""
	@echo "Container verification suite passed!"

# Test deployment completeness and that all expected symlinks exist
test-links:
	$(call check_deploy_completeness,$(STOW_PACKAGES))
	@echo "Testing opencode symlinks..."
ifneq ($(OPENCODE_PRESENT),)
	@echo "  Checking rules directory exists..."
	@test -d $(OPENCODE_RULES) || (echo "FAIL: $(OPENCODE_RULES) directory missing" && exit 1)
	@echo "  Checking rules files..."
	@for file in $(EXPECTED_RULES); do \
		test -L $(OPENCODE_RULES)/$$file || { echo "FAIL: $$file symlink missing"; exit 1; }; \
		echo "    $$file OK"; \
	done
	@echo "  Checking opencode config symlinks..."
	@for file in opencode.json tui.json; do \
		test -L $(OPENCODE_CONFIG)/$$file || { echo "FAIL: $$file symlink missing"; exit 1; }; \
		echo "    $$file OK"; \
	done
else
	@echo "  Skipping opencode checks (opencode not installed)"
endif
	@echo "  Checking skills..."
	@for skill in $(EXPECTED_SKILLS); do \
		test -f $(STOW_TARGET)/.agents/skills/$$skill/SKILL.md || { echo "FAIL: $$skill skill missing"; exit 1; }; \
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
	@opencode run --auto "List the rules files you have loaded and the skills available to you. Just names, one per line." 2>&1 | \
		tee /tmp/opencode-rules-test.txt >/dev/null
	@grep -qiE "(^|[^[:alpha:]])core\.md|coding-standards|execution-standards" /tmp/opencode-rules-test.txt || \
		(echo "FAIL: Rules files not detected in response (expected coding-standards.md, core.md, or execution-standards.md). Output:" && cat /tmp/opencode-rules-test.txt && exit 1)
	@grep -qiE "delegation|git-protocol|task-files" /tmp/opencode-rules-test.txt || \
		(echo "FAIL: Skills not detected in response (expected delegation, git-protocol, or task-files). Output:" && cat /tmp/opencode-rules-test.txt && exit 1)
	@echo "  Rules loading confirmed!"
	@echo "Rules test passed!"
else
	@echo "  Skipping rules test (opencode not installed)"
endif

# Mechanical corpus lint: dashes, links, headings, INVENTORY sync, budgets
lint-corpus:
	@echo "Linting the corpus..."
	@bash tests/corpus/lint-corpus.sh

# Test the tasks board tool (render, atomic claim, lane placement)
test-tasks:
	@echo "Testing tasks board tool..."
	@bash tests/tasks/test-tasks.sh

# Test the oc-continue runner (budgets, retention, follow, flag contract)
test-oc-continue:
	@echo "Testing oc-continue runner..."
	@bash tests/oc-continue/test-oc-continue.sh

# Test that the generated CLAUDE.md matches a fresh generation of the rules
test-claudecode:
	@echo "Testing Claude Code sync (CLAUDE.md vs opencode rules)..."
	@bash tests/claudecode/test-sync.sh

# Test that the generated pi AGENTS.md matches a fresh generation of the rules
test-agents-md:
	@echo "Testing pi AGENTS.md sync (~/.pi/agent/AGENTS.md vs opencode rules)..."
	@bash tests/agents-md/test-sync.sh

# Test that the generated pi agents match a fresh compilation of the fleet
test-pi-agents:
	@echo "Testing pi agents sync (generated files vs opencode fleet)..."
	@bash tests/pi-agents/test-sync.sh

# Fleet manager source and its digest pin (see pin-manager-body; the digest
# must match tests/pi-agents/test-sync.sh's manager_body_digest)
FLEET_MANAGER_MD := opencode/.config/opencode/agents/manager.md
MANAGER_BODY_PIN := tests/pi-agents/manager-body.sha256

# Regenerate the manager body digest pin (keep the awk program identical to
# the test's manager_body_digest). Refuses to write a vacuous pin: a missing
# fleet manager.md, a digest pipeline that produced nothing, or an empty body
# (an unclosed frontmatter extracts no lines, and empty input hashes to the
# well-known empty digest) each fail loudly instead of pinning, which would
# leave the sync guard dying vacuously after the next re-pin.
pin-manager-body:
	@test -f $(FLEET_MANAGER_MD) || { echo "ERROR: $(FLEET_MANAGER_MD) not found; nothing to pin" >&2; exit 1; }; \
	digest=$$(awk '/^---$$/{c++; if (c == 2) { in_body = 1; next } } in_body { print }' $(FLEET_MANAGER_MD) | sha256sum | cut -d' ' -f1) || \
		{ echo "ERROR: hashing the $(FLEET_MANAGER_MD) body failed" >&2; exit 1; }; \
	[ -n "$$digest" ] || { echo "ERROR: body extraction from $(FLEET_MANAGER_MD) produced no digest" >&2; exit 1; }; \
	empty_digest=$$(printf '' | sha256sum | cut -d' ' -f1) || \
		{ echo "ERROR: computing the empty-input reference digest failed" >&2; exit 1; }; \
	if [ "$$digest" = "$$empty_digest" ]; then \
		echo "ERROR: $(FLEET_MANAGER_MD) body is empty (digest $$digest matches empty input);" >&2; \
		echo "  the frontmatter is probably missing or never closes with a second ---. Fix the file, then rerun." >&2; \
		exit 1; \
	fi; \
	printf '# sha256 of the fleet manager body (everything below the frontmatter closing ---); refresh: make pin-manager-body\n' > $(MANAGER_BODY_PIN); \
	printf '%s\n' "$$digest" >> $(MANAGER_BODY_PIN); \
	echo "Pinned the $(FLEET_MANAGER_MD) body digest to $(MANAGER_BODY_PIN)"

# Test the pi integration contract: setup.sh's pi functions and gates,
# the .zshrc session-dir export, and the seed config repo's whitelist
# and pre-commit secrets guard against a local fixture replica. Hermetic:
# the feed and the pi binary are faked on PATH, and the ThoDHa/pi origin
# is probed only when the network is reachable, so the suite runs green
# network-off (verify-inner) with the origin section announced as skipped.
test-pi:
	@echo "Testing the pi integration contract..."
	@bash tests/pi/test-pi.sh

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
	@echo "  make readopt     - Re-adopt opencode.json after a runtime rewrite"
	@echo "  make stow-PKG    - Stow a single package   (e.g., make stow-shell)"
	@echo "  make unstow-PKG  - Unstow a single package (e.g., make unstow-shell)"
	@echo "  make restow-PKG  - Restow a single package (e.g., make restow-shell)"
	@echo ""
	@echo "Claude Code Configuration:"
	@echo "  make sync-claudecode    - Sync CLAUDE.md with opencode rules"
	@echo "  make stow-claudecode    - Stow claudecode package (auto-syncs)"
	@echo "  make unstow-claudecode  - Unstow claudecode package"
	@echo ""
	@echo "pi Agents:"
	@echo "  make sync-pi-agents     - Compile ~/.pi/agent/agents from the opencode fleet"
	@echo "  make sync-agents-md     - Generate ~/.pi/agent/AGENTS.md from the opencode rules"
	@echo "  make pin-manager-body   - Regenerate the manager body digest pin (rejects missing or empty body)"
	@echo ""
	@echo "Testing:"
	@echo "  make test        - Run all tests (corpus lint + symlinks + rules + tasks + oc-continue + claudecode + pi)"
	@echo "  make check       - Alias for make test"
	@echo "  make lint-corpus - Mechanical corpus lint (dashes, links, INVENTORY sync)"
	@echo "  make verify      - Container verification suite (verifier dispatches)"
	@echo "  make test-links  - Verify stow deployment completeness and symlinks"
	@echo "  make test-rules  - Verify opencode loads all rules files"
	@echo "  make test-tasks  - Verify the tasks board tool"
	@echo "  make test-oc-continue - Verify the oc-continue runner"
	@echo "  make test-claudecode - Verify CLAUDE.md matches a fresh generation of the opencode rules"
	@echo "  make test-agents-md - Verify ~/.pi/agent/AGENTS.md matches a fresh generation of the opencode rules"
	@echo "  make test-pi-agents - Verify ~/.pi/agent/agents matches a fresh compilation of the fleet"
	@echo "  make test-pi     - Verify the pi integration contract (feed parsers, gates, seed repo guard)"
	@echo ""
	@echo "Available stow packages: $(STOW_PACKAGES_ALL)"
	@echo "opencode/claudecode are stowed only when the tool is installed"
	@echo "(override with FORCE_OPENCODE=1 / FORCE_CLAUDECODE=1)"
	@echo ""
	@echo "Docker Commands:"
	@echo "  make build       - Build the dev container"
	@echo "  make run         - Run the dev container"
