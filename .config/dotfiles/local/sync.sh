#!/usr/bin/env bash
# sync.sh - install/sync everything locally via Homebrew (no sudo/root needed)
# (run automatically by `dotfiles pull`, or manually)
#
# Prerequisites: git exists. Run as normal user (not root).
# Steps:
# 1. Install Homebrew to ~/.local/opt/homebrew if not present
# 2. Install brew formulae from brewlist.txt
# 3. Optionally install casks from brewcask.txt and extras from brewextra.txt
# 4. Process any local builds in builds/ (if present)
# 5. Call extra.sh for additional setup
#
# Prompts once before installing/updating; otherwise non-interactive.

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$DOTFILES_ROOT"

log() { printf '%s\n' "$*"; }

log "=== Running the local install/update script (Homebrew-based) ==="

# Warn about stray dotfiles in $HOME
allowed_home_entries=".config .zshenv .local .cache"
strays=()
shopt -s nullglob
for entry in "$HOME"/.*; do
  name="${entry##*/}"
  [[ $name == "." || $name == ".." ]] && continue
  case " $allowed_home_entries " in
    *" $name "*) continue ;;
  esac
  strays+=("$name")
done
shopt -u nullglob

if ((${#strays[@]})); then
  log ""
  log "Warning: found stray dotfiles in $HOME:"
  for name in "${strays[@]}"; do
    log "  $name"
  done
  log "Consider moving them into ~/.config (or another managed location)."
fi

log ""
read -r -p "Would you like to update/install programs? [y/N] " reply
case "$reply" in
  [Yy]*) ;;
  *)
    log "Exiting without making changes."
    exit 0
    ;;
esac

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "do not run as root" >&2
  exit 1
fi

# Step 1: Install Homebrew if not present (to ~/.local/opt/homebrew)
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$HOME/.local/opt/homebrew}"
HOMEBREW_BIN="$HOMEBREW_PREFIX/bin"
if ! command -v brew >/dev/null 2>&1; then
  log "=== Installing Homebrew ==="
  if [[ ! -d "$HOMEBREW_PREFIX" ]]; then
    mkdir -p "$(dirname "$HOMEBREW_PREFIX")"
    git clone --depth=1 https://github.com/Homebrew/brew "$HOMEBREW_PREFIX"
  fi
  export PATH="$HOMEBREW_BIN:$PATH"
fi
export PATH="$HOMEBREW_BIN:$PATH"
eval "$("$HOMEBREW_PREFIX"/bin/brew shellenv 2>/dev/null || true)" 2>/dev/null || true

# Step 2: Install Homebrew packages from brewlist.txt
if [[ -f "$INSTALL_DIR/brewlist.txt" ]]; then
  log "=== Installing Homebrew packages ==="
  grep -v '^#' "$INSTALL_DIR/brewlist.txt" | grep -v '^$' | xargs -r brew install
else
  log "Warning: $INSTALL_DIR/brewlist.txt not found, skipping brew packages"
fi

# Step 3: Install brew "local AUR-like" packages from brewcask.txt or brewextra.txt if present
if [[ -f "$INSTALL_DIR/brewcask.txt" ]]; then
  log "=== Installing Homebrew cask packages ==="
  grep -v '^#' "$INSTALL_DIR/brewcask.txt" | grep -v '^$' | xargs -r brew install --cask
fi
if [[ -f "$INSTALL_DIR/brewextra.txt" ]]; then
  log "=== Installing Homebrew extra packages ==="
  grep -v '^#' "$INSTALL_DIR/brewextra.txt" | grep -v '^$' | xargs -r brew install
fi

# Step 4: Handle local builds (if any) - adapt for local installs
if [[ -x "$INSTALL_DIR/gitfind.sh" ]]; then
  log "=== Updating local builds from gitlist.txt ==="
  "$INSTALL_DIR/gitfind.sh"
fi

log "=== Processing local build scripts/formulas ==="
shopt -s nullglob
builds=("$INSTALL_DIR"/builds/*)
shopt -u nullglob
if ((${#builds[@]})); then
  for build in "${builds[@]}"; do
    log "  found build artifact: $(basename "$build")"
  done
else
  log "  no local builds found in $INSTALL_DIR/builds"
fi

# Step 5: Call extra.sh
if [[ -x "$INSTALL_DIR/extra.sh" ]]; then
  log "=== Running extra.sh ==="
  "$INSTALL_DIR/extra.sh"
elif [[ -f "$INSTALL_DIR/extra.sh" ]]; then
  log "=== Running extra.sh ==="
  bash "$INSTALL_DIR/extra.sh"
else
  log "Warning: $INSTALL_DIR/extra.sh not found, skipping extra steps"
fi

log ""
log "=== Done ==="
