#!/usr/bin/env bash
set -euo pipefail

# The release tarball is a self-contained prebuilt tree (extracted directly
# into the work dir) whose launcher resolves its own location, so install it
# under share/ and expose the launcher via a symlink in bin/. The symlink is
# relative: pixi installs the package into a different prefix than the one it
# was built in, so an absolute $PREFIX target would dangle.
# rattler-build (0.79) does not extract .tar.xz sources, so do it here.
for arc in zen.linux-x86_64.tar.xz zen.linux-x86_64.txz; do
  if [ -f "$arc" ] && [ ! -d zen ]; then
    tar -xJf "$arc"
  fi
done

mkdir -p "$PREFIX/share/zen-browser"
cp -a zen/. "$PREFIX/share/zen-browser/"
rm -f "$PREFIX/share/zen-browser/conda_build.sh" \
      "$PREFIX/share/zen-browser/build_env.sh" \
      "$PREFIX/share/zen-browser/build_env_setup.sh"

mkdir -p "$PREFIX/bin"
cat > "$PREFIX/bin/zen" <<'ZEOF'
#!/bin/sh
# Wrapper: pixi's shim does not propagate the env's lib dir onto
# LD_LIBRARY_PATH, and Zen's libxul needs libasound.so.2 from it.
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$here/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/../share/zen-browser/zen" "$@"
ZEOF
chmod +x "$PREFIX/bin/zen"
