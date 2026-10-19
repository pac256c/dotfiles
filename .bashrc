# ~/.bashrc - stub. bash reads its config from $HOME, so keep the real
# contents under XDG. This file also needs to be sourced for login shells (from
# ~/.bash_profile).
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
[ -f "$XDG_CONFIG_HOME/bash/rc" ] && . "$XDG_CONFIG_HOME/bash/rc"
