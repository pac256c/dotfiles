#!/usr/bin/env bash
# sync.sh - install/sync everything for an Arch Linux system
# (run automatically by `dotfiles pull`, or manually)
#
# Prerequisites: git and sudo exist. Run as normal user (not root).
# Steps:
# 1. Install yay if not present
# 2. Install pacman packages from paclist.txt (pacman -Qqen)
# 3. Install AUR packages from yaylist.txt (pacman -Qqem)
# 4. Build and install local PKGBUILDs from builds/ (after updating via gitfind.sh)
# 5. Call extra.sh for additional setup
#
# Prompts once before installing/updating; otherwise non-interactive.

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$DOTFILES_ROOT"

log() { printf '%s\n' "$*"; }

log "=== Running the Arch install/update script ==="

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

sudo -v

# Step 1: Install yay if not present
if ! command -v yay >/dev/null 2>&1; then
  log "=== Installing yay ==="
  sudo pacman -S --noconfirm --needed base-devel git
  if [[ -d /tmp/yay ]]; then
    rm -rf /tmp/yay
  fi
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  (cd /tmp/yay && makepkg -si --noconfirm)
  rm -rf /tmp/yay
fi

# Step 2: Install pacman packages from paclist.txt
if [[ -f "$INSTALL_DIR/paclist.txt" ]]; then
  log "=== Installing pacman packages ==="
  # Filter out empty lines and comments if any
  grep -v '^#' "$INSTALL_DIR/paclist.txt" | grep -v '^$' | sudo pacman -S --noconfirm --needed -
else
  log "Warning: $INSTALL_DIR/paclist.txt not found, skipping pacman packages"
fi

# Step 3: Install AUR packages from yaylist.txt
if [[ -f "$INSTALL_DIR/yaylist.txt" ]]; then
  log "=== Installing AUR packages ==="
  grep -v '^#' "$INSTALL_DIR/yaylist.txt" | grep -v '^$' | yay -S --noconfirm --needed -
else
  log "Warning: $INSTALL_DIR/yaylist.txt not found, skipping AUR packages"
fi

# Step 4: Update PKGBUILDs from gitlist.txt and build/install local packages
if [[ -x "$INSTALL_DIR/gitfind.sh" ]]; then
  log "=== Updating local PKGBUILDs from gitlist.txt ==="
  "$INSTALL_DIR/gitfind.sh"
fi

log "=== Building and installing local PKGBUILDs ==="
shopt -s nullglob
pkgbuilds=("$INSTALL_DIR"/builds/*_PKGBUILD)
shopt -u nullglob
if ((${#pkgbuilds[@]})); then
  for pkgbuild in "${pkgbuilds[@]}"; do
    name="$(basename "$pkgbuild")"
    name="${name%_PKGBUILD}"
    builddir="/tmp/build-${name}"
    rm -rf "$builddir"
    mkdir -p "$builddir"
    cp "$pkgbuild" "$builddir/PKGBUILD"
    log "  building and installing $name ..."
    (cd "$builddir" && makepkg -Cfis --noconfirm --needed --clean)
    rm -rf "$builddir"
  done
else
  log "  no PKGBUILDs found in $INSTALL_DIR/builds"
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
