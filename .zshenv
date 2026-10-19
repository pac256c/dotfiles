# runs every time zsh is started, login or not
# use this for env variables / XDG
# echo "running zenv vars"

# XDG home paths
export XDG_DATA_HOME=$HOME/.local/share
export XDG_CACHE_HOME=$HOME/.cache
export XDG_CONFIG_HOME=$HOME/.config
export XDG_STATE_HOME=$HOME/.local/state
export XDG_BIN_DIR=$HOME/.local/bin
export XDG_TEMPLATES_DIR=$HOME/templates
export XDG_PUBLICSHARE_DIR=$HOME/public
export XDG_DOCUMENTS_DIR=$HOME/documents
export XDG_MUSIC_DIR=$HOME/music
export XDG_PICTURES_DIR=$HOME/pictures
export XDG_VIDEOS_DIR=$HOME/videos
export XDG_DESKTOP_DIR=$HOME/desktop
export XDG_DOWNLOAD_DIR=$HOME/downloads
export XDG_GAMES_DIR=$HOME/games

# reroute program paths
export ZDOTDIR=$XDG_CONFIG_HOME/zsh
export GVIMINIT="so $XDG_CONFIG_HOME/nvim/init.lua"
export VIMINIT="so $XDG_CONFIG_HOME/nvim/init.lua"
export WGETRC=$XDG_CONFIG_HOME/wget/wgetrc
export WGET_HISTS=$XDG_DATA_HOME/wget-hsts
export LESSHISTFILE=$XDG_STATE_HOME/lesshst
export HISTFILE=$XDG_STATE_HOME/bash/history
export NVM_DIR=$XDG_DATA_HOME/nvm
export NPM_CONFIG_INIT_MODULE=$XDG_CONFIG_HOME/npm/config/npm-init.js
export NPM_CONFIG_CACHE=$XDG_CACHE_HOME/npm
export PYTHONSTARTUP=$XDG_CONFIG_HOME/python/pythonrc.py
export PYTHON_HISTORY=$XDG_STATE_HOME/python/history
export TS_NODE_HISTORY=$XDG_STATE_HOME/ts_node_repl_history
export OCTAVE_HISTFILE=$XDG_STATE_HOME/octave_hist
export CONDARC=$XDG_CONFIG_HOME/conda/condarc
export _JAVA_OPTIONS=-Djava.util.prefs.userRoot=$XDG_CONFIG_HOME/java
export NODE_REPL_HISTORY=$XDG_STATE_HOME/node_repl_history
export RUSTUP_HOME=$HOME/.local/opt/rustup
export CARGO_HOME=$HOME/.local/opt/cargo
export GOPATH=$HOME/.local/opt/go
export GNUPGHOME=$XDG_DATA_HOME/gnupg
export OPENCODE_CONFIG_DIR=$XDG_CONFIG_HOME/opencode
export OPENCODE_CONFIG=$XDG_CONFIG_HOME/opencode/opencode.json

# edit path variable (only add directories that exist)
for _dir in \
  /opt/nvim-linux-x86_64/bin \
  "$CARGO_HOME/bin" \
  "$OPENCODE_CONFIG_DIR/bin" \
  /opt/kitty/bin \
  "$GOPATH/bin" \
  /opt/cuda/bin; do
  [ -d "$_dir" ] && export PATH=$PATH:$_dir
done
unset _dir

# remove duplicates from $PATH if they exist
typeset -U path
