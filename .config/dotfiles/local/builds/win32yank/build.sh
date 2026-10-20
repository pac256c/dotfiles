#!/usr/bin/env bash
set -euo pipefail

# The .exe ships in the zip without the exec bit, so copy it explicitly
# instead of relying on `find -executable` (which would find nothing).
mkdir -p "$PREFIX/bin"
cp -f win32yank.exe "$PREFIX/bin/win32yank.exe"
chmod +x "$PREFIX/bin/win32yank.exe"
