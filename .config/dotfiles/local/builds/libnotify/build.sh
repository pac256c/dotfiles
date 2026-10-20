#!/usr/bin/env bash
set -euo pipefail

# Skip man/API docs (need xsltproc, docbook, gi-docgen) and introspection
# (needs g-ir-scanner); we only want the shared library.
meson setup build --prefix="$PREFIX" --buildtype=release \
  -Dman=false -Dtests=false -Dgtk_doc=false -Ddocbook_docs=disabled -Dintrospection=disabled
ninja -C build
ninja -C build install
