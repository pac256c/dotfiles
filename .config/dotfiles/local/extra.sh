#!/usr/bin/env bash
# extra.sh - additional setup steps (links, directories, etc.)
# Customize this as needed. This is called by sync.sh step 5.

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

CONDA_PREFIX="${CONDA_PREFIX:-$HOME/.local/opt/miniforge3}"

# conda-forge's gcc/gxx metapackages install the compiler only under the
# target-triple name (x86_64-conda-linux-gnu-cc), but tree-sitter (used by
# nvim-treesitter) and other tools invoke a bare `cc`/`c++`. Symlink the
# generic names to the conda compilers so those builds work.
for pair in "cc:x86_64-conda-linux-gnu-cc" "c++:x86_64-conda-linux-gnu-c++"; do
  generic="${pair%%:*}"
  target="${pair##*:}"
  if [[ -x "$CONDA_PREFIX/bin/$target" && ! -e "$CONDA_PREFIX/bin/$generic" ]]; then
    ln -s "$target" "$CONDA_PREFIX/bin/$generic"
    log "  linked $CONDA_PREFIX/bin/$generic -> $target"
  fi
done

xdg-user-dirs-update

# NOTE: no chsh here. On the local (no-sudo) flow zsh lives only inside the
# conda env, so chsh can't find it (and would need root anyway). Instead, the
# default shell stays bash and ~/.bashrc -> ~/.config/bash/rc activates conda
# and execs zsh, which then sources ~/.zshenv and ~/.zshrc.

# Point fontconfig at the conda env's fonts (nerd fonts are installed there via conda recipes)
mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>$CONDA_PREFIX/share/fonts</dir>
</fontconfig>
EOF
fc-cache -fv "$CONDA_PREFIX/share/fonts"

# Desktop integration for conda-installed apps. The prebuilt kitty/zen recipes
# install their .desktop files under the conda prefix, but those hardcode
# `Exec=kitty`/`Exec=zen`, which desktop launchers (with the system PATH) can't
# resolve. Write machine-local entries that point at the conda prefix and
# register kitty as the xdg-terminal-exec handler.
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/kitty.desktop <<EOF
[Desktop Entry]
Encoding=UTF-8
Type=Application
NoDisplay=false
Exec=$CONDA_PREFIX/bin/kitty
TryExec=$CONDA_PREFIX/bin/kitty
Name=Kitty
Comment=Custom definition for Kitty
Icon=utilities-terminal
Categories=System;TerminalEmulator;
X-TerminalArgExec=--
X-TerminalArgTitle=--title
X-TerminalArgAppId=--class
X-TerminalArgDir=--working-directory
X-TerminalArgHold=--hold
EOF
if [[ -x "$CONDA_PREFIX/bin/zen" ]]; then
  cat > ~/.local/share/applications/zen.desktop <<EOF
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
NoDisplay=false
Exec=$CONDA_PREFIX/bin/zen
Name=Zen
Comment=Custom definition for Zen
EOF
fi
echo 'kitty.desktop' > ~/.config/xdg-terminals.list

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
