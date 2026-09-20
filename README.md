# Setup:

Use the following steps to overwrite current dotfiles in ~, ignore dotfiles not in this repo, and install programs/dependencies that I use.

```bash
sudo apt update && sudo apt install git
alias dotfiles='/usr/bin/git --git-dir=$HOME/documents/dotfiles/ --work-tree=$HOME'
mkdir -p $HOME/documents 
git clone --bare git@github.com:pac256c/dotfiles.git $HOME/documents/dotfiles
dotfiles config --local status.showUntrackedFiles no
dotfiles checkout -f
chmod +x $HOME/.config/dotfiles/setup.sh
sudo source $HOME/.config/dotfiles/setup.sh 
```

After this, there are a few more steps to complete:
1. Open nvim by running "nvim", wait for lazy to install plugins, then run :MasonInstallAll and :TsInstallAll
2. Start tmux server by running "tmux", install tpm plugins using ctrl + I, reload using ctrl + r. Note in my config the tmux leader is ctrl + s.
3. Reboot linux

A few additional notes:
* The setup.sh script is written for 64-bit ubuntu. Setup will currently not work for other distros / instruction lengths.
* As per the commands above, this setup will require sudo privileges. I am planning on making a version for local install instead.
