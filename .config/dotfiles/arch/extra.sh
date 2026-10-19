#!/usr/bin/env bash
# extra.sh - additional setup steps (links, directories, etc.)
# Customize this as needed. This is called by sync.sh step 5.

set -euo pipefail

log() { printf '%s\n' "$*"; }

log "extra.sh: running additional setup..."


xdg-user-dirs-update
# Only change shell if it is not already zsh (avoids a password prompt when unnecessary)
current_shell="$(getent passwd "$USER" | cut -d: -f7 2>/dev/null || true)"
if [[ -n "$current_shell" && "$(basename "$current_shell")" != "zsh" ]]; then
  if [[ -t 0 ]]; then
    chsh -s "$(which zsh)" || log "  WARNING: chsh failed"
  else
    log "  skipping chsh (non-interactive)"
  fi
fi
fc-cache -fv ~/.local/share/fonts
if [[ -z "${SUDO_SKIP:-}" ]]; then
  sudo systemctl enable --now sshd
else
  log "  SUDO_SKIP: would enable sshd"
fi
mkdir -p ~/.local/share/gnupg
chmod 700 ~/.local/share/gnupg
if [ -d ~/.gnupg ]; then cp -r ~/.gnupg/. ~/.local/share/gnupg/ && rm -rf ~/.gnupg; fi


log "extra.sh: done."
