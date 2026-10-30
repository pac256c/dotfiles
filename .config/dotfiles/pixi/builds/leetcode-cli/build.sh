#!/usr/bin/env bash
set -euo pipefail

# Keep npm's cache/tmp on the XDG path. The rattler-build sandbox does not
# inherit .zshenv's NPM_CONFIG_* vars, so npm would otherwise fall back to ~/.npm.
# npm reads the uppercase form; tools like prebuild-install (keytar) read the
# lowercase form, so set both. Native deps may build with cargo; keep it on a
# user-writable path (the build does not inherit .zshenv's CARGO_HOME).
export NPM_CONFIG_CACHE="$HOME/.cache/npm"
export npm_config_cache="$HOME/.cache/npm"
export CARGO_HOME="$HOME/.local/opt/cargo"

# Remove the root package's prepare script (e.g. husky) so npm pack/install don't run it
node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync("package.json","utf8")); if(p.scripts){delete p.scripts.prepare; delete p.scripts.prepublish; delete p.scripts.prepublishOnly;} fs.writeFileSync("package.json", JSON.stringify(p, null, 2));'

# Pack into a real tarball, then install it (avoids symlinks into the work dir)
npm pack --no-fund --no-audit
export npm_config_allow_scripts=keytar
npm install -g --prefix="$PREFIX" --no-fund --no-audit ./*.tgz
