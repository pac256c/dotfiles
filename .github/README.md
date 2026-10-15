# Setup:

Make sure git and sudo are installed in your distro (arch, ubuntu, local, scratch), and follow these steps to overwrite dotfiles and install programs i use:

```bash
mkdir -p $HOME/.local/state/dotfiles
alias dotfiles='$(which git) --git-dir=$HOME/.local/state/dotfiles/ --work-tree=$HOME' 
git clone --bare git@github.com:pac256c/dotfiles.git $HOME/.local/state/dotfiles
dotfiles config --local status.showUntrackedFiles no
dotfiles checkout -f
cd $HOME/.github
chmod +x sync.sh registry.sh
./sync.sh -k <distro> 
```

After this, there are a few more steps to complete:
1. Open nvim by running "nvim", wait for lazy to install plugins, then run :MasonInstallAll and :TsInstallAll
2. Start tmux server by running "tmux", install tpm plugins using ctrl + I, reload using ctrl + r. Note in my config the tmux leader is ctrl + s.
3. Open ArtCraft launcher, install photo,film,pdf,word,deck,grid,sound,cad
4. Reboot linux

A few additional notes:
* The setup.sh script is written for 64-bit ubuntu. Setup will currently not work for other distros / instruction lengths.
* As per the commands above, this setup will require sudo privileges. I am planning on making a version for local install instead.
* The setup script sets kitty as the default terminal emulator with nerd font 0xProto, so you should use kitty as your terminal emulator if using a GUI on your linux distro.
