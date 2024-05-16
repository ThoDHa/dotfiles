#!/bin/bash
#
curl -LO https://github.com/neovim/neovim/releases/download/v0.10.0/nvim.appimage
chmod u+x nvim.appimage
rm -rf /squashfs-root
./nvim.appimage --appimage-extract
./squashfs-root/AppRun --version
mv squashfs-root /
ln -s /squashfs-root/AppRun /usr/bin/nvim
rm nvim.appimage
rm -rf squashfs-root

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
nvm install --lts 
nvm install-latest-npm

git clone https://github.com/ThoDHa/nvim.git ~/.config/nvim
nvim --headless "+Lazy! sync" +qa

