```sh
#!/bin/bash

# set up VIM TMUX and Bash
mkdir ~/.vim/tmp/mkdir 

sudo apt-get install tmux vim fzf fd-find exuberant-ctags
curl https://raw.githubusercontent.com/ThoDHa/confs/master/vimrc > ~/vimrc
curl https://raw.githubusercontent.com/ThoDHa/confs/master/tmux.conf > ~/tmux.conf
curl https://raw.githubusercontent.com/ThoDHa/confs/master/ctags > ~/.ctags.d/default.ctags


mkdir -p ~/.vim/pack/themes/start
git clone https://github.com/tomasiser/vim-code-dark ~/.vim/pack/themes/start/vim-code-dark 

mkdir -p ~/.vim/pack/git-plugins/start
git clone --depth 1 https://github.com/dense-analysis/ale.git ~/.vim/pack/git-plugins/start/ale

# Add VIM Key bindings to bash
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

# Regolith things status bar things 
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
```
