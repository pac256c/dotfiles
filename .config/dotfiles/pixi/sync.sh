#!/usr/bin/env bash
# sync.sh - install/sync everything locally via pixi (no sudo/root needed)
# (run manually, or from `dotfiles pull` once wired up)
#
# Prerequisites: curl or wget, tar. Run as normal user (not root).
# Steps:
# 1. Install pixi to ~/.local/opt/pixi if not present
# 2. Install packages from packages.txt (pixi global, from conda-forge)
# 3. Update local recipes from manlist.txt and build/install builds/
# 4. Call extra.sh for additional setup
#
# Everything lives under $PIXI_HOME (~/.local/opt/pixi):
#   bin/       pixi itself plus the executables exposed by `pixi global`
#   envs/      pixi's internal per-package environments (never activated)
#   prefix/    files from locally-built packages that have no executables
#              (fonts, tmux-plugin-manager)
# Put these two lines in your shell env (e.g. ~/.config/zsh/env) to use it:
#   export PIXI_HOME="$HOME/.local/opt/pixi"
#   export PATH="$PIXI_HOME/bin:$PATH"
# PIXI_HOME must be exported everywhere you run `pixi global`, otherwise pixi
# falls back to ~/.pixi.
#
# Prompts once before installing/updating; otherwise non-interactive.

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$DOTFILES_ROOT"

# Per-machine state (not part of the repo). Records which packages were built
# locally (and at which version) so a later run can skip unchanged ones and
# detect stale ones.
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/dotfiles"

log() { printf '%s\n' "$*"; }

log "=== Running the local install/update script (pixi-based) ==="

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

# Step 1: Install pixi (to ~/.local/opt/pixi) if not present. This fetches the
# same release binary pixi's own installer does, without piping a script to a
# shell and without touching shell rc files.
export PIXI_HOME="$HOME/.local/opt/pixi"
PIXI_BIN="$PIXI_HOME/bin/pixi"
export PATH="$PIXI_HOME/bin:$PATH"
if [[ ! -x $PIXI_BIN ]]; then
  log "=== Installing pixi ==="
  case "$(uname -m)" in
    x86_64) pixi_arch=x86_64 ;;
    aarch64|arm64) pixi_arch=aarch64 ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  pixi_url="https://github.com/prefix-dev/pixi/releases/latest/download/pixi-${pixi_arch}-unknown-linux-musl.tar.gz"
  mkdir -p "$PIXI_HOME/bin"
  pixi_tmp=$(mktemp -d)
  trap 'rm -rf "$pixi_tmp"' EXIT
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$pixi_url" -o "$pixi_tmp/pixi.tar.gz"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$pixi_url" -O "$pixi_tmp/pixi.tar.gz"
  else
    echo "need curl or wget to install pixi" >&2
    exit 1
  fi
  tar -xzf "$pixi_tmp/pixi.tar.gz" -C "$PIXI_HOME/bin" pixi
  chmod +x "$PIXI_BIN"
  rm -rf "$pixi_tmp"
  trap - EXIT
fi
log "  using $("$PIXI_BIN" --version) at $PIXI_BIN"

# pixi global install wrapper (conda-forge). Each package gets its own environment named
# after it; failures are reported but do not abort the whole run.
pg_install() { # pixi global install, with conda-forge as the channel
  "$PIXI_BIN" global install -c conda-forge "$@"
}

# Step 2: Install packages from packages.txt
if [[ -f "$INSTALL_DIR/packages.txt" ]]; then
  log "=== Installing pixi global packages from packages.txt ==="

  # Packages built locally by a previous run (recorded in the per-machine state
  # file) that are no longer in manlist.txt are stale; remove them before
  # installing replacements.
  BUILT_STATE="$STATE_DIR/pixi-built"
  if [[ -f "$BUILT_STATE" ]]; then
    stale=()
    while read -r bname _; do
      [[ -z "$bname" ]] && continue
      grep -qE "^[[:space:]]*${bname}([[:space:]]|\$)" "$INSTALL_DIR/manlist.txt" && continue
      [[ -d "$PIXI_HOME/envs/${bname,,}" ]] && stale+=("${bname,,}")
    done < "$BUILT_STATE"
    if ((${#stale[@]})); then
      log "  removing stale locally-built packages: ${stale[*]}"
      "$PIXI_BIN" global uninstall "${stale[@]}" || log "  WARNING: failed to remove some stale packages"
    fi
  fi

  # Everything in packages.txt (local recipes are built in Step 3). Plain
  # one-word lines go in one batch command; lines with spaces carry extra
  # `pixi global install` arguments (--with, --expose) and run on their own.
  # pixi isolates each install in its own environment under $PIXI_HOME/envs,
  # but they are all exposed through $PIXI_HOME/bin; nothing to activate.
  mapfile -t pkg_lines < <(grep -v '^#' "$INSTALL_DIR/packages.txt" | grep -v '^$')
  plain_pkgs=()
  special_lines=()
  for line in "${pkg_lines[@]}"; do
    if [[ $line == *" "* ]]; then special_lines+=("$line"); else plain_pkgs+=("$line"); fi
  done

  if [[ "$PER_PKG_INSTALL" == "true" ]]; then
    failed=()
    for line in "${plain_pkgs[@]}" "${special_lines[@]}"; do
      read -r -p "  Install $line? [y/N] " p_reply
      case "$p_reply" in
        [Yy]*) ;;
        *)
          log "  skipping $line"
          continue
          ;;
      esac
      read -ra pg_args <<<"$line"
      if ! pg_install "${pg_args[@]}"; then
        log "  WARNING: failed to install $line (continuing)"
        failed+=("$line")
      fi
    done
    if ((${#failed[@]})); then
      log "  failed packages: ${failed[*]}"
    fi
  else
    if ((${#plain_pkgs[@]})) && ! pg_install "${plain_pkgs[@]}"; then
      log "  WARNING: batch install failed; falling back to per-package install"
      failed=()
      for pkg in "${plain_pkgs[@]}"; do
        if ! pg_install "$pkg"; then
          log "  WARNING: failed to install $pkg (continuing)"
          failed+=("$pkg")
        fi
      done
      if ((${#failed[@]})); then
        log "  failed packages: ${failed[*]}"
      fi
    fi
    for line in "${special_lines[@]}"; do
      read -ra pg_args <<<"$line"
      pg_install "${pg_args[@]}" || log "  WARNING: failed to install $line (continuing)"
    done
  fi
else
  log "Warning: $INSTALL_DIR/packages.txt not found, skipping pixi packages"
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

log "=== Building and installing local recipes from builds/ ==="
# rattler-build (installed from packages.txt) builds each recipe into a local
# channel directory; pixi then installs from that channel + conda-forge.
# Packages with executables get their own `pixi global` environment. Packages
# without any (fonts, tmux-plugin-manager) can't be exposed through pixi, so
# their files are unpacked into $PIXI_HOME/prefix instead.
CHANNEL_DIR="$STATE_DIR/pixi-channel"
SHARE_PREFIX="$PIXI_HOME/prefix"
BUILT_STATE="$STATE_DIR/pixi-built"
mkdir -p "$STATE_DIR" "$CHANNEL_DIR" "$SHARE_PREFIX"

shopt -s nullglob
recipes=("$INSTALL_DIR"/builds/*/recipe.yaml)
shopt -u nullglob

if ((${#recipes[@]})) && ! command -v rattler-build >/dev/null 2>&1; then
  log "  WARNING: rattler-build not found (is it in packages.txt and did it install?); skipping local builds"
  recipes=()
fi

if ((${#recipes[@]})); then
  built_lines=()
  for recipe in "${recipes[@]}"; do
    pkgdir=$(dirname "$recipe")
    pkgname=$(basename "$pkgdir")
    pkgname_lc=${pkgname,,}
    recipe_ver=$(sed -n 's/^  version: "\(.*\)"$/\1/p' "$recipe" | head -n1)
    recipe_num=$(sed -n 's/^  number: \([0-9]*\)$/\1/p' "$recipe" | head -n1)
    key="${recipe_ver}-${recipe_num:-0}"

    # Previously recorded "<name> <version>-<build number>" for this package
    prev_key=$(awk -v p="$pkgname" '$1==p {print $2}' "$BUILT_STATE" 2>/dev/null || true)
    if [[ -n $recipe_ver && $key == "$prev_key" ]]; then
      log "  $pkgname $recipe_ver already installed, skipping build"
      built_lines+=("$pkgname $key")
      continue
    fi

    log "  building $pkgname${recipe_ver:+ ($recipe_ver)}"
    if rattler-build build --recipe "$recipe" --output-dir "$CHANNEL_DIR" \
         --channel conda-forge --package-format tar-bz2 \
         >"/tmp/rattler-build-$pkgname.log" 2>&1; then
      # rattler-build leaves its work dirs behind under <output-dir>/bld
      rm -rf "$CHANNEL_DIR"/bld/rattler-build_"${pkgname_lc}"_* 2>/dev/null || true
      bpath=$(find "$CHANNEL_DIR" -name "${pkgname_lc}-${recipe_ver}-*.tar.bz2" -not -path '*/bld/*' \
                -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
      if [[ -z $bpath ]]; then
        log "  WARNING: could not find built package for $pkgname"
        continue
      fi
      installed=false
      # (list into a variable first: `tar | grep -q` would trip pipefail via SIGPIPE)
      pkg_files=$(tar -tjf "$bpath")
      if grep -q '^bin/' <<<"$pkg_files"; then
        log "  installing $(basename "$bpath") with pixi global"
        # local channel first so it wins over a same-named conda-forge package
        if "$PIXI_BIN" global install -c "file://$CHANNEL_DIR" -c conda-forge \
             --force-reinstall "$pkgname_lc"; then
          installed=true
        else
          log "  WARNING: failed to install $pkgname"
        fi
      else
        log "  unpacking $(basename "$bpath") into $SHARE_PREFIX (no executables)"
        if tar -xjf "$bpath" -C "$SHARE_PREFIX" --wildcards --anchored \
             --exclude='info' --exclude='info/*'; then
          installed=true
        else
          log "  WARNING: failed to unpack $pkgname"
        fi
      fi
      if $installed; then
        built_lines+=("$pkgname $key")
      fi
    else
      log "  WARNING: failed to build $pkgname (see /tmp/rattler-build-$pkgname.log)"
    fi
  done
  # Update state with the locally-built names and versions (one per line)
  printf '%s\n' "${built_lines[@]}" | sort -u > "$BUILT_STATE"
else
  log "  no local recipes found in $INSTALL_DIR/builds"
  rm -f "$BUILT_STATE"
fi

# Pick up newer versions of everything installed from conda-forge
log "=== Updating all pixi global environments ==="
"$PIXI_BIN" global update || log "  WARNING: pixi global update reported errors"

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
log "Make sure your shell exports PIXI_HOME=$PIXI_HOME and has $PIXI_HOME/bin on PATH."
