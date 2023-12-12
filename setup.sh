#!/bin/bash

################################################################################
# set up VIM TMUX and Bash
################################################################################
mkdir ~/.vim/tmp/mkdir 

sudo apt-get install tmux vim exuberant-ctags git curl gcc -y
curl https://raw.githubusercontent.com/ThoDHa/confs/main/vimrc > ~/.vimrc
curl https://raw.githubusercontent.com/ThoDHa/confs/main/ctags > ~/.ctags.d/default.ctags

# This sets up VIM
mkdir -p ~/.vim/pack/themes/start
git clone https://github.com/tomasiser/vim-code-dark ~/.vim/pack/themes/start/vim-code-dark 

mkdir -p ~/.vim/pack/git-plugins/start
git clone --depth 1 https://github.com/dense-analysis/ale.git ~/.vim/pack/git-plugins/start/ale

min_setup.sh

################################################################################
# REGOLITH
################################################################################
# Register the Regolith public key to your local apt
wget -qO - https://regolith-desktop.org/regolith.key | gpg --dearmor | sudo tee /usr/share/keyrings/regolith-archive-keyring.gpg > /dev/null

# Add the repository URL to your local apt
echo deb "[arch=amd64 signed-by=/usr/share/keyrings/regolith-archive-keyring.gpg] https://regolith-desktop.org/release-ubuntu-jammy-amd64 jammy main" | \
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
