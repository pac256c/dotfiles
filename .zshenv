# runs every time zsh is started, login or not
# use this for env variables / XDG

#XDG home paths
export XDG_DATA_HOME=$HOME/.local/share
export XDG_CACHE_HOME=$HOME/.cache
export XDG_CONFIG_HOME=$HOME/.config
export XDG_STATE_HOME=$HOME/.local/state

#reroute program paths
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export PYTHON_HISTORY=$XDG_STATE_HOME/python_history
export PYTHONSTARTUP=$XDG_CONFIG_HOME/python/pythonrc.py
export NVM_DIR=$XDG_DATA_HOME/nvm
export NODE_REPL_HISTORY=$XDG_STATE_HOME/node_repl_history
export WGETRC=$XDG_CONFIG_HOME/wget/wgetrc
export WGET_HISTS=$XDG_DATA_HOME/wget-hsts
export GVIMINIT="so $XDG_CONFIG_HOME/nvim/init.lua"
export VIMINIT="so $XDG_CONFIG_HOME/nvim/init.lua"
export TS_NODE_HISTORY=$XDG_STATE_HOME/ts_node_repl_history
export OCTAVE_HISTFILE=$XDG_STATE_HOME/octave_hist
export LESSHISTFILE=$XDG_STATE_HOME/lesshst
export _JAVA_OPTIONS=-Djava.util.prefs.userRoot=$XDG_CONFIG_HOME/java
export NPM_CONFIG_INIT_MODULE=$XDG_CONFIG_HOME/npm/config/npm-init.js
export NPM_CONFIG_CACHE=$XDG_CACHE_HOME/npm
export NPM_CONFIG_TMP=$XDG_RUNTIME_DIR/npm
export HISTFILE=$XDG_STATE_HOME/bash/history
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo


#edit path variable
export PATH=$PATH:/opt/nvim-linux-x86_64/bin
export PATH=$PATH:$CARGO_HOME/bin
