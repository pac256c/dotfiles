#!/usr/bin/env bash
# extra.sh - additional setup steps (links, directories, etc.)
# Customize this as needed. This is called by sync.sh step 4.

set -euo pipefail

log() { printf '%s\n' "$*"; }

log "extra.sh: running additional setup..."

for dir in desktop documents downloads games music pictures public templates videos; do
  if [ ! -d "$HOME/$dir" ]; then
    mkdir -p "$HOME/$dir"
    log "  created ~/$dir"
  fi
done

# State dirs for REPL history files (see ~/.config/zsh/env). Python's _pyrepl
# opens $PYTHON_HISTORY directly at startup and warns if its dir is missing.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/python"

PIXI_HOME="${PIXI_HOME:-$HOME/.local/opt/pixi}"
export PATH="$PIXI_HOME/bin:$PATH"

# xdg-user-dirs is built locally (builds/xdg-user-dirs) and exposed in
# $PIXI_HOME/bin.
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  xdg-user-dirs-update
fi

# NOTE: no chsh here. On the local (no-sudo) flow zsh lives only under
# $PIXI_HOME, so chsh can't find it (and would need root anyway). Instead, the
# default shell stays bash and ~/.bashrc -> ~/.config/bash/rc puts
# $PIXI_HOME/bin on PATH and execs zsh, which then sources ~/.zshenv and
# ~/.zshrc.

# Point fontconfig at the nerd fonts that sync.sh unpacks (no-executable
# packages are unpacked into $PIXI_HOME/prefix).
FONT_DIR="$PIXI_HOME/prefix/share/fonts"
mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf <<FCEOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>$FONT_DIR</dir>
</fontconfig>
FCEOF
if command -v fc-cache >/dev/null 2>&1; then
  mkdir -p "$FONT_DIR"
  fc-cache -fv "$FONT_DIR"
else
  log "  fc-cache not found; skipping font cache refresh"
fi

# Desktop integration for pixi-installed apps. The prebuilt kitty/zen packages
# have no launcher that desktop environments (with the system PATH) can
# resolve, so write machine-local entries that point at $PIXI_HOME/bin and
# register kitty as the xdg-terminal-exec handler.
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/kitty.desktop <<DEEOF
[Desktop Entry]
Encoding=UTF-8
Type=Application
NoDisplay=false
Exec=$PIXI_HOME/bin/kitty
TryExec=$PIXI_HOME/bin/kitty
Name=Kitty
Comment=Custom definition for Kitty
Icon=utilities-terminal
Categories=System;TerminalEmulator;
X-TerminalArgExec=--
X-TerminalArgTitle=--title
X-TerminalArgAppId=--class
X-TerminalArgDir=--working-directory
X-TerminalArgHold=--hold
DEEOF
if [[ -x "$PIXI_HOME/bin/zen" ]]; then
  cat > ~/.local/share/applications/zen.desktop <<DEEOF
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
NoDisplay=false
Exec=$PIXI_HOME/bin/zen
Name=Zen
Comment=Custom definition for Zen
DEEOF
fi
echo 'kitty.desktop' > ~/.config/xdg-terminals.list

mkdir -p ~/.local/share/gnupg
chmod 700 ~/.local/share/gnupg
if [ -d ~/.gnupg ]; then cp -r ~/.gnupg/. ~/.local/share/gnupg/ && rm -rf ~/.gnupg; fi

# Go builds use $HOME/.local/opt/go as GOPATH (outside the package prefixes so
# it works for both local and arch installs); .zshenv exports the same, so
# build and interactive go share one location. Fold any legacy default/interim
# GOPATH caches into it. Go marks its module cache read-only, so chmod before
# merging/removing. ~/.config/go is go's XDG config dir (telemetry/env), so it
# stays put.
GO_CACHE="$HOME/.local/opt/go"
mkdir -p "$GO_CACHE"
for legacy in "$HOME/go" "$HOME/.local/opt/miniforge3/go"; do
  if [ -d "$legacy" ]; then
    chmod -R u+w "$legacy" 2>/dev/null || true
    chmod -R u+w "$GO_CACHE" 2>/dev/null || true
    cp -a "$legacy/." "$GO_CACHE/" 2>/dev/null || true
    rm -rf "$legacy"
  fi
done
# Older setups used ~/.config/go as GOPATH; migrate only its cache/bin, leaving
# go's config dir (telemetry/env) intact.
if [ -d "$HOME/.config/go/pkg" ] || [ -d "$HOME/.config/go/bin" ]; then
  chmod -R u+w "$HOME/.config/go" 2>/dev/null || true
  chmod -R u+w "$GO_CACHE" 2>/dev/null || true
  for sub in pkg bin; do
    if [ -d "$HOME/.config/go/$sub" ]; then
      mkdir -p "$GO_CACHE/$sub"
      cp -a "$HOME/.config/go/$sub/." "$GO_CACHE/$sub/" 2>/dev/null || true
      rm -rf "$HOME/.config/go/$sub"
    fi
  done
fi

log "extra.sh: done."
