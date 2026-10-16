# Setup:

To install programs and check out files with the following commands, keep these bullets in mind.
* Git needs to be installed (to clone/checkout)
* If calling sync.sh with distro=arch or ubuntu (to use the system package manager) sudo must be installed, unless you are running as root user and want to have your dotfiles in /root.
* Calling sync.sh with distro=local will install programs locally (to ~/.local) with local package managers (homebrew, cargo, go, pip, npm, etc.) which will install automatically.
* Calling sync.sh with distro=scratch will only install programs that can be built from scratch with no package manager
* The expected terminal emulator for this setup is kitty - the sync.sh script sets kitty as default, and kitty is personalized in .config/kitty.

```bash
mkdir -p $HOME/.config/.github
alias dotfiles='$(which git) --git-dir=$HOME/.config/.github --work-tree=$HOME' 
git clone --bare https://github.com/pac256c/dotfiles.git $HOME/.config/.github
dotfiles config --local status.showUntrackedFiles no
dotfiles checkout -f
cd $HOME/.config/.github/install
chmod +x sync.sh registry.sh update.sh
./sync.sh -k <distro> 
```

There are a few more steps to complete after executing these commands.
1. Open nvim by running "nvim", wait for lazy to install plugins, then run :MasonInstallAll and :TsInstallAll
2. Start tmux server by running "tmux", install tpm plugins using ctrl + I, reload using ctrl + r. Note in my config the tmux leader is ctrl + s.
3. Open ArtCraft launcher, install photo, film, pdf, word, deck, grid, sound, cad
4. Create your ~/.config/zsh/extras with extra aliases/functions you want.
5. Overwrite the "chat" alias with your ai cli agent. Ask it to call beep() in .zshrc when it completes a task or needs to ask the user for input. 
6. Reboot linux
