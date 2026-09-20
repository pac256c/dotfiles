#!/usr/bin/env bash

# STEPS BEFORE:
# sudo apt update && sudo apt install git
# <clone git repo>
# chmod +x setup.sh
# sudo setup.sh

# STEPS AFTER: 
# use alacritty as terminal
# open nvim and run :MasonInstallAll, :TSInstallAll
# tmux and ctrl + I
# log out and back in (ctrl + alt + delete) after this.

# TODO:
# this will work for 64-bit ubuntu. changes needed for archlinux/64/32 bit
# create version for local install
# test git cloning
# make zshrc warn user about dotfiles?
# tmux resurrect + continuum + nvim AutoSession (plugins + autocmds.lua) not working
# autocmds.lua naming of unsaved files not really working..
# instead of installing oh my zsh, just add theme im using to repo?
# install npm - needed for lsps
# install languages for repl function
# make oh my zsh not need to install - choose theme & commit only files needed
# make gitignore positive.
# can probably delete code that substitutes into xdg dirs file
# move todo list to notes.md so i can use a checklist?

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
xdg_dirs_file=".config/user-dirs.dirs"
for d in "${xdg_folders[@]}"; do
  lower="${d,,}"
  
  [ -d "$d" ] && mv "$d" "${d}_TMP" && mv "${d}_TMP" "$lower"
  [ -f "$xdg_dirs_file" ] && sed -i "s/\b$d\b/$lower/g" "$xdg_dirs_file"
done
cat 'XDG_DESKTOP_DIR="$HOME/desktop"' >> "$xdg_dirs_file"
xdg-user-dirs-update --force

# cd to tmp for installs
cd /tmp

# install & use zsh by default 
sudo apt update && sudo apt install zsh -y
chsh -s $(which zsh)
sh -c "$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"

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

# install alacritty terminal
sudo apt install cmake pkg-config libfreetype6-dev libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3
cargo install alacritty
sudo mv /opt/cargo/bin/alacritty /usr/local/bin/alacritty
sudo update-alternatives --install /usr/local/bin/alacritty alacritty /usr/bin/zsh 1

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

# cd back to ~ after installs
cd ~
