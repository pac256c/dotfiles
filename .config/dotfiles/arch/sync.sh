#!/usr/bin/env bash
# sync.sh - install/sync everything for an Arch Linux system
# (run automatically by `dotfiles pull`, or manually)
#
# Prerequisites: git and sudo exist. Run as normal user (not root).
# Steps:
# 1. Install yay if not present
# 2. Install packages from packages.txt via yay (official repos + AUR)
# 3. Update local PKGBUILDs from manlist.txt and build/install builds/
# 4. Call extra.sh for additional setup
#
# Prompts once before installing/updating; otherwise non-interactive.

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$DOTFILES_ROOT"

# Per-machine state (not part of the repo). Records which packages were built
# locally so a later run can detect ones that became stale.
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/dotfiles"

log() { printf '%s\n' "$*"; }

log "=== Running the Arch install/update script ==="

# Warn about stray dotfiles in $HOME
allowed_home_entries=".config .zshenv .bash_profile .bashrc .local .cache"
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

log ""
read -r -p "Would you like to install programs one by one? [y/N] " per_pkg_reply
PER_PKG_INSTALL=false
case "$per_pkg_reply" in
  [Yy]*) PER_PKG_INSTALL=true ;;
  *) PER_PKG_INSTALL=false ;;
esac

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "do not run as root" >&2
  exit 1
fi

# Allow skipping sudo for testing
if [[ -n "${SUDO_SKIP:-}" ]]; then
  log "SUDO_SKIP set; skipping sudo checks and privileged operations"
else
  if ! sudo -v 2>/dev/null; then
    echo "sudo is required but not available non-interactively; set SUDO_SKIP=1 to skip privileged operations" >&2
    exit 1
  fi
fi

# Step 1: Install yay if not present
if ! command -v yay >/dev/null 2>&1; then
  log "=== Installing yay ==="
  if [[ -z "${SUDO_SKIP:-}" ]]; then
    sudo pacman -S --noconfirm --needed base-devel git
    if [[ -d /tmp/yay ]]; then
      rm -rf /tmp/yay
    fi
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
    rm -rf /tmp/yay
  else
    log "  SUDO_SKIP: would install yay"
  fi
fi

# Refresh package databases before installing (official repos + AUR)
if [[ -z "${SUDO_SKIP:-}" ]]; then
  log "=== Refreshing package databases ==="
  yay -Syu --noconfirm
else
  log "=== Refreshing package databases (skipped - SUDO_SKIP set) ==="
fi

# Step 2: Install packages from packages.txt (official repos + AUR) via yay.
# Packages that are built locally from manlist.txt are removed from the system
# and skipped here, so both stay in sync with the lists.
if [[ -f "$INSTALL_DIR/packages.txt" ]]; then
  log "=== Installing packages from packages.txt ==="

  # Packages built locally by a previous run (recorded in the per-machine state
  # file) that are no longer in manlist.txt are stale; remove them so a
  # packages.txt replacement (e.g. wordcraft -> wordcraft-bin) can be installed
  # without a conflict.
  BUILT_STATE="$STATE_DIR/built"
  if [[ -f "$BUILT_STATE" ]]; then
    stale=()
    while IFS= read -r bname; do
      [[ -z "$bname" ]] && continue
      grep -qE "^[[:space:]]*${bname}([[:space:]]|\$)" "$INSTALL_DIR/manlist.txt" && continue
      pacman -Qq "$bname" >/dev/null 2>&1 && stale+=("$bname")
    done < "$BUILT_STATE"
    if ((${#stale[@]})); then
      log "  removing stale locally-built packages: ${stale[*]}"
      if [[ -z "${SUDO_SKIP:-}" ]]; then
        sudo pacman -Rns --noconfirm "${stale[@]}" || log "  WARNING: failed to remove some stale packages"
      else
        log "    SUDO_SKIP: would remove: ${stale[*]}"
      fi
    fi
  fi

  # packages.txt minus manlist-built packages (those are built in Step 3)
  man_pkgs=()
  if [[ -f "$INSTALL_DIR/manlist.txt" ]]; then
    while IFS=$' \t' read -r mname _ || [[ -n ${mname:-} ]]; do
      [[ -z ${mname:-} || $mname == \#* ]] && continue
      man_pkgs+=("$mname")
    done < "$INSTALL_DIR/manlist.txt"
  fi

  filtered=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    skip=false
    for mp in "${man_pkgs[@]}"; do
      [[ "$pkg" == "$mp" ]] && skip=true && break
    done
    if [[ "$skip" == true ]]; then
      log "  skipping $pkg (built locally from manlist.txt)"
      continue
    fi
    filtered+=("$pkg")
  done < <(grep -v '^#' "$INSTALL_DIR/packages.txt" | grep -v '^[[:space:]]*$')

  if ((${#filtered[@]})); then
    if [[ -z "${SUDO_SKIP:-}" ]]; then
      # Install one at a time so a single bad/missing package does not abort the batch.
      failed=()
      for pkg in "${filtered[@]}"; do
        if [[ "$PER_PKG_INSTALL" == "true" ]]; then
          read -r -p "  Install $pkg? [y/N] " p_reply
          case "$p_reply" in
            [Yy]*) ;;
            *)
              log "  skipping $pkg"
              continue
              ;;
          esac
        fi
        log "  installing $pkg ..."
        if ! yay -S --noconfirm --needed --removemake "$pkg"; then
          log "  WARNING: failed to install $pkg (continuing)"
          failed+=("$pkg")
        fi
      done
      if ((${#failed[@]})); then
        log "  failed packages: ${failed[*]}"
      fi
    else
      log "  SUDO_SKIP: would install packages:"
      for pkg in "${filtered[@]}"; do
        if [[ "$PER_PKG_INSTALL" == "true" ]]; then
          log "    (would prompt) $pkg"
        else
          log "    $pkg"
        fi
      done
    fi
  else
    log "  no packages to install after filtering"
  fi
else
  log "Warning: $INSTALL_DIR/packages.txt not found, skipping package installs"
fi

# Step 3: Update PKGBUILDs from manlist.txt and build/install local packages
# Avoid conda/python from interfering with native builds (pyo3 etc.)
unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_SHLVL CONDA_PYTHON_EXE 2>/dev/null || true
export PYO3_PYTHON=/usr/bin/python3
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if [[ -x "$INSTALL_DIR/manfind.sh" ]]; then
  log "=== Updating local PKGBUILDs from manlist.txt ==="
  manfind_rc=0
  "$INSTALL_DIR/manfind.sh" || manfind_rc=$?
  if ((manfind_rc != 0)); then
    log "  WARNING: manfind.sh finished with errors (exit $manfind_rc); continuing with existing PKGBUILDs"
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
      log "  hint: if the errors are GitHub 403/rate-limit, export GITHUB_TOKEN to raise the API rate limit"
    fi
  fi
fi

log "=== Building and installing local PKGBUILDs ==="
shopt -s nullglob
pkgbuilds=("$INSTALL_DIR"/builds/*/PKGBUILD)
shopt -u nullglob
# Record which packages are built locally so future runs can detect stale ones.
BUILT_STATE="$STATE_DIR/built"
mkdir -p "$STATE_DIR"
if ((${#pkgbuilds[@]})); then
  failed_builds=()
  built_names=()
  for pkgbuild in "${pkgbuilds[@]}"; do
    name="$(basename "$(dirname "$pkgbuild")")"
    built_names+=("$name")
    builddir="/tmp/build-${name}"
    rm -rf "$builddir"
    mkdir -p "$builddir"
    cp "$pkgbuild" "$builddir/PKGBUILD"
    if [[ -z "${SUDO_SKIP:-}" ]]; then
      log "  building and installing $name ..."
      if ! (env -u CONDA_PREFIX -u CONDA_DEFAULT_ENV -u CONDA_SHLVL -u CONDA_PYTHON_EXE PYO3_PYTHON=/usr/bin/python3 PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH cd "$builddir" && makepkg -Cfis --noconfirm --needed --clean); then
        log "  WARNING: build failed for $name (continuing)"
        failed_builds+=("$name")
      fi
    else
      log "  SUDO_SKIP: would build and install $name from $pkgbuild"
    fi
    rm -rf "$builddir"
  done
  # Update state with the locally-built names (one per line)
  printf '%s\n' "${built_names[@]}" | sort -u > "$BUILT_STATE"
  if ((${#failed_builds[@]})); then
    log "  failed builds: ${failed_builds[*]}"
  fi
else
  log "  no PKGBUILDs found in $INSTALL_DIR/builds"
  rm -f "$BUILT_STATE"
fi

# Step 4: Call extra.sh
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
