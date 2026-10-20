#!/usr/bin/env bash
# Query upstream sources for the apps/fonts in manlist.txt and (re)generate
# their conda recipe files in builds/<name>/meta.yaml and builds/<name>/build.sh
# (existing recipes are overwritten). Handles release tarballs, go builds,
# npm packages, and Nerd Fonts.
#
# manlist.txt format, one app per line:
#   <name> <github-owner/repo> [overrides]
#
# Overrides (semicolon-separated, no spaces):
#   type=release|go|npm|font|source  where the version/source comes from (default: release)
#   depends=a,b,c              extra runtime dependencies for the recipe
#   asset=<filename>           (release/font) exact asset to use
#   dir=<subdir>               (font) subdirectory under share/fonts to install into
#   npm=<package>              (npm) npm package name (default: <name>)
#   scripts=a,b                (npm) packages whose install scripts are allowed
#   license=<SPDX>             license id override (go/npm/source only)
#
# source type: installs the whole tag tarball tree into share/<name>/ (for
# script collections without a release asset, e.g. tmux plugin manager).
#
# Usage:
#   ./manfind.sh                 # process every app in manlist.txt
#   ./manfind.sh photocraft ...  # process only the named apps
#
# GITHUB_TOKEN is honored if set (raises the GitHub API rate limit).

set -uo pipefail

BUILD_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RECIPE_DIR="$BUILD_ROOT/builds"
APPS_CONF="$BUILD_ROOT/manlist.txt"
ARCH_ASSET="linux-x86_64"
GITHUB_API="https://api.github.com"
NPM_REGISTRY="https://registry.npmjs.org"

SELECTED=()

while (($#)); do
  case $1 in
  -h|--help)
    sed -n '1,26p' "$0"
    exit 0
    ;;
  -*)
    echo "unknown option: $1" >&2
    exit 1
    ;;
  *)
    SELECTED+=("$1")
    ;;
  esac
  shift
done

for tool in curl jq sha256sum sort; do
  command -v "$tool" >/dev/null || { echo "missing dependency: $tool" >&2; exit 1; }
done
[[ -f $APPS_CONF ]] || { echo "no manlist.txt at $APPS_CONF" >&2; exit 1; }
mkdir -p "$RECIPE_DIR"

log() { printf '%s\n' "$*"; }

gh() { # GET a GitHub API url
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    curl --compressed -fsSL \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" "$@"
  else
    curl --compressed -fsSL "$@"
  fi
}

strip_version() { # $1=tag $2=pkgname -> plain version
  local v=$1
  v=${v#"$2"-}
  v=${v#[vV]}
  printf '%s' "$v"
}

clean_desc() { # strip chars that would break a recipe string, collapse newlines
  local d=$1
  d=${d//\"/}
  d=${d//\`/}
  d=${d//\$/}
  d=${d//$'\n'/ }
  printf '%s' "$d"
}

desc_for() { # $1=repo -> repo description (best effort)
  local d=""
  d=$(gh "$GITHUB_API/repos/$1" 2>/dev/null | jq -r '.description // empty' 2>/dev/null) || d=""
  printf '%s' "$d"
}

license_for() { # $1=repo -> SPDX id from the GitHub license endpoint (best effort)
  local spdx=""
  spdx=$(gh "$GITHUB_API/repos/$1/license" 2>/dev/null | jq -r '.license.spdx_id // empty' 2>/dev/null) || spdx=""
  printf '%s' "$spdx"
}

# ---------------------------------------------------------------- generators ---

write_release_recipe() { # $1=name $2=repo $3=ver $4=tag $5=asset $6=url $7=sha $8=desc $9=depends_csv
  local name=$1 repo=$2 ver=$3 tag=$4 asset=$5 url=$6 sha=$7 desc=$8 depends_csv=$9

  # Emit a runtime requirements block only when the caller supplied depends.
  local req_block=""
  if [[ -n $depends_csv ]]; then
    req_block=$'\n\nrequirements:\n  run:\n'
    local dep
    IFS=',' read -ra __deps <<<"$depends_csv"
    for dep in "${__deps[@]}"; do
      [[ -n $dep ]] && req_block+="    - $dep"$'\n'
    done
  fi

  mkdir -p "$RECIPE_DIR/$name"
  cat >"$RECIPE_DIR/$name/meta.yaml" <<PKEOF
{% set name = "$name" %}
{% set version = "$ver" %}

package:
  name: {{ name|lower }}
  version: {{ version }}

source:
  url: $url
  sha256: $sha

build:
  number: 2
  binary_relocation: false
  detect_binary_files_with_prefix: false
$req_block
about:
  home: https://github.com/$repo
  license: Apache-2.0
  summary: "$desc"
PKEOF

  # Create build.sh for binary releases
  cat >"$RECIPE_DIR/$name/build.sh" <<'BSHEOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$PREFIX/bin"

# Find all executable files (not dirs) and copy to bin, skipping helper scripts
find . -type f -executable 2>/dev/null | while read -r f; do
  base=$(basename "$f")
  # Skip macOS debug files and conda-build helper scripts
  [[ "$f" =~ \.dSYM/ ]] && continue
  [[ "$base" == conda_build.sh ]] && continue
  cp -f "$f" "$PREFIX/bin/$base"
done

# Also look in common subdirs
for d in bin usr/bin usr/local/bin; do
  if [[ -d "$d" ]]; then
    find "$d" -type f -executable 2>/dev/null | while read -r f; do
      base=$(basename "$f")
      [[ "$base" == conda_build.sh ]] && continue
      cp -f "$f" "$PREFIX/bin/$base"
    done
  fi
done
BSHEOF
  chmod +x "$RECIPE_DIR/$name/build.sh"
}

write_go_recipe() { # $1=name $2=repo $3=ver $4=tag $5=desc $6=license $7=depends_csv $8=sha
  local name=$1 repo=$2 ver=$3 tag=$4 desc=$5 license=$6 depends_csv=$7 sha=$8

  mkdir -p "$RECIPE_DIR/$name"
  cat >"$RECIPE_DIR/$name/meta.yaml" <<PKEOF
{% set name = "$name" %}
{% set version = "$ver" %}

package:
  name: {{ name|lower }}
  version: {{ version }}

source:
  url: https://github.com/$repo/archive/refs/tags/$tag.tar.gz
  sha256: $sha

build:
  number: 1
  script:
    - export CGO_ENABLED=0
    - export GOPATH=\$HOME/.local/opt/go
    - mkdir -p \$HOME/.local/opt/go
    - mkdir -p \$PREFIX/bin
    - go build -trimpath -ldflags "-s -w" -o \$PREFIX/bin/{{ name }} .

requirements:
  build:
    - go

about:
  home: https://github.com/$repo
  license: $license
  summary: "$desc"
PKEOF
}

# Install a tag tarball's tree as-is under share/<name>/ (for repos that are
# runnable scripts rather than binaries, e.g. tmux plugin manager).
write_source_recipe() { # $1=name $2=repo $3=ver $4=tag $5=url $6=sha $7=desc $8=license $9=depends_csv
  local name=$1 repo=$2 ver=$3 tag=$4 url=$5 sha=$6 desc=$7 license=$8 depends_csv=$9

  local req_block=""
  if [[ -n $depends_csv ]]; then
    req_block=$'\n\nrequirements:\n  run:\n'
    local dep
    IFS=',' read -ra __deps <<<"$depends_csv"
    for dep in "${__deps[@]}"; do
      [[ -n $dep ]] && req_block+="    - $dep"$'\n'
    done
  fi

  mkdir -p "$RECIPE_DIR/$name"
  cat >"$RECIPE_DIR/$name/meta.yaml" <<PKEOF
{% set name = "$name" %}
{% set version = "$ver" %}

package:
  name: {{ name|lower }}
  version: {{ version }}

source:
  url: $url
  sha256: $sha

build:
  number: 1
  binary_relocation: false
  detect_binary_files_with_prefix: false
$req_block
about:
  home: https://github.com/$repo
  license: $license
  summary: "$desc"
PKEOF

  cat >"$RECIPE_DIR/$name/build.sh" <<BSHEOF
#!/usr/bin/env bash
set -euo pipefail

# The source tarball keeps git's file modes, so scripts stay executable.
mkdir -p "\$PREFIX/share/$name"
cp -a ./ "\$PREFIX/share/$name/"
BSHEOF
  chmod +x "$RECIPE_DIR/$name/build.sh"
}

write_npm_recipe() { # $1=name $2=repo $3=ver $4=tarball $5=sha $6=desc $7=license $8=scripts_csv $9=depends_csv
  local name=$1 repo=$2 ver=$3 tarball=$4 sha=$5 desc=$6 license=$7 scripts_csv=$8 depends_csv=$9
  # Only allow-list install scripts when the caller asks (native deps like keytar).
  local npm_env=""
  [[ -n $scripts_csv ]] && npm_env="export npm_config_allow_scripts=$scripts_csv"

  mkdir -p "$RECIPE_DIR/$name"
  cat >"$RECIPE_DIR/$name/meta.yaml" <<PKEOF
{% set name = "$name" %}
{% set version = "$ver" %}

package:
  name: {{ name|lower }}
  version: {{ version }}

source:
  url: $tarball
  sha256: $sha

build:
  number: 1

requirements:
  build:
    - nodejs
  run:
    - nodejs

about:
  home: https://github.com/$repo
  license: $license
  summary: "$desc"
PKEOF

  cat >"$RECIPE_DIR/$name/build.sh" <<BSHEOF
#!/usr/bin/env bash
set -euo pipefail

# Keep npm's cache/tmp on the XDG path. The conda-build sandbox does not
# inherit .zshenv's NPM_CONFIG_* vars, so npm would otherwise fall back to ~/.npm.
# npm reads the uppercase form; tools like prebuild-install (keytar) read the
# lowercase form, so set both. Native deps may build with cargo; keep it on a
# user-writable path (conda-build does not inherit .zshenv's CARGO_HOME).
export NPM_CONFIG_CACHE="\$HOME/.cache/npm"
export npm_config_cache="\$HOME/.cache/npm"
export CARGO_HOME="\$HOME/.local/opt/cargo"

# Remove the root package's prepare script (e.g. husky) so npm pack/install don't run it
node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync("package.json","utf8")); if(p.scripts){delete p.scripts.prepare; delete p.scripts.prepublish; delete p.scripts.prepublishOnly;} fs.writeFileSync("package.json", JSON.stringify(p, null, 2));'

# Pack into a real tarball, then install it (avoids symlinks into the work dir)
npm pack --no-fund --no-audit
$npm_env
npm install -g --prefix="\$PREFIX" --no-fund --no-audit ./*.tgz
BSHEOF
  chmod +x "$RECIPE_DIR/$name/build.sh"
}

write_font_recipe() { # $1=name $2=repo $3=ver $4=tag $5=asset $6=url $7=sha $8=desc $9=fontdir
  local name=$1 repo=$2 ver=$3 tag=$4 asset=$5 url=$6 sha=$7 desc=$8 fontdir=$9
  [[ -n $fontdir ]] || fontdir=$name

  mkdir -p "$RECIPE_DIR/$name"
  cat >"$RECIPE_DIR/$name/meta.yaml" <<PKEOF
{% set name = "$name" %}
{% set version = "$ver" %}

package:
  name: {{ name|lower }}
  version: {{ version }}

source:
  url: $url
  sha256: $sha

build:
  number: 1

about:
  home: https://github.com/$repo
  license: MIT
  summary: "$desc"
PKEOF

  cat >"$RECIPE_DIR/$name/build.sh" <<BSHEOF
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "\$PREFIX/share/fonts/$fontdir"
# Copy only the font files (skip LICENSE/readme/etc)
find . -type f \\( -iname '*.ttf' -o -iname '*.otf' \\) -exec cp -f {} "\$PREFIX/share/fonts/$fontdir/" \\;
BSHEOF
  chmod +x "$RECIPE_DIR/$name/build.sh"
}

# ------------------------------------------------------------------ updaters ---

declare -a R_OK R_SKIP R_FAIL
FAILED=0

process_release() { # $1=name $2=repo $3=asset_ov $4=depends_csv
  local name=$1 repo=$2 asset_ov=$3 depends_csv=$4
  local builddir="$RECIPE_DIR/.build-$name"

  local rel tag
  if ! rel=$(gh "$GITHUB_API/repos/$repo/releases/latest"); then
    log "  ERROR: could not fetch latest release (no releases, rate limited, or repo missing)"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  tag=$(jq -r '.tag_name // empty' <<<"$rel")
  if [[ -z $tag ]]; then
    log "  ERROR: latest release has no tag"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  local ver
  ver=$(strip_version "$tag" "$name")
  log "  latest: $tag (version $ver)"

  local asset sha url
  if [[ -n $asset_ov ]]; then
    asset=$asset_ov
    url=$(jq -r --arg a "$asset" '.assets[] | select(.name == $a) | .browser_download_url // empty' <<<"$rel" | head -n1)
  else
    url=$(jq -r --arg p "${name}-${ver}-${ARCH_ASSET}.tar.gz" \
      '.assets[] | select(.name == $p) | .browser_download_url' <<<"$rel" | head -n1)
    if [[ -z $url ]]; then # fall back to any main (non -cli-) linux x86_64 tarball
      url=$(jq -r --arg pre "${name}-" \
        '.assets[] | select(.name | startswith($pre))
                     | select(.name | endswith("-'"$ARCH_ASSET"'.tar.gz"))
                     | select(.name | contains("-cli-") | not)
                     | .browser_download_url' <<<"$rel" | head -n1)
    fi
    asset=${url##*/}
  fi
  if [[ -z $url || -z $asset ]]; then
    log "  SKIP: no ${ARCH_ASSET} tarball in release $tag"
    R_SKIP+=("$name (no asset)"); return 0
  fi
  log "  asset: $asset"

  sha=$(jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .digest // "" | sub("^sha256:"; "")' <<<"$rel")
  if [[ ! $sha =~ ^[0-9a-f]{64}$ ]]; then
    log "  no sha256 digest in API response, downloading to compute checksum..."
    mkdir -p "$builddir"
    if ! curl --compressed -fsSL -o "$builddir/$asset" "$url"; then
      log "  ERROR: download failed"
      rm -rf "$builddir"
      R_FAIL+=("$name"); FAILED=1; return 0
    fi
    sha=$(sha256sum "$builddir/$asset" | awk '{print $1}')
    rm -rf "$builddir"
  fi

  local desc
  desc=$(clean_desc "$(desc_for "$repo")")
  [[ -n $desc ]] || desc="$name"

  write_release_recipe "$name" "$repo" "$ver" "$tag" "$asset" "$url" "$sha" "$desc" "$depends_csv"
  log "  builds/$name/meta.yaml and build.sh updated (pkgver=$ver)"
  R_OK+=("$name -> $ver")
}

process_go() { # $1=name $2=repo $3=depends_csv $4=license_ov
  local name=$1 repo=$2 depends_csv=$3 license_ov=$4

  local tags tag
  if ! tags=$(gh "$GITHUB_API/repos/$repo/tags?per_page=100"); then
    log "  ERROR: could not fetch tags"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  tag=$(jq -r '.[].name' <<<"$tags" | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -n1)
  if [[ -z $tag ]]; then
    log "  ERROR: no semver tags found"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  local ver
  ver=$(strip_version "$tag" "$name")
  log "  latest tag: $tag (version $ver)"

  local desc license
  desc=$(clean_desc "$(desc_for "$repo")")
  [[ -n $desc ]] || desc="$name"
  license=${license_ov:-$(license_for "$repo")}
  [[ -n $license ]] || license="unknown"

  # Download source tarball to compute sha256
  local url="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
  local builddir="$RECIPE_DIR/.build-$name"
  mkdir -p "$builddir"
  if ! curl --compressed -fsSL -o "$builddir/$name-$ver.tar.gz" "$url"; then
    log "  ERROR: download failed"
    rm -rf "$builddir"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  local sha
  sha=$(sha256sum "$builddir/$name-$ver.tar.gz" | awk '{print $1}')
  rm -rf "$builddir"

  write_go_recipe "$name" "$repo" "$ver" "$tag" "$desc" "$license" "$depends_csv" "$sha"
  log "  builds/$name/meta.yaml updated (pkgver=$ver)"
  R_OK+=("$name -> $ver")
}

process_source() { # $1=name $2=repo $3=depends_csv $4=license_ov
  local name=$1 repo=$2 depends_csv=$3 license_ov=$4

  local tags tag
  if ! tags=$(gh "$GITHUB_API/repos/$repo/tags?per_page=100"); then
    log "  ERROR: could not fetch tags"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  tag=$(jq -r '.[].name' <<<"$tags" | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -n1)
  if [[ -z $tag ]]; then
    log "  ERROR: no semver tags found"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  local ver
  ver=$(strip_version "$tag" "$name")
  log "  latest tag: $tag (version $ver)"

  local desc license
  desc=$(clean_desc "$(desc_for "$repo")")
  [[ -n $desc ]] || desc="$name"
  license=${license_ov:-$(license_for "$repo")}
  [[ -n $license ]] || license="unknown"

  local url="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
  local builddir="$RECIPE_DIR/.build-$name"
  mkdir -p "$builddir"
  if ! curl --compressed -fsSL -o "$builddir/$name-$ver.tar.gz" "$url"; then
    log "  ERROR: download failed"
    rm -rf "$builddir"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  local sha
  sha=$(sha256sum "$builddir/$name-$ver.tar.gz" | awk '{print $1}')
  rm -rf "$builddir"

  write_source_recipe "$name" "$repo" "$ver" "$tag" "$url" "$sha" "$desc" "$license" "$depends_csv"
  log "  builds/$name/meta.yaml and build.sh updated (pkgver=$ver)"
  R_OK+=("$name -> $ver")
}

process_npm() { # $1=name $2=repo $3=npm_pkg $4=scripts_csv $5=depends_csv $6=license_ov
  local name=$1 repo=$2 npm_pkg=$3 scripts_csv=$4 depends_csv=$5 license_ov=$6
  local builddir="$RECIPE_DIR/.build-$name"
  [[ -n $npm_pkg ]] || npm_pkg=$name

  local enc=${npm_pkg//\//%2F}
  local meta ver tarball
  if ! meta=$(curl --compressed -fsSL "$NPM_REGISTRY/$enc"); then
    log "  ERROR: could not fetch npm metadata for $npm_pkg"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  ver=$(jq -r '."dist-tags".latest // empty' <<<"$meta")
  if [[ -z $ver ]]; then
    log "  ERROR: no latest version for $npm_pkg"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  tarball=$(jq -r --arg v "$ver" '.versions[$v].dist.tarball // empty' <<<"$meta")
  if [[ -z $tarball ]]; then
    log "  ERROR: no tarball for $npm_pkg@$ver"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  log "  latest: $npm_pkg@$ver"

  # The npm registry exposes sha1/sha512, not sha256; download to compute it.
  local sha
  mkdir -p "$builddir"
  if ! curl --compressed -fsSL -o "$builddir/$name-$ver.tgz" "$tarball"; then
    log "  ERROR: download failed"
    rm -rf "$builddir"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  sha=$(sha256sum "$builddir/$name-$ver.tgz" | awk '{print $1}')
  rm -rf "$builddir"

  local desc license
  desc=$(clean_desc "$(desc_for "$repo")")
  [[ -n $desc ]] || desc=$(clean_desc "$(jq -r '.description // empty' <<<"$meta")")
  [[ -n $desc ]] || desc="$name"
  license=${license_ov:-$(jq -r '.license // empty' <<<"$meta")}
  [[ -n $license ]] || license="unknown"

  write_npm_recipe "$name" "$repo" "$ver" "$tarball" "$sha" "$desc" "$license" "$scripts_csv" "$depends_csv"
  log "  builds/$name/meta.yaml and build.sh updated (pkgver=$ver)"
  R_OK+=("$name -> $ver")
}

process_font() { # $1=name $2=repo $3=asset_ov $4=fontdir
  local name=$1 repo=$2 asset_ov=$3 fontdir=$4
  local builddir="$RECIPE_DIR/.build-$name"

  local rel tag
  if ! rel=$(gh "$GITHUB_API/repos/$repo/releases/latest"); then
    log "  ERROR: could not fetch latest release"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  tag=$(jq -r '.tag_name // empty' <<<"$rel")
  if [[ -z $tag ]]; then
    log "  ERROR: latest release has no tag"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  local ver
  ver=$(strip_version "$tag" "$name")
  log "  latest: $tag (version $ver)"

  local asset url
  if [[ -n $asset_ov ]]; then
    asset=$asset_ov
  else
    log "  ERROR: no asset override for font (set asset=<zip>)"
    R_FAIL+=("$name"); FAILED=1; return 0
  fi
  url=$(jq -r --arg a "$asset" '.assets[] | select(.name == $a) | .browser_download_url // empty' <<<"$rel" | head -n1)
  if [[ -z $url ]]; then
    log "  SKIP: asset $asset not found in release $tag"
    R_SKIP+=("$name (no asset)"); return 0
  fi
  log "  asset: $asset"

  local sha
  sha=$(jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .digest // "" | sub("^sha256:"; "")' <<<"$rel")
  if [[ ! $sha =~ ^[0-9a-f]{64}$ ]]; then
    log "  no sha256 digest in API response, downloading to compute checksum..."
    mkdir -p "$builddir"
    if ! curl --compressed -fsSL -o "$builddir/$asset" "$url"; then
      log "  ERROR: download failed"
      rm -rf "$builddir"
      R_FAIL+=("$name"); FAILED=1; return 0
    fi
    sha=$(sha256sum "$builddir/$asset" | awk '{print $1}')
    rm -rf "$builddir"
  fi

  local desc
  desc=$(clean_desc "$(desc_for "$repo")")
  [[ -n $desc ]] || desc="$name"

  write_font_recipe "$name" "$repo" "$ver" "$tag" "$asset" "$url" "$sha" "$desc" "$fontdir"
  log "  builds/$name/meta.yaml and build.sh updated (pkgver=$ver)"
  R_OK+=("$name -> $ver")
}

process_app() { # $1=name $2=repo $3=extra
  local name=$1 repo=$2 extra=${3:-}

  log ""
  log "=== $name ($repo) ==="

  # Recipes maintained by hand (marker file in the recipe dir) are never
  # regenerated -- they exist precisely because the generic generators don't
  # fit (e.g. win32yank's .exe has no exec bit).
  if [[ -f "$RECIPE_DIR/$name/.manual" ]]; then
    log "  manual recipe (builds/$name/.manual), not regenerating"
    R_SKIP+=("$name (manual)")
    return 0
  fi

  local type=release asset_ov="" depends_csv="" npm_pkg="" scripts_csv="" license_ov="" fontdir=""
  if [[ -n $extra ]]; then
    local pair pairs=()
    IFS=';' read -ra pairs <<<"$extra"
    for pair in "${pairs[@]}"; do
      [[ -z $pair ]] && continue
      case ${pair%%=*} in
      type) type=${pair#*=} ;;
      asset) asset_ov=${pair#*=} ;;
      depends) depends_csv=${pair#*=} ;;
      npm) npm_pkg=${pair#*=} ;;
      scripts) scripts_csv=${pair#*=} ;;
      license) license_ov=${pair#*=} ;;
      dir) fontdir=${pair#*=} ;;
      *) log "  warning: unknown override '$pair'" ;;
      esac
    done
  fi

  case $type in
  release) process_release "$name" "$repo" "$asset_ov" "$depends_csv" ;;
  go) process_go "$name" "$repo" "$depends_csv" "$license_ov" ;;
  source) process_source "$name" "$repo" "$depends_csv" "$license_ov" ;;
  npm) process_npm "$name" "$repo" "$npm_pkg" "$scripts_csv" "$depends_csv" "$license_ov" ;;
  font) process_font "$name" "$repo" "$asset_ov" "$fontdir" ;;
  *)
    log "  ERROR: unknown type '$type'"
    R_FAIL+=("$name"); FAILED=1
    ;;
  esac
}

# --------------------------------------------------------------------- main ---

while IFS=$' \t' read -r name repo extra _ || [[ -n ${name:-} ]]; do
  [[ -z ${name:-} || $name == \#* ]] && continue
  if [[ -z ${repo:-} ]]; then
    log "malformed line in manlist.txt: $name"
    continue
  fi
  if ((${#SELECTED[@]})); then
    skip=1
    for s in "${SELECTED[@]}"; do
      [[ $s == "$name" ]] && skip=0
    done
    ((skip)) && continue
  fi
  process_app "$name" "$repo" "${extra:-}"
done <"$APPS_CONF"

log ""
log "================ summary ================"
for r in "${R_OK[@]:-}"; do [[ -n $r ]] && log "  ok      $r"; done
for r in "${R_SKIP[@]:-}"; do [[ -n $r ]] && log "  skipped $r"; done
for r in "${R_FAIL[@]:-}"; do [[ -n $r ]] && log "  FAILED  $r"; done
log "========================================="

exit $FAILED
