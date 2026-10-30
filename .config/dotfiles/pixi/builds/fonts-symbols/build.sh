#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$PREFIX/share/fonts/Symbols"
# Copy only the font files (skip LICENSE/readme/etc)
find . -type f \( -iname '*.ttf' -o -iname '*.otf' \) -exec cp -f {} "$PREFIX/share/fonts/Symbols/" \;
