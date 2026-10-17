#!/usr/bin/env bash
# extra.sh - additional setup steps (links, directories, etc.)
# Customize this as needed. This is called by arch_sync.sh step 5.

set -euo pipefail

log() { printf '%s\n' "$*"; }

log "extra.sh: running additional setup..."

# Example: create common directories
mkdir -p "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.cache"

# Example: create symlinks (uncomment and customize)
# ln -sf "$HOME/.config/someconfig" "$HOME/.someconfig" 2>/dev/null || true

log "extra.sh: done."
