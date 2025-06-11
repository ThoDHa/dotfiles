#!/bin/bash

################################################################################
# NVM and NPM
################################################################################

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | $SHELL 
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
nvm install --lts 
nvm install-latest-npm

################################################################################
# NVIM
################################################################################

curl -LO https://github.com/neovim/neovim/releases/download/v0.11.2/nvim-linux-x86_64.appimage
chmod u+x nvim-linux-x86_64.appimage
rm -rf /squashfs-root
./nvim-linux-x86_64.appimage --appimage-extract
./squashfs-root/AppRun --version
mv squashfs-root /
ln -s /squashfs-root/AppRun /usr/bin/nvim
rm nvim-linux-x86_64.appimage
rm -rf squashfs-root

git clone https://github.com/ThoDHa/nvim.git ~/.config/nvim
nvim --headless "+Lazy! sync" +qa
