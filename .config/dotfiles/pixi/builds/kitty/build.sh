#!/usr/bin/env bash
set -euo pipefail

# The bundle is self-contained and resolves its own location, so copy the
# whole tree (bin/kitty, bin/kitten, lib/kitty, share/...) into the prefix.
mkdir -p "$PREFIX"
cp -a bin lib share "$PREFIX/"
rm -f "$PREFIX/bin/conda_build.sh" "$PREFIX/bin/build_env.sh"
