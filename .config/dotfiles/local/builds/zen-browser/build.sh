#!/usr/bin/env bash
set -euo pipefail

# The release tarball is a self-contained prebuilt tree (extracted directly
# into the work dir) whose launcher resolves its own location, so install it
# under share/ and expose the launcher via a symlink in bin/.
mkdir -p "$PREFIX/share/zen-browser"
cp -a . "$PREFIX/share/zen-browser/"
rm -f "$PREFIX/share/zen-browser/conda_build.sh" \
      "$PREFIX/share/zen-browser/build_env_setup.sh"

mkdir -p "$PREFIX/bin"
ln -sf "$PREFIX/share/zen-browser/zen" "$PREFIX/bin/zen"
