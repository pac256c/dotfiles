#!/usr/bin/env bash
set -euo pipefail

# The source tarball keeps git's file modes, so scripts stay executable.
mkdir -p "$PREFIX/share/tmux-plugin-manager"
cp -a ./ "$PREFIX/share/tmux-plugin-manager/"
