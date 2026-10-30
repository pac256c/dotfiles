#!/usr/bin/env bash
set -euo pipefail

# The release tarball is a self-contained prebuilt tree (extracted directly
# into the work dir) whose launcher resolves its own location, so install it
# under share/ and expose the launcher via a symlink in bin/. The symlink is
# relative: pixi installs the package into a different prefix than the one it
# was built in, so an absolute $PREFIX target would dangle.
mkdir -p "$PREFIX/share/zen-browser"
cp -a . "$PREFIX/share/zen-browser/"
rm -f "$PREFIX/share/zen-browser/conda_build.sh" \
      "$PREFIX/share/zen-browser/build_env.sh" \
      "$PREFIX/share/zen-browser/build_env_setup.sh"

mkdir -p "$PREFIX/bin"
ln -sf ../share/zen-browser/zen "$PREFIX/bin/zen"
