#!/bin/bash
#
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
./nvim.appimage --appimage-extract
./squashfs-root/AppRun --version
mv squashfs-root /
ln -s /squashfs-root/AppRun /usr/bin/nvim
rm nvim.appimage
rm -rf squashfs-root

pip3 install neovim

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
nvm install --lts 
nvm install-latest-npm
python3 -m pip install --user virtualenv

git clone https://github.com/ThoDHa/nvim.git ~/.config/nvim
nvim --headless "+Lazy! sync" +qa \
  && nvim --headless "+MasonInstall jdtls eslint rust_analyzer marksman clangd lua_ls black markdownlint" -c qall

