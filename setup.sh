#!/bin/bash

################################################################################
# set up VIM TMUX and Bash
################################################################################
mkdir ~/.vim/tmp/mkdir 

sudo apt-get install tmux vim exuberant-ctags git curl gcc -y
curl https://raw.githubusercontent.com/ThoDHa/confs/master/vimrc > ~/.vimrc
curl https://raw.githubusercontent.com/ThoDHa/confs/master/tmux.conf > ~/.tmux.conf
curl https://raw.githubusercontent.com/ThoDHa/confs/master/ctags > ~/.ctags.d/default.ctags

# This sets up VIM
mkdir -p ~/.vim/pack/themes/start
git clone https://github.com/tomasiser/vim-code-dark ~/.vim/pack/themes/start/vim-code-dark 

mkdir -p ~/.vim/pack/git-plugins/start
git clone --depth 1 https://github.com/dense-analysis/ale.git ~/.vim/pack/git-plugins/start/ale

################################################################################
# NVIM
################################################################################
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
./nvim.appimage --appimage-extract
./squashfs-root/AppRun --version
sudo mv squashfs-root /
sudo ln -s /squashfs-root/AppRun /usr/bin/nvim

sudo apt install ripgrep python3-pip3 -y
python3 -m pip install --user virtualenv
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
nvm install --lts 
nvm install-latest-npm
nvim.appimage

mkdir -m ~/.config/nvim
git clone https://github.com/ThoDHa/nvim.git ~/.config/nvim

################################################################################
# zsh and OH MY ZSH
################################################################################
sudo apt-get install zsh -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
curl https://raw.githubusercontent.com/ThoDHa/confs/master/zshrc > ~/.zshrc
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions 
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
chsh -s $(which zsh)

################################################################################
# FZF
################################################################################
sudo apt-get install fd-find bat tree -y
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

################################################################################
# REGOLITH
################################################################################
wget -qO - https://regolith-desktop.org/regolith.key | \
gpg --dearmor | sudo tee /usr/share/keyrings/regolith-archive-keyring.gpg > /dev/null

echo deb "[arch=amd64 signed-by=/usr/share/keyrings/regolith-archive-keyring.gpg] \
https://regolith-desktop.org/release-ubuntu-jammy-amd64 jammy main" | \
sudo tee /etc/apt/sources.list.d/regolith.list

sudo apt update
sudo apt install regolith-desktop regolith-compositor-picom-glx -y
sudo apt upgrade
sudo apt-get install i3xrocks-volume i3xrocks-battery dunst -y
sudo apt-get remove i3xrocks-net-traffic cpu-usage regolith-rofication -y

curl https://raw.githubusercontent.com/ThoDHa/confs/master/Xresources > ~/.config/regolith2/Xresources

mkdir ~/.config/regolith2/i3xrocks
cp -r /usr/share/i3xrocks/conf.d ~/.config/regolith2/i3xrocks
rm ~/.config/regolith2/i3xrocks/conf.d/30_net-traffic  
rm ~/.config/regolith2/i3xrocks/conf.d/40_cpu-usage    
mv ~/.config/regolith2/i3xrocks/conf.d/80_battery ~/.config/regolith2/i3xrocks/conf.d/90_battery
mv ~/.config/regolith2/i3xrocks/conf.d/80_volume ~/.config/regolith2/i3xrocks/conf.d/70_volume
mv ~/.config/regolith2/i3xrocks/conf.d/90_time ~/.config/regolith2/i3xrocks/conf.d/80_time
