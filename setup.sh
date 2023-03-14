#!/bin/bash

# set up VIM TMUX and Bash
mkdir ~/.vim/tmp/mkdir 

sudo apt-get install tmux vim fd-find bat exuberant-ctags zsh
curl https://raw.githubusercontent.com/ThoDHa/confs/master/vimrc > ~/.vimrc
curl https://raw.githubusercontent.com/ThoDHa/confs/master/tmux.conf > ~/.tmux.conf
curl https://raw.githubusercontent.com/ThoDHa/confs/master/ctags > ~/.ctags.d/default.ctags

# This sets up VIM
mkdir -p ~/.vim/pack/themes/start
git clone https://github.com/tomasiser/vim-code-dark ~/.vim/pack/themes/start/vim-code-dark 

mkdir -p ~/.vim/pack/git-plugins/start
git clone --depth 1 https://github.com/dense-analysis/ale.git ~/.vim/pack/git-plugins/start/ale

# nvim
# Install the latest NVIM using the link.
# https://github.com/neovim/neovim/releases/tag/stable
sudo apt install ripgrep
python3 -m pip install --user virtualenv
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
nvm install latest
nvm install-latest-npm

mkdir -m ~/.config/nvim
git clone https://github.com/ThoDHa/nvim.git ~/.config/nvim

# This sets up bash
if grep -q "set -o vi" ~/.bashrc; then
	echo "set -o vi" >> ~/.bashrc
fi

# Set up fzf to work correctly
if grep -q "source /usr/share/doc/fzf/examples/key-bindings.bash" ~/.bashrc; then
	echo "source /usr/share/doc/fzf/examples/key-bindings.bash" >> ~/.bashrc
fi

if grep -q "source /usr/share/doc/fzf/examples/completion.bash" ~/.bashrc; then
	echo "source /usr/share/doc/fzf/examples/completion.bash" >> ~/.bashrc
fi

# zsh
# OH MY SH
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
curl http://raw.githubusercontent.com/ThoDHa/confs/master/zshrc > ~/.zshrc
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions 
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# FZF
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install


# REGOLITH
sudo apt-get install i3xrocks-volume i3xrocks-battery dunst
sudo apt-get remove i3xrocks-net-traffic cpu-usage regolith-rofication

curl https://raw.githubusercontent.com/ThoDHa/confs/master/Xresources > ~/.config/regolith2/Xresources

mkdir ~/.config/regolith2/i3xrocks
mkdir ~/.config/regolith2/i3xrocks/
cp -r /usr/share/i3xrocks/conf.d ~/.config/regolith2/i3xrocks
rm ~/.config/regolith2/i3xrocks/conf.d/30_net-traffic  
rm ~/.config/regolith2/i3xrocks/conf.d/40_cpu-usage    
mv ~/.config/regolith2/i3xrocks/conf.d/80_battery ~/.config/regolith2/i3xrocks/conf.d/90_battery
mv ~/.config/regolith2/i3xrocks/conf.d/80_volume ~/.config/regolith2/i3xrocks/conf.d/70_volume
mv ~/.config/regolith2/i3xrocks/conf.d/90_time ~/.config/regolith2/i3xrocks/conf.d/80_time

