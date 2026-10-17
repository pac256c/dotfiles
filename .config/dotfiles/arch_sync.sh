#!/usr/bin/env bash
# arch_sync.sh - install everything for a fresh Arch Linux system
#
# Prerequisites: git and sudo exist. Run as normal user (not root).
# Steps:
# 1. Install yay if not present
# 2. Install pacman packages from install/paclist.txt (pacman -Qqen)
# 3. Install AUR packages from install/yaylist.txt (pacman -Qqem)
# 4. Build and install local PKGBUILDs from install/builds (after updating via gitfind.sh)
# 5. Call install/extra.sh for additional setup
#
# All operations are non-interactive.

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$DOTFILES_ROOT/install"

log() { printf '%s\n' "$*"; }

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

if [[ -f "$INSTALL_DIR/gitlist.txt" ]]; then
  log "=== Building and installing local PKGBUILDs ==="
  while IFS=$' \t' read -r name repo extra _ || [[ -n ${name:-} ]]; do
    [[ -z ${name:-} || $name == \#* ]] && continue
    pkgbuild="$INSTALL_DIR/builds/${name}_PKGBUILD"
    if [[ -f "$pkgbuild" ]]; then
      builddir="/tmp/build-${name}"
      rm -rf "$builddir"
      mkdir -p "$builddir"
      cp "$pkgbuild" "$builddir/PKGBUILD"
      (cd "$builddir" && makepkg -Cfis --noconfirm --needed --clean)
      rm -rf "$builddir"
    else
      log "  Warning: PKGBUILD not found for $name at $pkgbuild"
    fi
  done <"$INSTALL_DIR/gitlist.txt"
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
