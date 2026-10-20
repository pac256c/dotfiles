#!/usr/bin/env bash
set -euo pipefail

# docs=disabled: man pages need xsltproc/docbook; we only want the binaries.
# The iconv symbols live in libiconv.so (conda's libintl does not provide
# them), and the meson build only links intl, so add it explicitly.
export LDFLAGS="${LDFLAGS:-} -liconv"

meson setup build --prefix="$PREFIX" --buildtype=release -Ddocs=false
ninja -C build
ninja -C build install
