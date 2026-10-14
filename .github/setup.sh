#!/usr/bin/env bash

# clean up dotfiles in home directory.
cd ~
shopt -s nullglob
remove=(".Xauthority" ".xorg*" ".xsess" ".pam" ".sudo_*" ".bash*" ".profile")
for pattern in "${remove[@]}"; do
  for file in $pattern; do
    rm -r -f $file
  done
done

# rename XDG directories to lowercase
xdg_folders=("Desktop" "Downloads" "Templates" "Public" "Documents" "Music" "Pictures" "Videos")
for d in "${xdg_folders[@]}"; do
  lower="${d,,}"
  [ -d "$d" ] && mv "$d" "${d}_TMP" && mv "${d}_TMP" "$lower"
done
xdg-user-dirs-update --force

# cd to tmp for installs
cd /tmp

# install & use zsh by default 
sudo apt update && sudo apt install zsh -y
chsh -s $(which zsh)
sh -c "$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
cp $ZSH/themes/sorin.zsh-theme $ZSH_CUSTOM/themes/peter.zsh-theme
sed -i 's/%c/%~/g' $ZSH_CUSTOM/themes/peter.zsh-theme
zsh

# install nerd font - NOTE: still have to switch to this in gnome.
fonts=~/.local/share/fonts
mkdir -p "$fonts"
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/0xProto.zip
unzip 0xProto.zip -d "$fonts/0xProto"
fc-cache -fv "$fonts"

# prereq for tree-sitter: make/gcc.
sudo apt update && sudo apt install build-essential

# install curl - needed to lazy install packages
sudo apt update && sudo apt install curl

# install rustup/cargo
export RUSTUP_HOME=~/.local/opt/rustup
export CARGO_HOME=~/.local/opt/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
sudo mv $RUSTUP_HOME /opt/rustup
sudo mv $CARGO_HOME /opt/cargo
export $PATH=$PATH:/opt/cargo/bin

# install tree-sitter
cargo install tree-sitter-cli
sudo mv /opt/cargo/bin/tree-sitter-cli /usr/local/bin/tree-sitter

# install ripgrep
cargo install ripgrep
sudo mv /opt/cargo/bin/rg /usr/local/bin/rg

# install win32yank (for wsl)
https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip
unzip win32yank-x64.zip
chmod +x win32yank.exe
sudo mv win32yank.exe /usr/local/bin/win32yank.exe

# install neovim most recent version
wget https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz

# install tmux
sudo apt update && sudo apt install tmux

# install tmux plugin manager
git clone https://github.com/tmux-plugins/tpm $XDG_CONFIG_HOME/tmux/plugins/tpm

# install SSH server & start automatically on boot
sudo apt update && sudo apt install openssh-server -y
echo "sudo systemctrl start ssh" > ssh_start.sh
chmod +x ssh_start.sh
sudo mv ssh_start.sh /usr/local/bin/ssh_start.sh
(sudo crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/ssh_start.sh") | sudo crontab -

# install fzf
sudo apt update && sudo apt install fzf

# install go
wget https://go.dev/dl/go1.27.1.linux-amd64.tar.gz
tar -zxf go1.27.1.linux-amd64.tar.gz
sudo mv go /usr/local/go

# install bootdotdev
go install github.com/bootdotdev/bootdev@latest

# install python3
sudo apt update && sudo apt install python3
sudo apt update && sudo apt install python3-pip
python3 -m pip install pint
python3 -m pip install numpy
python3 -m pip install tomli
python3 -m pip install tomllib

# install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# install octave, java, jshell
sudo apt update && sudo apt install octave
sudo apt update && sudo apt install default-jdk

# install clang/cling for repl
sudo apt update && sudo apt install build-essential cmake ninja-buld libz-dev libtinfo-dev
mkdir cling-build-src
cd cling-build-src
git clone https://github.com/root-project/llvm-project.git src
cd src/clang-tools-extra
git clone https://github.com/root-project/cling.git cling
echo "add_subdirectory(cling)" >> CMakeLists.txt
cd /tmp/cling-build-src
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DLLVM_ENABLE_PROJECTS="clang" \
      ../src/llvm
make -j2
sudo make install
cd /tmp

# move .gnupg (privacy guard) to xdg if exists
mkdir -p ~/.local/share/gnupg
chmod 700 ~/.local/share/gnupg
if [[ -d "~/.gnupg" ]]; then
  cp -r ~/.gnupg/* ~/.local/share/gnupg
  rm -r -f ~/.gnupg
fi

# install opencode - figure this out later with nvm
curl -fsSL https://opencode.ai/install | bash
if [[ -d "~/.opencode" ]]; then
  mv ~/.opencode $XDG_CONFIG_HOME/opencode
fi

# install nvm & npm
mkdir -p ~/.local/share/nvm
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
nvm install 22.14.0

# install homebrew
wget https://github.com/Homebrew/brew/archive/refs/tags/7.0.9.tar.gz
tar zxf 7.0.9.tar.gz
sudo mv brew-7.0.9 /opt/homebrew

# install some command line tools - tldr and z
brew install tlrc
brew install zoxide

# install kitty terminal emulator
curl -L https://sw.kovidgyal.net/kitty/installer.sh | sh /dev/stdin dest=/tmp/kitty
sudo mv kitty/kitty.app /opt/kitty

# install yazi file manager
brew install ffmpeg-full sevenzip jq poppler 

# install yazi file manager & prereqs
brew install yazi --HEAD
brew install ffmpeg-full sevenzip jq poppler fd resvg imagemagick-full font-symbols-only-nerd-font
brew link ffmpeg-full imagemagick-full -f --overwrite

# install artcraft launcher for tools:
# word, excel, powerpoint, pdf, photoshop, premier pro, cad, sound
git clone https://github.com/storytold/craft-launcher
cd craft-launcher
cargo run --release -p artcraft-launcher
sudo mv craft-launcher/target/release /opt/artcraft-launcher
sudo ln -s /opt/artcraft-launcher/artcraft-launcher /usr/local/bin/artcraft-launcher

# later stuff - install zen browser
wget https://github.com/zen-browser/desktop/releases/download/1.23b/zen.linux-x86_64.tar.xz
tar -zxf zen.linux-x86_64.tar.xz
sudo mv zen /opt/zen-browser
sudo ln -s /opt/zen-browser/zen /usr/local/bin/zen
 
# install lua
sudo apt update && sudo apt install lua5.4

# install leetcode cli
npm install -g @night-slayer18/leetcode-cli

# still need to install bun for typescript repl


# cd back to ~ after installs
cd ~
