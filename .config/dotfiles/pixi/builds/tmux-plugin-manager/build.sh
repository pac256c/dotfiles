#!/usr/bin/env bash
set -euo pipefail

# The source tarball keeps git's file modes, so scripts stay executable.
mkdir -p "$PREFIX/share/tmux-plugin-manager"
cp -a ./ "$PREFIX/share/tmux-plugin-manager/"
rm -f "$PREFIX/share/tmux-plugin-manager/conda_build.sh" \
      "$PREFIX/share/tmux-plugin-manager/build_env.sh" \
      "$PREFIX/share/tmux-plugin-manager/build_env_setup.sh"
