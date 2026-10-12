echo "running zshrc"

# make sure .zshenv has been run
source ~/.zshenv

# zsh settings:
ZSH_THEME="peter" # name of theme to load
plugins=(git) # set zsh plugins to load, separate by space
source $ZSH/oh-my-zsh.sh

# make fzf search dotfiles/directories
export FZF_DEFAULT_COMMAND="rg --files --hidden"

# make sure gnupg uses GNUPGHOME
if command -v systemvtrl &>/dev/null; then
  systemctl --user import-environment GNUPGHOME
fi

# load nvm   
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# source my zsh functions & aliases - keep at bottom of file
[ -f $XDG_CONFIG_HOME/zsh/functions ] && source $XDG_CONFIG_HOME/zsh/functions
[ -f $XDG_CONFIG_HOME/zsh/aliases ] && source $XDG_CONFIG_HOME/zsh/aliases


