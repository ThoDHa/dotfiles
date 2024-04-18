#!/bin/bash

sudo apt-get install git tmux vim exuberant-ctags curl gcc zsh zip unzip python3 wget fd-find bat tree ripgrep default-jdk -y

curl https://raw.githubusercontent.com/ThoDHa/confs/main/tmux.conf > ~/.tmux.conf

################################################################################
# zsh and OH MY ZSH
################################################################################
curl https://raw.githubusercontent.com/ThoDHa/confs/main/zshrc > ~/.zshrc
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
curl https://raw.githubusercontent.com/ThoDHa/confs/master/zshrc > ~/.zshrc
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions 
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
chsh -s $(which zsh)

################################################################################
# NVIM
################################################################################
sh nvim_install.sh

################################################################################
# FZF
################################################################################
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
