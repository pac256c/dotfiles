# Setup:

To install programs and check out files with the following commands, keep these bullets in mind.
* Git needs to be installed (to clone/checkout).
* Dotfiles live in a bare git repo at `~/.config/dotfiles` with the work-tree set to `$HOME`.
* Two install flows are provided:
  * **arch** (`arch/sync.sh`) - system packages via `yay` (official repos + AUR) from `arch/packages.txt`, plus locally-built PKGBUILDs from `arch/manlist.txt`. Requires sudo.
  * **local** (`local/sync.sh`) - no sudo/root needed. Installs Miniforge3 (conda) to `~/.local/opt/miniforge3`, conda-forge packages from `local/packages.txt`, and locally-built conda recipes from `local/manlist.txt`.
* The expected terminal emulator is kitty - the sync script sets it as default, and kitty is personalized in `.config/kitty`.

```bash
mkdir -p $HOME/.config/dotfiles
alias dotfiles='$(which git) --git-dir=$HOME/.config/dotfiles --work-tree=$HOME'
git clone --bare https://github.com/pac256c/dotfiles.git $HOME/.config/dotfiles
dotfiles config --local status.showUntrackedFiles no
dotfiles checkout -f
```

Then run the install flow for your machine:

```bash
# On Arch (system packages via yay/pacman):
$HOME/.config/dotfiles/arch/sync.sh

# Anywhere else (local, no sudo, via conda):
$HOME/.config/dotfiles/local/sync.sh
```

The scripts are executable in the repo; if a checkout drops the bit, `chmod +x` the `sync.sh`/`manfind.sh`/`extra.sh` you need.

There are a few more steps to complete after executing these commands.
1. Open nvim by running "nvim", wait for lazy to install plugins, then run :MasonInstallAll and :TsInstallAll
2. Start tmux server by running "tmux", install tpm plugins using ctrl + I, reload using ctrl + r. Note in my config the tmux leader is ctrl + s.
4. Create your ~/.config/zsh/extras with extra aliases/functions you want.
5. Overwrite the "chat" alias with your ai cli agent. Ask it to call beep() in .zshrc when it completes a task or needs to ask the user for input.
6. Reboot linux
