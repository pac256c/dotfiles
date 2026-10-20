#!/usr/bin/env bash
# extra.sh - additional setup steps (links, directories, etc.)
# Customize this as needed. This is called by sync.sh step 5.

set -euo pipefail

log() { printf '%s\n' "$*"; }

log "extra.sh: running additional setup..."

for dir in desktop documents downloads games music pictures public templates videos; do
  if [ ! -d "$HOME/$dir" ]; then
    mkdir -p "$HOME/$dir"
    log "  created ~/$dir"
  fi
done

xdg-user-dirs-update

# Make every zsh load the shared env (~/.config/zsh/env). /etc/zshenv is
# read by ALL zsh shells (login or not) before ~/.zshenv, which also covers
# nested shells that inherit ZDOTDIR and would otherwise skip ~/.zshenv.
if [[ -z "${SUDO_SKIP:-}" ]]; then
  if ! sudo grep -qF '.config/zsh/env' /etc/zsh/zshenv 2>/dev/null; then
    printf '[ -f "$HOME/.config/zsh/env" ] && . "$HOME/.config/zsh/env"\n' | sudo tee -a /etc/zsh/zshenv >/dev/null
    log "  added env source line to /etc/zsh/zshenv"
  fi
  if ! sudo grep -qF '.config/zsh/env' /etc/zsh/zprofile 2>/dev/null; then
    printf '[ -f "$HOME/.config/zsh/env" ] && . "$HOME/.config/zsh/env"\n' | sudo tee -a /etc/zsh/zprofile >/dev/null
    log "  added env source line to /etc/zsh/zprofile"
  fi
else
  log "  SUDO_SKIP: would add env source line to /etc/zsh/zshenv and zprofile"
fi

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
