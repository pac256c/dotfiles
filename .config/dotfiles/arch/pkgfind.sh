#!/usr/bin/env bash
# pkgfind.sh - regenerate arch/packages.txt from currently installed packages
set -euo pipefail

BUILD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGFILE="$BUILD_ROOT/packages.txt"
MANLIST="$BUILD_ROOT/manlist.txt"

log() { printf '%s\n' "$*"; }

log "=== Updating packages.txt from installed packages ==="

{
  printf '%s\n' "# Arch packages (official repos + AUR), one per line."
  printf '%s\n' "# Installed with \`yay -S --needed\` (yay handles both). Edit as needed."
  printf '%s\n' "# Lines starting with # are comments."
  printf '\n'
  {
    pacman -Qqen
    pacman -Qqem
  } 2>/dev/null | grep -v -- '-debug$' | sort -u | {
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
} > "$PKGFILE"

log "done: $PKGFILE"
