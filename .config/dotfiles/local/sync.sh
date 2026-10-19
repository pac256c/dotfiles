#!/usr/bin/env bash
# sync.sh - install/sync everything locally via conda (no sudo/root needed)
# (run automatically by `dotfiles pull`, or manually)
#
# Prerequisites: git exists. Run as normal user (not root).
# Steps:
# 1. Install Miniforge3 (conda) to ~/.local/opt/miniforge3 if not present
# 2. Install conda packages from packages.txt (via conda-forge)
# 3. Update local recipes from manlist.txt and build/install builds/
# 4. Call extra.sh for additional setup
#
# Prompts once before installing/updating; otherwise non-interactive.

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$DOTFILES_ROOT"

log() { printf '%s\n' "$*"; }

log "=== Running the local install/update script (conda-based) ==="

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

# Use the XDG condarc so config lives under ~/.config/conda
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export CONDARC="$XDG_CONFIG_HOME/conda/condarc"

# Step 1: Install Miniforge3 (conda) if not present (to ~/.local/opt/miniforge3)
MINIFORGE_DIR="$HOME/.local/opt/miniforge3"
CONDA_PREFIX="$MINIFORGE_DIR"
if ! command -v conda >/dev/null 2>&1 && [[ ! -f "$MINIFORGE_DIR/bin/conda" ]]; then
  log "=== Installing Miniforge3 ==="
  mkdir -p "$(dirname "$MINIFORGE_DIR")"
  if command -v curl >/dev/null 2>&1; then
    curl -L "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh" -o /tmp/miniforge.sh
  elif command -v wget >/dev/null 2>&1; then
    wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh" -o /tmp/miniforge.sh
  else
    echo "need curl or wget to install miniforge" >&2
    exit 1
  fi
  bash /tmp/miniforge.sh -b -p "$MINIFORGE_DIR"
  rm -f /tmp/miniforge.sh
fi
# Initialize conda for this shell (prefer the installed miniforge, fall back to an existing conda)
CONDA_BASE=""
for candidate in "$MINIFORGE_DIR" "$(conda info --base 2>/dev/null)"; do
  if [[ -n $candidate && -f "$candidate/etc/profile.d/conda.sh" ]]; then
    CONDA_BASE="$candidate"
    break
  fi
done
if [[ -n $CONDA_BASE ]]; then
  # shellcheck disable=SC1091
  . "$CONDA_BASE/etc/profile.d/conda.sh"
  export CONDA_PREFIX="$CONDA_BASE"
fi
conda activate base >/dev/null 2>&1 || true

# Step 2: Install conda packages from packages.txt
# Prefer mamba if available for faster solves
CONDA_BIN="conda"
if command -v mamba >/dev/null 2>&1; then
  CONDA_BIN="mamba"
fi

# Ensure conda-build is available
if ! command -v conda-build >/dev/null 2>&1 && [[ ! -f "$CONDA_PREFIX/bin/conda-build" ]]; then
  log "=== Installing conda-build ==="
  $CONDA_BIN install -y -c conda-forge conda-build
fi

if [[ -f "$INSTALL_DIR/packages.txt" ]]; then
  log "=== Installing conda packages from packages.txt ==="

  # Packages built locally by a previous run (recorded in builds/.built) that are
  # no longer in manlist.txt are stale; remove them before installing replacements.
  BUILT_STATE="$INSTALL_DIR/builds/.built"
  if [[ -f "$BUILT_STATE" ]]; then
    stale=()
    while IFS= read -r bname; do
      [[ -z "$bname" ]] && continue
      grep -qE "^[[:space:]]*${bname}([[:space:]]|\$)" "$INSTALL_DIR/manlist.txt" && continue
      $CONDA_BIN list "${bname,,}" 2>/dev/null | awk -v p="${bname,,}" '$1==p{found=1} END{exit !found}' && stale+=("$bname")
    done < "$BUILT_STATE"
    if ((${#stale[@]})); then
      log "  removing stale locally-built packages: ${stale[*]}"
      $CONDA_BIN remove -y "${stale[@]}" || log "  WARNING: failed to remove some stale packages"
    fi
  fi

  # Everything in packages.txt (local recipes are built in Step 3)
  failed=()
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if ! $CONDA_BIN install -y -c conda-forge "$pkg"; then
      log "  WARNING: failed to install $pkg (continuing)"
      failed+=("$pkg")
    fi
  done < <(grep -v '^#' "$INSTALL_DIR/packages.txt" | grep -v '^$')
  if ((${#failed[@]})); then
    log "  failed packages: ${failed[*]}"
  fi
else
  log "Warning: $INSTALL_DIR/packages.txt not found, skipping conda packages"
fi

# Step 3: Update local recipes from manlist.txt and build/install builds/
if [[ -x "$INSTALL_DIR/manfind.sh" ]]; then
  log "=== Updating local builds from manlist.txt ==="
  manfind_rc=0
  "$INSTALL_DIR/manfind.sh" || manfind_rc=$?
  if ((manfind_rc != 0)); then
    log "  WARNING: manfind.sh finished with errors (exit $manfind_rc); continuing"
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
      log "  hint: if the errors are GitHub 403/rate-limit, export GITHUB_TOKEN to raise the API rate limit"
    fi
  fi
fi

log "=== Building and installing local conda recipes from builds/ ==="
shopt -s nullglob
recipes=("$INSTALL_DIR"/builds/*/meta.yaml)
shopt -u nullglob
# Record which packages are built locally so future runs can detect stale ones.
BUILT_STATE="$INSTALL_DIR/builds/.built"
if ((${#recipes[@]})); then
  built_names=()
  for recipe in "${recipes[@]}"; do
    pkgdir=$(dirname "$recipe")
    pkgname=$(basename "$pkgdir")
    built_names+=("$pkgname")
    recipe_ver=$(sed -n 's/^{% set version = "\(.*\)" %}$/\1/p' "$recipe" | head -n1)
    installed_ver=$($CONDA_BIN list "${pkgname,,}" 2>/dev/null | awk -v p="${pkgname,,}" '$1==p {print $2}')
    if [[ -n $recipe_ver && $recipe_ver == "$installed_ver" ]]; then
      log "  $pkgname $recipe_ver already installed, skipping build"
      continue
    fi
    log "  building $pkgname${recipe_ver:+ ($recipe_ver)}"
    if conda-build --output-folder /tmp/conda-build "$pkgdir" >/tmp/conda-build-$pkgname.log 2>&1; then
      # Find the built package (conda-build outputs .conda or .tar.bz2)
      bpath=$(find /tmp/conda-build -name "${pkgname,,}*.conda" -not -path '*/work/*' 2>/dev/null | head -n1)
      if [[ -z $bpath ]]; then
        bpath=$(find /tmp/conda-build -name "${pkgname,,}*.tar.bz2" -not -path '*/work/*' 2>/dev/null | head -n1)
      fi
      if [[ -z $bpath ]]; then
        bpath=$(find /tmp/conda-build -name "*.conda" 2>/dev/null | head -n1)
      fi
      if [[ -z $bpath ]]; then
        bpath=$(find /tmp/conda-build -name "*.tar.bz2" 2>/dev/null | head -n1)
      fi
      if [[ -n $bpath ]]; then
        log "  installing $(basename "$bpath")"
        $CONDA_BIN install -y "$bpath" || log "  WARNING: failed to install $pkgname"
      else
        log "  WARNING: could not find built package for $pkgname"
      fi
    else
      log "  WARNING: failed to build $pkgname (see /tmp/conda-build-$pkgname.log)"
    fi
  done
  # Update state with the locally-built names (one per line)
  printf '%s\n' "${built_names[@]}" | sort -u > "$BUILT_STATE"
else
  log "  no local conda recipes found in $INSTALL_DIR/builds"
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
