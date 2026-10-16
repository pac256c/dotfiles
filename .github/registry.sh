# ============================================================================
# registry.sh - program & method definitions, sourced by sync.sh
#
# This file is data only: it calls the add_* helpers defined in sync.sh to
# populate the registry. Keep it free of logic.
#
#   add_program NAME
#
#   add_install_method NAME KIND METHOD COMMAND      # single line
#   add_install_method NAME KIND METHOD <<'CMD'      # multi-line
#   <one or more install commands>
#   CMD
#
#   add_update_method NAME KIND METHOD COMMAND
#   add_update_method NAME KIND METHOD <<'CMD'
#   <one or more update commands>
#   CMD
#
# Per-program update methods are only needed when the update is specific to
# that program; KIND must match the install method's kind. Updates that are
# just "upgrade everything from this package manager" belong in the manager
# list below instead.
#
# Single-line commands are passed as a single-quoted argument so $variables
# expand when the command runs, not when this file is sourced. Multi-line
# commands use a quoted <<'CMD' heredoc for the same reason. Write one
# statement per line - each install is run as its own script with `set -e`.
# ============================================================================

# ----------------------------------------------------------------------------
# Package manager updates - catch-all commands run once per `update`, for each
# manager actually used to install a wanted program (per installed.state).
# ----------------------------------------------------------------------------
add_manager_update apt UBUNTU '$SUDO apt update && $SUDO apt upgrade -y'
add_manager_update pacman ARCH '$SUDO pacman -Syu --noconfirm'
add_manager_update yay ARCH 'yay -Syu --noconfirm'
add_manager_update brew LOCAL 'brew update && brew upgrade'

# ----------------------------------------------------------------------------
# Install methods for each program
# ----------------------------------------------------------------------------
add_program yay
add_install_method yay ARCH pacman << 'CMD'
$SUDO pacman -S --needed base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ..
CMD
add_update_method yay ARCH pacman << 'CMD'
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ..
CMD


add_program add-apt-repo
add_install_method apt-add-repo UBUNTU apt 'sudo apt update && sudo apt install -y software-properties-common'


add_program libnotify
add_install_method libnotify ARCH pacman '$SUDO pacman -S --noconfirm libnotify'


add_program zsh
add_install_method zsh UBUNTU apt << 'CMD'
$SUDO apt update && $SUDO apt install -y zsh
chsh -s $(which zsh)
CMD
add_install_method zsh ARCH pacman << 'CMD'
$SUDO pacman -S --noconfirm zsh
chsh -s $(which zsh)
CMD


add_program font-0xproto
add_install_method font-0xproto LOCAL wget <<'CMD'
mkdir -p ~/.local/share/fonts
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/0xProto.zip
unzip 0xProto.zip -d ~/.local/share/fonts/0xProto
fc-cache -fv ~/.local/share/fonts
CMD


add_program build-essential
add_install_method build-essential UBUNTU apt '$SUDO apt update && $SUDO apt install -y build-essential'
add_install_method build-essential ARCH pacman '$SUDO pacman -S --noconfirm base-devel'


add_program curl
add_install_method curl UBUNTU apt '$SUDO apt update && $SUDO apt install -y curl'
add_install_method curl ARCH pacman '$SUDO pacman -S --noconfirm curl'


add_program rust
add_install_method rust UBUNTU apt << 'CMD'
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
$SUDO apt update && $SUDO apt install -y rustup
export PATH=$PATH:/opt/cargo/bin
CMD
add_install_method rust ARCH pacman << 'CMD'
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
$SUDO pacman -S --noconfirm rustup
export PATH=$PATH:/opt/cargo/bin
CMD
add_install_method rust LOCAL script << 'CMD'
export RUSTUP_HOME=~/.local/opt/rustup
export CARGO_HOME=~/.local/opt/cargo
curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
CMD
add_update_method rust LOCAL script 'rustup update'


add_program tree-sitter
add_install_method tree-sitter UBUNTU apt '$SUDO apt update && $SUDO apt install -y tree-sitter-cli'
add_install_method tree-sitter ARCH pacman '$SUDO pacman -S --noconfirm tree-sitter tree-sitter-cli'
add_install_method tree-sitter LOCAL cargo 'cargo install tree-sitter-cli'
add_update_method tree-sitter LOCAL cargo 'cargo install --force tree-sitter-cli'


add_program ripgrep
add_install_method ripgrep UBUNTU apt '$SUDO apt update && $SUDO apt install -y ripgrep'
add_install_method ripgrep ARCH pacman '$SUDO pacman -S --noconfirm ripgrep'
add_install_method ripgrep LOCAL cargo 'cargo install ripgrep'
add_update_method ripgrep LOCAL cargo 'cargo install --force ripgrep'


add_program win32yank
add_install_method win32yank LOCAL wget <<'CMD'
wget https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip
unzip win32yank-x64.zip
chmod +x win32yank.exe
$SUDO mv win32yank.exe /usr/local/bin/win32yank.exe
CMD


add_program neovim
add_install_method neovim UBUNTU apt '$SUDO apt update && $SUDO apt install -y neovim'
add_install_method neovim ARCH pacman '$SUDO pacman -S --noconfirm neovim'
add_install_method neovim LOCAL github <<'CMD'
wget https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
$SUDO tar -C /opt -xzf nvim-linux-x86_64.tar.gz
CMD


add_program tmux
add_install_method tmux UBUNTU apt '$SUDO apt update && $SUDO apt install -y tmux'
add_install_method tmux ARCH pacman '$SUDO pacman -S --noconfirm tmux'


add_program tpm
add_install_method tpm LOCAL git 'git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm'
add_update_method tpm LOCAL git 'git -C ~/.config/tmux/plugins/tpm pull'


add_program openssh-server
add_install_method openssh-server UBUNTU apt <<'CMD'
$SUDO apt update && $SUDO apt install openssh-server -y
echo "$SUDO systemctrl start ssh" > ssh_start.sh
chmod +x ssh_start.sh
$SUDO mv ssh_start.sh /usr/local/bin/ssh_start.sh
($SUDO crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/ssh_start.sh") | $SUDO crontab -
CMD
add_install_method openssh-server ARCH pacman <<'CMD'
$SUDO pacman -S --noconfirm openssh
$SUDO systemctl enable --now sshd
CMD


add_program fzf
add_install_method fzf UBUNTU apt '$SUDO apt update && $SUDO apt install -y fzf'
add_install_method fzf ARCH pacman '$SUDO pacman -S --noconfirm fzf'


add_program go
add_install_method go UBUNTU apt '$SUDO apt update && $SUDO apt install golang go'
add_install_method go ARCH pacman '$SUDO pacman -S --noconfirm go'
add_install_method go LOCAL wget <<'CMD'
wget https://go.dev/dl/go1.27.1.linux-amd64.tar.gz
tar -zxf go1.27.1.linux-amd64.tar.gz
$SUDO mv go /usr/local/go
CMD


add_program bootdev
add_install_method bootdev LOCAL go 'go install github.com/bootdotdev/bootdev@latest'
add_update_method boootdev LOCAL go 'go install github.com/bootdotdev/bootdev@latest'


add_program python3
add_install_method python3 UBUNTU apt '$SUDO apt update && $SUDO apt install -y python3 python3-pip'
add_install_method python3 ARCH pacman '$SUDO pacman -S --noconfirm python python-pip'


add_program python-pkgs
add_install_method python-pkgs LOCAL pip 'python -m pip install --user pint numpy tomli'
add_update_method python-pkgs LOCAL pip 'python -m pip install --user --upgrade pint numpy tomli'


add_program uv
add_install_method uv ARCH pacman '$SUDO pacman -S --noconfirm uv'
add_install_method uv LOCAL script 'curl -LsSf https://astral.sh/uv/install.sh | sh'
add_update_method uv LOCAL script 'uv self update'


add_program octave
add_install_method octave UBUNTU apt '$SUDO apt update && $SUDO apt install -y octave'
add_install_method octave ARCH pacman '$SUDO pacman -S --noconfirm octave'


add_program jdk
add_install_method jdk UBUNTU apt '$SUDO apt update && $SUDO apt install -y default-jdk'
add_install_method jdk ARCH pacman '$SUDO pacman -S --noconfirm jdk-openjdk'


add_program cmake_ninja
add_install_method cmake_ninja UBUNTU apt '$SUDO apt update && $SUDO apt install -y cmake ninja-build libz-dev libtinfo-dev'
add_install_method cmake_ninja ARCH pacman '$SUDO pacman -S --noconfirm cmake ninja zlib ncurses'


add_program cling
add_install_method cling UBUNTU apt << 'CMD'
$SUDO add-apt-repository ppa:ppa-verse/cling
sudo apt update && sudo apt install -y cling
sudo apt install -y clang llvm
CMD
add_install_method cling ARCH yay 'yay -S --noconfirm cling'
add_install_method cling SCRATCH source <<'CMD'
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
CMD


add_program gnupg
add_install_method gnupg UBUNTU apt <<'CMD'
$SUDO apt update && $SUDO apt install -y gnupg
mkdir -p ~/.local/share/gnupg
chmod 700 ~/.local/share/gnupg
if [ -d ~/.gnupg ]; then cp -r ~/.gnupg/. ~/.local/share/gnupg/ && rm -rf ~/.gnupg; fi
CMD
add_install_method gnupg ARCH pacman <<'CMD'
$SUDO pacman -S --noconfirm gnupg
mkdir -p ~/.local/share/gnupg
chmod 700 ~/.local/share/gnupg
if [ -d ~/.gnupg ]; then cp -r ~/.gnupg/. ~/.local/share/gnupg/ && rm -rf ~/.gnupg; fi
CMD


add_program opencode
add_install_method opencode ARCH yay 'yay -S --noconfirm opencode-bin'
add_install_method opencode LOCAL script 'curl -fsSL https://opencode.ai/install | bash'


add_program nvm
add_install_method nvm LOCAL script <<'CMD'
mkdir -p ~/.local/share/nvm
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
nvm install 22.14.0
CMD
add_install_method nvm ARCH yay 'yay -S --noconfirm nvm'


add_program homebrew
add_install_method homebrew LOCAL wget <<'CMD'
wget https://github.com/Homebrew/brew/archive/refs/tags/7.0.9.tar.gz
tar zxf 7.0.9.tar.gz
sudo mv brew-7.0.9 /opt/homebrew
CMD


add_program tlrc
add_install_method tlrc ARCH yay 'yay -S --noconfirm tlrc'
add_install_method tlrc LOCAL brew 'brew install tlrc'


add_program zoxide
add_install_method zoxide UBUNTU apt '$SUDO apt update && sudo apt install -y zoxide'
add_install_method zoxide ARCH pacman '$SUDO pacman -S --noconfirm zoxide'
add_install_method zoxide LOCAL brew 'brew install zoxide'


add_program kitty
add_install_method kitty UBUNTU apt '$SUDO apt update && $SUDO apt install -y kitty'
add_install_method kitty ARCH pacman '$SUDO pacman -S --noconfirm kitty'
add_install_method kitty LOCAL script 'curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin dest=/opt/kitty'


add_program yazi_deps
add_install_method yazi_deps UBUNTU apt << 'CMD'
$SUDO apt update
$SUDO apt install -y jq fd-find poppler-utils imagemagick
$SUDO cargo install resvg
brew install font-symbols-only-nerd-font
CMD
add_install_method yazi_deps ARCH pacman << 'CMD'
$SUDO pacman -Syu --noconfirm jq poppler poppler-utils fd imagemagick
$SUDO yay -S ffmpeg-full sevenzip resvg-bin ttf-nerd-fonts-symbols-common
CMD
add_install_method yazi_deps LOCAL brew 'brew install ffmpeg-full sevenzip jq poppler fd resvg imagemagick-full font-symbols-only-nerd-font; brew link ffmpeg-full imagemagick-full -f --overwrite'


add_program yazi
add_install_method yazi LOCAL brew <<'CMD'
brew install yazi --HEAD
CMD
add_install_method yazi ARCH pacman '$SUDO pacman -S --noconfirm yazi'


add_program lua
add_install_method lua UBUNTU apt '$SUDO apt update && $SUDO apt install -y lua5.4'
add_install_method lua ARCH pacman '$SUDO pacman -S --noconfirm lua'


add_program bun
add_install_method bun ARCH yay 'yay -S --noconfirm bun-bin'
add_install_method bun LOCAL script 'curl -fsSL https://bun.sh/install | bash'
add_update_method bun LOCAL script 'bun upgrade'


add_program artcraft-launcher
add_install_method artcraft-launcher SCRATCH source <<'CMD'
git clone https://github.com/storytold/craft-launcher
cd craft-launcher
cargo run --release -p artcraft-launcher
$SUDO mv craft-launcher/target/release /opt/artcraft-launcher
$SUDO ln -s /opt/artcraft-launcher/artcraft-launcher /usr/local/bin/artcraft-launcher
CMD


add_program zen-browser
add_install_method zen-browser ARCH yay 'yay -S --noconfirm zen-browser-bin'
add_install_method zen-browser LOCAL wget <<'CMD'
wget -qO /tmp/zen.tar.xz https://github.com/zen-browser/desktop/releases/download/1.23b/zen.linux-x86_64.tar.xz
$SUDO rm -rf /opt/zen-browser
$SUDO tar -C /opt -xJf /tmp/zen.tar.xz
$SUDO ln -sf /opt/zen/zen /usr/local/bin/zen
CMD


add_program leetcode-cli
add_install_method leetcode-cli LOCAL npm 'npm install -g @night-slayer18/leetcode-cli'
add_update_method leetcode-cli LOCAL npm 'npm update -g @night-slayer18/leetcode-cli'
