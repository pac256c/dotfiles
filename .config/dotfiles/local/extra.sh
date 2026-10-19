#!/usr/bin/env bash
# extra.sh - additional setup steps (links, directories, etc.)
# Customize this as needed. This is called by sync.sh step 5.

set -euo pipefail

log() { printf '%s\n' "$*"; }

log "extra.sh: running additional setup..."


xdg-user-dirs-update

# NOTE: no chsh here. On the local (no-sudo) flow zsh lives only inside the
# conda env, so chsh can't find it (and would need root anyway). Instead, the
# default shell stays bash and ~/.bashrc -> ~/.config/bash/rc activates conda
# and execs zsh, which then sources ~/.zshenv and ~/.zshrc.

# Point fontconfig at the conda env's fonts (nerd fonts are installed there via conda recipes)
CONDA_PREFIX="${CONDA_PREFIX:-$HOME/.local/opt/miniforge3}"
mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>$CONDA_PREFIX/share/fonts</dir>
</fontconfig>
EOF
fc-cache -fv "$CONDA_PREFIX/share/fonts"

mkdir -p ~/.local/share/gnupg
chmod 700 ~/.local/share/gnupg
if [ -d ~/.gnupg ]; then cp -r ~/.gnupg/. ~/.local/share/gnupg/ && rm -rf ~/.gnupg; fi

# Conda unconditionally touches ~/.conda/environments.txt (empty) on every
# install/create even with register_envs: false, and mamba can leave ~/.mamba
# behind. Both live under ~/.config now, so drop the stray $HOME folders.
if [ -d ~/.conda ] && [ "$(ls -A ~/.conda 2>/dev/null)" = "environments.txt" ]; then
  rm -rf ~/.conda
fi
rm -rf ~/.mamba

# Go builds use $HOME/.local/opt/go as GOPATH (outside the conda prefix so it
# works for both local and arch installs); .zshenv exports the same, so build
# and interactive go share one location. Fold any legacy default/interim
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
