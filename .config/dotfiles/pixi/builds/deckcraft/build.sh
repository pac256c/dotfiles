#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$PREFIX/bin"

# Find all executable files (not dirs) and copy to bin, skipping helper scripts
find . -type f -executable 2>/dev/null | while read -r f; do
  base=$(basename "$f")
  # Skip macOS debug files and rattler-build helper scripts
  [[ "$f" =~ \.dSYM/ ]] && continue
  [[ "$base" == conda_build.sh || "$base" == build_env.sh || "$base" == build_env_setup.sh ]] && continue
  cp -f "$f" "$PREFIX/bin/$base"
done

# Also look in common subdirs
for d in bin usr/bin usr/local/bin; do
  if [[ -d "$d" ]]; then
    find "$d" -type f -executable 2>/dev/null | while read -r f; do
      base=$(basename "$f")
      [[ "$base" == conda_build.sh || "$base" == build_env.sh || "$base" == build_env_setup.sh ]] && continue
      cp -f "$f" "$PREFIX/bin/$base"
    done
  fi
done
