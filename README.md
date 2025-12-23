# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick Start

```bash
# Clone, stow configs, and bootstrap everything
git clone https://github.com/ThoDHa/dotfiles.git ~/dotfiles
cd ~/dotfiles
make stow
./bootstrap/install.sh

# Restart shell when done
exec zsh
```

**Alternative:** If you just want to symlink configs without installing tools:

```bash
git clone https://github.com/ThoDHa/dotfiles.git ~/dotfiles
cd ~/dotfiles
make install
```

## Structure

Each directory is a stow "package" that mirrors the target structure in `$HOME`:

```
dotfiles/
├── shell/              # Zsh configuration
│   └── .zshrc          # -> ~/.zshrc
├── tmux/               # Tmux configuration
│   └── .tmux.conf      # -> ~/.tmux.conf
├── scripts/            # Custom scripts
│   └── .local/bin/
│       ├── tmux-sessionizer
│       └── tmux-windowizer
├── isort/              # Python isort config
│   └── .config/isort/
│       └── config.toml # -> ~/.config/isort/config.toml
├── opencode/           # OpenCode AI config
│   └── .config/opencode/
│       ├── opencode.json
│       ├── rules/      # RFC 2119 specification files
│       └── reference/  # Personality definitions
├── bootstrap/          # Setup scripts (not stowed)
│   ├── install.sh
│   ├── opencode-install.sh
│   └── Dockerfile
├── reference/          # Template configs (not stowed)
│   ├── markdownlint.json
│   ├── PowerToys/
│   └── windows_terminal_settings.json
├── Makefile
└── README.md
```

## Commands

| Command | Description |
|---------|-------------|
| `make bootstrap` | Full setup: install tools + symlink all configs |
| `make install` | Symlink all stow packages |
| `make uninstall` | Remove all symlinks |
| `make stow` | Symlink stow packages |
| `make unstow` | Remove stow symlinks |
| `make restow` | Update symlinks (unstow + stow) |
| `make dry-run` | Preview what would be stowed |
| `make clean-stow` | Remove conflicting files before stowing |
| `make stow-PKG` | Stow a single package (e.g., `make stow-shell`) |
| `make unstow-PKG` | Unstow a single package |
| `make build` | Build the dev container |
| `make run` | Run the dev container |

**Container Usage:** The Docker setup provides a clean development environment with all tools pre-installed. Run `make build` once, then `make run` to get a containerized shell with your configs mounted.

## Packages

| Package | Target | Description |
|---------|--------|-------------|
| `shell` | `~/.zshrc` | Zsh config with oh-my-zsh, FZF, aliases |
| `tmux` | `~/.tmux.conf` | Tmux config with TPM plugins, rose-pine theme |
| `scripts` | `~/.local/bin/` | tmux-sessionizer and tmux-windowizer |
| `isort` | `~/.config/isort/` | Python import sorter config |
| `opencode` | `~/.config/opencode/` | OpenCode AI rules and personality |

## OpenCode Personality

Switch OpenCode personality after stowing:

```bash
make stow-opencode        # Stow opencode + set Wukong as default
make personality-wukong   # Switch to Wukong personality
```

The personality system uses symlinks — `rules/personality.md` points to the active personality in `reference/`.

## Bootstrap

The `bootstrap/install.sh` script sets up a complete development environment:

- System packages (git, curl, zsh, tmux, ripgrep, etc.)
- oh-my-zsh with plugins (syntax highlighting, autosuggestions, completions)
- fzf (fuzzy finder)
- TPM (Tmux Plugin Manager) with plugin installation
- NeoVim (latest version via AppImage)
- NeoVim configuration from [ThoDHa/nvim](https://github.com/ThoDHa/nvim)
- NVM with Node.js LTS
- OpenCode configuration symlinks

The script is idempotent — safe to run multiple times.

## Reference Templates

The `reference/` directory contains configuration templates that you copy to projects or systems as needed:

**Project Templates:**
```bash
# Copy markdownlint config to a project
cp ~/dotfiles/reference/markdownlint.json ~/my-project/.markdownlint.json
```

## Windows Configuration

Copy Windows configurations manually when needed:

**PowerToys:**
```powershell
# Close PowerToys application first
# Then copy settings:
Copy-Item "reference\PowerToys\*" "$env:LOCALAPPDATA\Microsoft\PowerToys\" -Recurse -Force
```

**Windows Terminal:**
```powershell
Copy-Item "reference\windows_terminal_settings.json" "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
```

**Notes:**
- Close PowerToys before copying settings  
- Windows Terminal will auto-reload the configuration
- Backup existing configs if you want to preserve them

## Troubleshooting

**Stow conflicts:**
```bash
# If stow complains about existing files/directories
make clean-stow  # Remove all conflicting files
make stow        # Create fresh symlinks
```

**Bootstrap issues:**
- **Permission denied**: Run bootstrap with appropriate permissions for system packages
- **NeoVim plugins don't install**: Open nvim manually after bootstrap — Lazy will prompt to install plugins  
- **Zsh not default shell**: Log out and back in, or run `exec zsh`

## Dependencies

The bootstrap script installs all required dependencies, but for reference:

**Shell configuration expects:**
- [oh-my-zsh](https://ohmyz.sh/)
- [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
- [zsh-completions](https://github.com/zsh-users/zsh-completions)
- [fzf](https://github.com/junegunn/fzf)

**Tmux configuration expects:**
- [TPM](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)

**NeoVim configuration:**
- Managed in separate repository: [ThoDHa/nvim](https://github.com/ThoDHa/nvim)
