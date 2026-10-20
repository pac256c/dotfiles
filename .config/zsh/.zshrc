# echo "running zshrc"

# make sure .zshenv has been run
source $ZDOTDIR/env

# zsh settings:
source $ZDOTDIR/peter.zsh-theme

# make fzf search dotfiles/directories
export FZF_DEFAULT_COMMAND="rg --files --hidden"

# make sure gnupg uses GNUPGHOME
if command -v systemvtrl &>/dev/null; then
  systemctl --user import-environment GNUPGHOME
fi

# load nvm   
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# initialize zoxide
eval "$(zoxide init zsh --cmd cd)"

# trigger bell on any task longer than 3 seconds, but turn sound off
unsetopt beep
beep() {
  if [ -n "$NVIM" ]; then
    nvim --server "$NVIM" --remote-expr "luaeval('(function() vim.loop.new_tty(1,false):write(\"\x07\"); return \"\" end)()')"
  else
    printf '\007'
  fi
}

preexec() {
  cmd_start_time=$SECONDS
}

precmd() {
  if [[ -n "$cmd_start_time" ]]; then
    local elapsed=$(( SECONDS - cmd_start_time ))
    if (( elapsed >= 3 )); then
      beep
    fi
    unset cmd_start_time
  fi
}

# source my zsh functions & aliases - keep at bottom of file
[ -f $XDG_CONFIG_HOME/zsh/functions ] && source $XDG_CONFIG_HOME/zsh/functions
[ -f $XDG_CONFIG_HOME/zsh/aliases ] && source $XDG_CONFIG_HOME/zsh/aliases
[ -f $XDG_CONFIG_HOME/zsh/extra ] && source $XDG_CONFIG_HOME/zsh/extra

# Conda setup - only if conda is actually installed (e.g. a local-install machine)
if [[ -f "$HOME/.local/opt/miniforge3/etc/profile.d/conda.sh" ]]; then
  . "$HOME/.local/opt/miniforge3/etc/profile.d/conda.sh"
  conda activate base >/dev/null 2>&1 || true
  # Let global binaries shadow conda's where they exist (kitty, git, ...).
  conda_defer_path
fi
