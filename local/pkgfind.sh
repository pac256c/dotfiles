#!/usr/bin/env bash
# pkgfind.sh - regenerate local/packages.txt from conda base env
set -euo pipefail

BUILD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGFILE="$BUILD_ROOT/packages.txt"
MANLIST="$BUILD_ROOT/manlist.txt"
CONDA="${CONDA:-$HOME/.local/opt/miniforge3/bin/conda}"

log() { printf '%s\n' "$*"; }

log "=== Updating local/packages.txt from conda base env ==="

{
  printf '%s\n' "# Conda packages for local installs (no sudo/root needed)"
  printf '%s\n' "# Installed from conda-forge into the base env via sync.sh."
  printf '%s\n' "# Edit as needed."
  printf '%s\n' "#"
  printf '%s\n' "# Format: one package per line. Lines starting with # are comments."
  printf '%s\n' "# Packages also built locally from manlist.txt are skipped here."
  printf '\n'
  if command -v "$CONDA" >/dev/null 2>&1 || [[ -x "$CONDA" ]]; then
    "$CONDA" env export -n base --from-history 2>/dev/null \
      | awk '
          /^dependencies:/ { deps=1; next }
          /^[A-Za-z_]+:/   { deps=0 }
          deps && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print }
        ' \
      | sed -E 's/^([A-Za-z0-9_.-]+).*/\1/' \
      | grep -vE '^(conda|mamba|pip|python)$' \
      | sort -u \
      | {
          if [[ -f "$MANLIST" ]]; then
            local_man=()
            while IFS=$' \t' read -r mname _ || [[ -n ${mname:-} ]]; do
              [[ -z ${mname:-} || $mname == \#* ]] && continue
              local_man+=("$mname")
            done < "$MANLIST"
            if ((${#local_man[@]})); then
              grep -vxFf <(printf '%s\n' "${local_man[@]}")
            else
              cat
            fi
          else
            cat
          fi
        }
  else
    :
  fi
} > "$PKGFILE"

log "done: $PKGFILE"
