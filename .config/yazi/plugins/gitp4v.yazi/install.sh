#!/bin/bash
# install.sh - hook gitp4v into a yazi config with three small marked blocks
# (everything else of the plugin lives in this folder):
#   keymap.toml   <- plugins/gitp4v.yazi/keymap.toml
#   yazi.toml     <- plugins/gitp4v.yazi/yazi.toml   ([plugin] previewer rules)
#   init.lua      <- require("gitp4v"):setup(gitp4v_opts)
#                    gitp4v_opts is YOUR settings table, kept in init.lua outside the block
#                    (a commented template is added if it is missing); defaults: config.lua
# Re-running replaces the blocks, so editing keymap.toml / yazi.toml here and
# re-running is how a key or rule change is applied.
#
# Usage: install.sh [--uninstall]    (config dir: $YAZI_CONFIG_HOME or ~/.config/yazi)

set -u
here=$(dirname "$(readlink -f "$0")")
cfg="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}"
begin_toml='# >>> gitp4v (managed by plugins/gitp4v.yazi/install.sh; edit the files in that folder) >>>'
end_toml='# <<< gitp4v <<<'
begin_lua='-- >>> gitp4v (managed by plugins/gitp4v.yazi/install.sh) >>>'
end_lua='-- <<< gitp4v <<<'

# strip_block <file> <begin-marker-prefix>: print the file without a marked block
strip_block() {
    awk -v b=">>> gitp4v" -v e="<<< gitp4v" '
        index($0, b) { skip = 1; next }
        index($0, e) { skip = 0; next }
        !skip { print }' "$1"
}

# put_block <file> <begin> <end> <body-file or "-" for stdin body>
put_block() {
    local file="$1" begin="$2" end="$3" tmp
    tmp=$(mktemp)
    [ -f "$file" ] && strip_block "$file" > "$tmp"
    # drop trailing blank lines so repeated installs do not grow the file
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
    { [ -s "$tmp" ] && cat "$tmp" && echo; echo "$begin"; cat; echo "$end"; } > "$file.new"
    mv "$file.new" "$file"; rm -f "$tmp"
}

remove_block() {
    local file="$1" tmp
    [ -f "$file" ] || return 0
    tmp=$(mktemp); strip_block "$file" > "$tmp"
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
    mv "$tmp" "$file"
}

mkdir -p "$cfg"

if [ "${1:-}" = "--uninstall" ]; then
    remove_block "$cfg/keymap.toml"; remove_block "$cfg/yazi.toml"; remove_block "$cfg/init.lua"
    echo "gitp4v hooks removed from $cfg (plugin files left in place)"
    exit 0
fi

# a second [plugin] table in yazi.toml would be invalid TOML
if [ -f "$cfg/yazi.toml" ] && strip_block "$cfg/yazi.toml" | grep -q '^\[plugin\]'; then
    echo "yazi.toml already has a [plugin] table. Merge the rules from $here/yazi.toml into it by hand" >&2
    echo "(keymap.toml and init.lua are still installed)." >&2
    skip_toml=1
fi

[ -f "$cfg/keymap.toml" ] && cp -n "$cfg/keymap.toml" "$cfg/keymap.toml.pre-gitp4v" 2>/dev/null
put_block "$cfg/keymap.toml" "$begin_toml" "$end_toml" < "$here/keymap.toml"
[ -n "${skip_toml:-}" ] || put_block "$cfg/yazi.toml" "$begin_toml" "$end_toml" < "$here/yazi.toml"
# the user's settings live in init.lua, outside the managed block; add a template once
if ! { [ -f "$cfg/init.lua" ] && strip_block "$cfg/init.lua" | grep -q 'gitp4v_opts'; }; then
    {
        [ -f "$cfg/init.lua" ] && { cat "$cfg/init.lua"; echo; }
        cat <<'TEMPLATE'
-- gitp4v settings (yours; kept outside the plugin folder). Uncomment and edit.
-- All options and their defaults: plugins/gitp4v.yazi/config.lua
-- gitp4v_opts = {
--     org = "my-github-org",
--     p4 = { port = "perforce.example.com:1666", user = "me" },
--     clones = "/big/disk/gitp4v",
--     diff = "nvim -d",
-- }
TEMPLATE
    } > "$cfg/init.lua.new" && mv "$cfg/init.lua.new" "$cfg/init.lua"
fi
printf 'require("gitp4v"):setup(gitp4v_opts)\n' | put_block "$cfg/init.lua" "$begin_lua" "$end_lua"

echo "gitp4v installed into $cfg"
echo "  keys:      $cfg/keymap.toml"
[ -n "${skip_toml:-}" ] || echo "  previewer: $cfg/yazi.toml"
echo "  setup:     $cfg/init.lua (your settings: gitp4v_opts there; defaults: $here/config.lua)"
