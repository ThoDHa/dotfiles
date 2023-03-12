#!/bin/bash

# set up VIM TMUX and Bash
mkdir ~/.vim/tmp/mkdir 

sudo apt-get install tmux vim fzf fd-find exuberant-ctags
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
##options to fzf command
#export FZF_COMPLETION_OPTS='--border --info=inline'

## Use fd (https://github.com/sharkdp/fd) instead of the default find
## command for listing path candidates.
## - The first argument to the function ($1) is the base path to start traversal
## - See the source code (completion.{bash,zsh}) for the details.
#_fzf_compgen_path() {
#	fd --hidden --follow --exclude ".git" . "$1"
#}
#
## Use fd to generate the list for directory completion
#_fzf_compgen_dir() {
#	fd --type d --hidden --follow --exclude ".git" . "$1"
#}
#
## Advanced customization of fzf options via _fzf_comprun function
## - The first argument to the function is the name of the command.
## - You should make sure to pass the rest of the arguments to fzf.
#_fzf_comprun() {
#	local command=$1
#		shift
#
#	case "$command" in
#		cd)           fzf --preview 'tree -C {} | head -200'   "$@" ;;
#		export|unset) fzf --preview "eval 'echo \$'{}"         "$@" ;;
#		ssh)          fzf --preview 'dig {}'                   "$@" ;;
#		*)            fzf --preview 'bat -n --color=always {}' "$@" ;;
#		esac
#}
#
##Custom fuzzy completion for "doge" command
##   e.g. doge **<TAB>
#_fzf_complete_doge() {
#	_fzf_complete --multi --reverse --prompt="doge> " -- "$@" < <(
#			echo very
#			echo wow
#			echo such
#			echo doge
#			)
#}


## Ctrl-Z: https://sheerun.net/2014/03/21/how-to-boost-your-vim-productivity/
#fancy-ctrl-z () {
#if [[ $#BUFFER -eq 0 ]]; then
#    BUFFER="fg"
#    zle accept-line
#else
#    zle push-input
#    zle clear-screen
#fi
#}
#zle -N fancy-ctrl-z
#bindkey '^Z' fancy-ctrl-z
#
## Set vim mode
#bindkey -v
# alias vim='nvim'
# alias ls='ls --color'


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

