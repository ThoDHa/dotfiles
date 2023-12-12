#!/bin/bash

################################################################################
# set up TMUX and Bash
################################################################################
apt-get update && apt-get install tmux git curl gcc zsh -y
curl https://raw.githubusercontent.com/ThoDHa/confs/main/tmux.conf > ~/.tmux.conf
curl https://raw.githubusercontent.com/ThoDHa/confs/main/zshrc > ~/.zshrc

################################################################################
# NVIM
################################################################################
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
./nvim.appimage --appimage-extract
./squashfs-root/AppRun --version
mv squashfs-root /
ln -s /squashfs-root/AppRun /usr/bin/nvim
rm nvim.appimage

apt install ripgrep python3-pip3 -y
python3 -m pip install --user virtualenv
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
nvm install --lts 
nvm install-latest-npm
mkdir -m ~/.config/nvim
git clone https://github.com/ThoDHa/nvim.git ~/.config/nvim
nvim --headless "+Lazy! sync" +qa \
  && nvim --headless "+MasonInstall tsserver jdtls eslint rust_analyzer pyright marksman clangdlua_ls" -c qall

################################################################################
# zsh and OH MY ZSH
################################################################################
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
curl https://raw.githubusercontent.com/ThoDHa/confs/master/zshrc > ~/.zshrc
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions 
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
chsh -s $(which zsh)

################################################################################
# FZF
################################################################################
apt-get install fd-find bat tree -y
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
