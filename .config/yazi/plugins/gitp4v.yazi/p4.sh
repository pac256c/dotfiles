# p4.sh - Perforce half of the gitp4v backend. Sourced by gitp4v.sh (which
# provides die, pause, the cache/state variables, classify_err and pin
# helpers); it only defines functions.
#
# A p4 depot appears under the view root like a git org: view/<depot>/<dirs>.
# Directories are listed lazily, one level at a time. To edit, a lightweight
# workspace (client) is created per chosen depot folder ("workspace root");
# the root -> client mapping lives in $STATE/p4-ws.tsv. Files are synced one by
# one as they are edited. Opened files sit in the default changelist; "create
# changelist" moves them into a numbered CL; submit / shelve / revert act on it.
# One pending numbered CL per workspace at a time.

P4WS="$STATE/p4-ws.tsv"

# ---------------------------------------------------------------- helpers
# Depot-syntax quoting of the characters p4 reserves.
p4_enc() { sed -e 's/%/%25/g' -e 's/@/%40/g' -e 's/#/%23/g' -e 's/\*/%2A/g'; }
p4_dec() { sed -e 's/%2A/*/g' -e 's/%23/#/g' -e 's/%40/@/g' -e 's/%25/%/g'; }
enc1() { printf '%s' "$1" | p4_enc; }

# "//depot" or "//depot/dir/..." : at least a depot name, no "..", no wildcards.
valid_p4path() {
    case "$1" in
        //?*) ;;
        *) die "bad depot path '$1'" ;;
    esac
    case "$1" in *..*|*'*'*|*'?'*|*'#'*|*'@'*) die "bad depot path '$1'" ;; esac
}

# Run p4, die with a classified message if it fails (exit code or stderr text
# matching an error). Prints stdout.
p4run() {
    local out err rc
    err=$(mktemp)
    out=$(p4 "$@" 2>"$err"); rc=$?
    if [ $rc -ne 0 ]; then
        out=$(cat "$err"); rm -f "$err"
        die "$(classify_err "$out")"
    fi
    rm -f "$err"
    printf '%s' "$out"
}

p4_depot_of() { local p=${1#//}; echo "${p%%/*}"; }

# ------------------------------------------------------------- depots list
# "name<TAB>p4" for every depot of the server; empty on failure (message on stderr).
p4_depots() {
    local out
    out=$(p4 -ztag depots 2>&1) || { echo "$out" >&2; return 1; }
    printf '%s\n' "$out" | awk '
        /^\.\.\. name /  { name = $3 }
        /^\.\.\. type /  { if ($3 == "local" || $3 == "stream") print name "\tp4" }'
}

# ------------------------------------------------------------ browsing
# Placeholder for the files opened in a workspace, so adds/deletes show.
p4_overlay() { # dp root-dir
    local dp="$1" root="$2" ws client op act path name
    ws=$(cmd_p4_ws_find "$dp"); [ -n "$ws" ] || return 0
    client=$(printf '%s' "$ws" | cut -f2)
    p4 -c "$client" opened 2>/dev/null | while IFS= read -r op; do
        path=${op%%#*}
        act=${op#* - }; act=${act%% *}
        case "$path" in "$dp"/*) ;; *) continue ;; esac
        name=${path#"$dp"/}
        case "$name" in */*) continue ;; esac   # only direct children
        name=$(printf '%s' "$name" | p4_dec)
        case "$act" in
            delete|move/delete) rm -f -- "${root:?}/$name" ;;
            *) [ -e "$root/$name" ] || : > "$root/$name" ;;
        esac
    done
}

# p4-list <dir> [force]: list one directory level into the shadow tree.
cmd_p4_list() {
    local dp="${1:-}" force="${2:-}" rel root enc errf dirs files n
    valid_p4path "$dp"
    dp=${dp%/}
    rel=${dp#//}; root="$VIEW/$rel"
    mkdir -p "$root" "$HIST" || die "cannot create $root"
    if [ -z "$force" ] && [ -f "$root/.loaded" ] \
        && [ -n "$(find "$root/.loaded" -mmin "-$TTL" 2>/dev/null)" ]; then
        echo "$root"; return 0
    fi
    enc=$(enc1 "$dp")
    errf=$(mktemp)
    dirs=$(p4 dirs "$enc/*" 2>"$errf")
    files=$(p4 files -e "$enc/*" 2>>"$errf")
    n=$(printf '%s%s' "$dirs" "$files" | grep -c .)
    # A level with no files answers "protected namespace" / "no such file(s)":
    # that is only an error when nothing at all could be listed.
    if [ "$n" -eq 0 ] && [ -s "$errf" ] && ! grep -q 'no such file' "$errf"; then
        local m; m=$(cat "$errf"); rm -f "$errf"
        die "$(classify_err "$m")"
    fi
    rm -f "$errf"

    find "$root" -mindepth 1 -maxdepth 1 ! -name .loaded -exec rm -rf {} + 2>/dev/null
    printf '%s\n' "$dirs" | grep . | sed -e 's#^.*/##' | p4_dec | tr '\n' '\0' \
        | (cd "$root" && xargs -0 -r mkdir -p --)
    printf '%s\n' "$files" | grep . | sed -E 's/#[0-9]+ - .*$//; s#^.*/##' | p4_dec | tr '\n' '\0' \
        | (cd "$root" && xargs -0 -r touch --)
    p4_overlay "$dp" "$root"
    : > "$root/.loaded"
    echo "$root"
}

# ------------------------------------------------------------- history
# p4-hist <file>: "CL<TAB>date<TAB>user<TAB>description<TAB>rev", newest first.
cmd_p4_hist() {
    local dp="${1:-}" enc key out line cl t user desc rev
    valid_p4path "$dp"
    enc=$(enc1 "$dp")
    mkdir -p "$HIST"
    key=$(printf '%s' "$dp" | cksum | cut -d' ' -f1)
    out="$HIST/p4.$key"
    if [ -z "$(find "$out" -mmin -10 2>/dev/null)" ]; then
        local raw errf
        raw=$(mktemp); errf=$(mktemp)
        if ! p4 -ztag filelog -m "$LIMIT" "$enc" >"$raw" 2>"$errf" || [ ! -s "$raw" ]; then
            local m; m=$(cat "$errf"); rm -f "$raw" "$errf"
            die "$(classify_err "${m:-no history for $dp}")"
        fi
        awk '
            match($0, /^\.\.\. (rev|change|time|user|desc)[0-9]+ /) {
                key = substr($0, 5, RLENGTH - 5)
                val = substr($0, RLENGTH + 1)
                n = key; sub(/^[a-z]+/, "", n); k = key; sub(/[0-9]+$/, "", k)
                v[k, n] = val; if (n + 0 > max) max = n + 0; seen = 1
                next
            }
            END { if (seen) for (i = 0; i <= max; i++)
                print v["change", i] "\t" v["time", i] "\t" v["user", i] "\t" v["desc", i] "\t" v["rev", i] }
        ' "$raw" | while IFS=$'\t' read -r cl t user desc rev; do
            printf '%s\t%s\t%s\t%s\t%s\n' "$cl" "$(date -d "@$t" +%F 2>/dev/null || echo "$t")" "$user" "$desc" "$rev"
        done > "$out.tmp"
        rm -f "$raw" "$errf"
        mv "$out.tmp" "$out"
    fi
    cat "$out"
}

# p4-histdir <file>: placeholder dir, one entry per revision, newest first
# once sorted descending. Names "REV CL date user  description".
cmd_p4_histdir() {
    local dp="${1:-}" dir list w sha date user desc rev name maxrev=0
    valid_p4path "$dp"
    list=$(cmd_p4_hist "$dp") || exit 1
    while IFS=$'\t' read -r sha date user desc rev; do
        [ "${rev:-0}" -gt "$maxrev" ] 2>/dev/null && maxrev=$rev
    done <<< "$list"
    w=${#maxrev}; [ "$w" -lt 2 ] && w=2
    dir="$COMMITS/${dp#//}"
    case "$dir" in "$COMMITS"/?*/?*) rm -rf "$dir" ;; *) die "refusing to remove $dir" ;; esac
    mkdir -p "$dir" || die "cannot create $dir"
    while IFS=$'\t' read -r sha date user desc rev; do
        [ -n "$sha" ] || continue
        name=$(printf '%0*d %s %s  %s  %s' "$w" "$rev" "$sha" "$date" "$user" "$desc")
        name=${name//\//-}
        : > "$dir/${name:0:150}"
    done <<< "$list"
    echo "$dir"
}

# p4-show <file> <rev>: CL header + description + this revision's diff, in the
# same layout the plugin renders for git commits.
cmd_p4_show() {
    local dp="${1:-}" rev="${2:-}" enc key out cl hdr act diff adds dels
    valid_p4path "$dp"
    case "$rev" in ''|*[!0-9]*) die "bad revision '$rev'" ;; esac
    mkdir -p "$HIST"
    enc=$(enc1 "$dp")
    key=$(printf '%s#%s' "$dp" "$rev" | cksum | cut -d' ' -f1)
    out="$HIST/p4.show.$key"
    if [ ! -s "$out" ]; then
        local fl
        fl=$(p4 files "$enc#$rev" 2>/dev/null | head -1)   # "//f#2 - edit change 123 (text)"
        cl=$(printf '%s\n' "$fl" | sed -n 's/^.* - [^ ]* change \([0-9]*\) .*$/\1/p')
        act=$(printf '%s\n' "$fl" | sed -n 's/^.* - \([^ ]*\) change .*$/\1/p')
        [ -n "$cl" ] || die "no such revision $dp#$rev"
        {
            echo "CL $cl"
            p4 describe -s "$cl" 2>/dev/null | awk '/^Affected files/{exit} {print}' | sed -e '1s/^Change [0-9]* by /Author: /' -e 's/^\t//'
            echo
            if [ "$rev" -gt 1 ] && [ "$act" != "add" ] && [ "$act" != "move/add" ]; then
                diff=$(p4 diff2 -du "$enc#$((rev - 1))" "$enc#$rev" 2>/dev/null | sed 1d)
            else
                diff=$(p4 print -q "$enc#$rev" 2>/dev/null | sed 's/^/+/')
            fi
            adds=$(printf '%s\n' "$diff" | grep -c '^+[^+]')
            dels=$(printf '%s\n' "$diff" | grep -c '^-[^-]')
            printf -- '--- %s#%s (%s, +%s -%s)\n' "$dp" "$rev" "${act:-edit}" "$adds" "$dels"
            printf '%s\n' "$diff"
        } > "$out.tmp" && mv "$out.tmp" "$out"
    fi
    cat "$out"
}

p4_fetch() { # depotfile rev dest   (rev empty = head)
    p4 print -q "$(enc1 "$1")#${2:-head}" > "$3" 2>/dev/null || : > "$3"
}

# p4-print <file> [rev] [idx]: view a revision read-only (head by default).
cmd_p4_print() {
    local dp="${1:-}" rev="${2:-}" tmp f ed
    valid_p4path "$dp"
    tmp=$(mktemp -d) || die "mktemp failed"
    trap "rm -rf '$tmp'" EXIT
    f="$tmp/$(basename "$dp")${rev:+#$rev}"
    echo "gitp4v: fetching $dp${rev:+#$rev} ..." >&2
    p4_fetch "$dp" "$rev" "$f"
    chmod 444 "$f"
    ed="${EDITOR:-vi}"
    case "$(basename "${ed%% *}")" in
        vi|vim|nvim|view) $ed -R "$f" ;;
        *) ${PAGER:-less} "$f" ;;
    esac
}

# p4-diffv <file> <left-rev> <right-rev>: files named <name>#<rev>.
cmd_p4_diffv() {
    local dp="${1:-}" a="${2:-}" b="${3:-}" tmp base fa fb
    valid_p4path "$dp"
    [ -n "$a" ] && [ -n "$b" ] || die "need two revisions"
    base=$(basename "$dp"); fa="$base#$a"; fb="$base#$b"
    tmp=$(mktemp -d) || die "mktemp failed"
    trap "rm -rf '$tmp'" EXIT
    echo "gitp4v: fetching two revisions of $dp ..." >&2
    p4_fetch "$dp" "$a" "$tmp/$fa"
    p4_fetch "$dp" "$b" "$tmp/$fb"
    if [ -n "${GITP4V_DIFF:-}" ]; then
        (cd "$tmp" && $GITP4V_DIFF "$fa" "$fb")
    else
        { echo "# $dp   left=#$a  right=#$b"
          (cd "$tmp" && git diff --no-index --color=always -- "$fa" "$fb"); } | less -R
    fi
}

# ------------------------------------------------------------ workspaces
# $P4WS rows: root<TAB>client<TAB>local-root

# p4-ws-find <path>: the workspace whose root covers the path (longest wins).
cmd_p4_ws_find() {
    local dp="${1:-}" line root client lr
    [ -s "$P4WS" ] || return 0
    line=$(DP="$dp" awk -F'\t' '
        { r = $1; if (ENVIRON["DP"] == r || index(ENVIRON["DP"], r "/") == 1)
            if (length(r) > best) { best = length(r); line = $0 } }
        END { if (line != "") print line }' "$P4WS")
    [ -n "$line" ] || return 0
    IFS=$'\t' read -r root client lr <<< "$line"
    # The workspace folder was deleted behind our back: forget the whole
    # workspace (opened files, pending CLs, client) instead of reporting it
    # missing; the next change creates a fresh one.
    if [ ! -d "$lr" ]; then p4_drop_ws "$root" "$client" "$lr"; return 0; fi
    printf '%s\n' "$line"
}

# p4-ws-create <root>: make a lightweight client viewing <root>/...
cmd_p4_ws_create() {
    local root="${1:-}" slug client lr enc spec
    valid_p4path "$root"; root=${root%/}
    [ -z "$(cmd_p4_ws_find "$root")" ] || die "a workspace already covers $root"
    slug=$(printf '%s' "${root#//}" | tr -c 'A-Za-z0-9\n' '_')
    client="gitp4v_${USER:-user}_${slug}"
    [ "${#client}" -le 90 ] || client="${client:0:70}_$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
    lr="$CLONES/$slug"
    enc=$(enc1 "$root")
    mkdir -p "$lr" || die "cannot create $lr"
    spec=$(p4 --field "Root=$lr" --field "View=\"$enc/...\" \"//$client/...\"" \
              --field "Host=" --field "Description=gitp4v workspace for $root" \
              client -o "$client" 2>&1) || die "$(classify_err "$spec")"
    printf '%s\n' "$spec" | p4 client -i >/dev/null 2>"$CACHE/.p4err" \
        || die "$(classify_err "$(cat "$CACHE/.p4err")")"
    mkdir -p "$STATE"
    printf '%s\t%s\t%s\n' "$root" "$client" "$lr" >> "$P4WS"
    printf '%s\t%s\n' "$client" "$lr"
}

# Resolve the workspace for a path or die. Sets W_ROOT W_CLIENT W_LOCAL.
need_ws() {
    local ws
    ws=$(cmd_p4_ws_find "$1")
    [ -n "$ws" ] || die "no workspace covers $1 (create one with the workspace key)"
    IFS=$'\t' read -r W_ROOT W_CLIENT W_LOCAL <<< "$ws"
}

# The one pending numbered CL of the workspace's client ("" if none).
p4_pending_cl() { p4 -c "$1" changes -c "$1" -s pending -m 1 2>/dev/null | awk '{print $2}'; }

block_if_cl() { # client
    local cl; cl=$(p4_pending_cl "$1")
    [ -z "$cl" ] || die "CL $cl is pending (not submitted). Submit or revert it before changing more files"
}

# p4-info <path>: key<TAB>value (root, client, local, default, cl, cldesc, clfiles, shelved)
cmd_p4_info() {
    local dp="${1:-}" cl d
    valid_p4path "$dp"
    local ws; ws=$(cmd_p4_ws_find "$dp")
    if [ -z "$ws" ]; then printf 'root\t\n'; return 0; fi
    IFS=$'\t' read -r W_ROOT W_CLIENT W_LOCAL <<< "$ws"
    printf 'root\t%s\nclient\t%s\nlocal\t%s\n' "$W_ROOT" "$W_CLIENT" "$W_LOCAL"
    printf 'default\t%s\n' "$(p4 -c "$W_CLIENT" opened -c default 2>/dev/null | grep -c .)"
    cl=$(p4_pending_cl "$W_CLIENT")
    printf 'cl\t%s\n' "$cl"
    [ -n "$cl" ] || return 0
    d=$(p4 -c "$W_CLIENT" describe -s -S "$cl" 2>/dev/null)
    printf 'cldesc\t%s\n' "$(printf '%s\n' "$d" | sed -n '3p' | sed 's/^\t//')"
    printf 'clfiles\t%s\n' "$(p4 -c "$W_CLIENT" opened -c "$cl" 2>/dev/null | grep -c .)"
    # shelved file lines look like "... //depot/path#rev action"
    if printf '%s\n' "$d" | grep -q '^\.\.\. //'; then printf 'shelved\tyes\n'; else printf 'shelved\tno\n'; fi
}

# ---------------------------------------------------------- open for edit
# p4 answers "not opened" on stderr with exit 0, so test for output instead.
p4_is_opened() { [ -n "$(p4 -c "$W_CLIENT" opened "$1" 2>/dev/null)" ]; }

p4_local_of() { p4 -c "$W_CLIENT" -ztag where "$(enc1 "$1")" 2>/dev/null | awk '/^\.\.\. path /{sub(/^\.\.\. path /, ""); print; exit}'; }

# Run a p4 command for a file and verify it ended up opened; else die with p4's text.
p4_open_file() { # verb depotfile [extra args...]
    local verb="$1" dp="$2" enc out; shift 2
    enc=$(enc1 "$dp")
    out=$(p4 -c "$W_CLIENT" "$verb" "$@" "$enc" 2>&1)
    p4_is_opened "$enc" \
        || die "cannot check out $dp ($verb not allowed): $(classify_err "${out:-no reason given}")"
}

# p4-checkout <file>...: sync and check out (p4 edit) each file; prints the
# local paths. Dies with p4's reason when checkout is not allowed.
cmd_p4_checkout() {
    local dp lp
    [ $# -gt 0 ] || die "no files given"
    need_ws "$1"; block_if_cl "$W_CLIENT"
    for dp in "$@"; do
        valid_p4path "$dp"
        p4 -c "$W_CLIENT" sync "$(enc1 "$dp")" >/dev/null 2>&1
        p4_open_file edit "$dp"
        lp=$(p4_local_of "$dp"); [ -f "$lp" ] || die "checked out $dp but $lp is missing"
        printf '%s\n' "$lp"
    done
}

# p4-editor <local path>...: open files in the opener yazi.toml picks, else $EDITOR.
cmd_p4_editor() {
    [ $# -gt 0 ] || die "no files given"
    open_in_editor "$@"
}

# p4-add <file>: create an empty new file and mark it for add.
cmd_p4_add() {
    local dp="${1:-}" lp out
    valid_p4path "$dp"
    need_ws "$dp"; block_if_cl "$W_CLIENT"
    lp=$(p4_local_of "$dp"); [ -n "$lp" ] || die "$dp is not mapped by the workspace"
    [ ! -e "$lp" ] || die "$dp already exists in the workspace"
    mkdir -p "$(dirname "$lp")" && : > "$lp" || die "cannot create $lp"
    out=$(p4 -c "$W_CLIENT" add "$lp" 2>&1)
    p4_is_opened "$(enc1 "$dp")" || { rm -f "$lp"; die "cannot add $dp: $(classify_err "$out")"; }
    mkdir -p "$VIEW/$(dirname "${dp#//}")" && : > "$VIEW/${dp#//}"
    printf '%s\n' "$lp"
}

# p4-rm <file-or-dir>: p4 delete.
cmd_p4_rm() {
    local dp="${1:-}" enc out target
    valid_p4path "$dp"
    need_ws "$dp"; block_if_cl "$W_CLIENT"
    enc=$(enc1 "$dp")
    target="$enc"
    [ -d "$VIEW/${dp#//}" ] && target="$enc/..."
    p4 -c "$W_CLIENT" sync "$target" >/dev/null 2>&1
    out=$(p4 -c "$W_CLIENT" delete "$target" 2>&1)
    p4_is_opened "$target" || die "cannot delete $dp: $(classify_err "${out:-delete refused}")"
    rm -rf -- "${VIEW:?}/${dp#//}"
    echo "Deleted $dp"
}

# p4-mv <old> <new>: check out the file and p4 move it.
cmd_p4_mv() {
    local old="${1:-}" new="${2:-}" out
    valid_p4path "$old"; valid_p4path "$new"
    need_ws "$old"; block_if_cl "$W_CLIENT"
    [ -z "$(p4 -c "$W_CLIENT" files -e "$(enc1 "$new")" 2>/dev/null)" ] || die "$new already exists"
    p4 -c "$W_CLIENT" sync "$(enc1 "$old")" >/dev/null 2>&1
    p4_open_file edit "$old"
    out=$(p4 -c "$W_CLIENT" move "$(enc1 "$old")" "$(enc1 "$new")" 2>&1)
    p4_is_opened "$(enc1 "$new")" || die "cannot rename $old: $(classify_err "${out:-move refused}")"
    mkdir -p "$VIEW/$(dirname "${new#//}")"
    mv -- "$VIEW/${old#//}" "$VIEW/${new#//}" 2>/dev/null || : > "$VIEW/${new#//}"
    echo "Renamed $old to $new"
}

# ----------------------------------------------------------- changelists
# p4-cl-create <path> <description>: move the default changelist's files into a new numbered CL.
cmd_p4_cl_create() {
    local dp="${1:-}" desc="${2:-}" out cl
    valid_p4path "$dp"; [ -n "$desc" ] || die "empty description"
    need_ws "$dp"; block_if_cl "$W_CLIENT"
    [ "$(p4 -c "$W_CLIENT" opened -c default 2>/dev/null | grep -c .)" -gt 0 ] \
        || die "no files are opened in the default changelist"
    out=$(p4 -c "$W_CLIENT" change -o | DESC="$desc" awk '
        /^Description:/ { print; print "\t" ENVIRON["DESC"]; skip = 1; next }
        skip && /^[ \t]/ { next }
        { skip = 0; print }' | p4 -c "$W_CLIENT" change -i 2>&1) || die "$(classify_err "$out")"
    cl=$(printf '%s\n' "$out" | sed -n 's/^Change \([0-9]*\) created.*/\1/p')
    [ -n "$cl" ] || die "$(classify_err "$out")"
    echo "CL $cl created"
}

# p4-submit <path>: submit the pending CL.
cmd_p4_submit() {
    local dp="${1:-}" cl out
    valid_p4path "$dp"; need_ws "$dp"
    cl=$(p4_pending_cl "$W_CLIENT"); [ -n "$cl" ] || die "no pending changelist to submit"
    out=$(p4 -c "$W_CLIENT" submit -c "$cl" 2>&1) || {
        die "$(classify_err "$(printf '%s\n' "$out" | tail -4)") -- sync and resolve in the workspace ($W_LOCAL) if files are out of date, then submit again"
    }
    p4_drop_ws "$W_ROOT" "$W_CLIENT" "$W_LOCAL"
    echo "Submitted CL $cl: $(printf '%s\n' "$out" | tail -1)"
}

# Delete a workspace: its client, folder and bookkeeping row (clearing any
# opened files and pending CLs first). Called when its work is done (submitted
# or reverted) so a client never outlives its changes, and for stale workspaces.
p4_drop_ws() { # root client local
    local root="$1" client="$2" lr="$3" cl
    p4 -c "$client" revert -k "//$client/..." >/dev/null 2>&1
    for cl in $(p4 -c "$client" changes -c "$client" -s pending 2>/dev/null | awk '{print $2}'); do
        p4 -c "$client" shelve -d -f -c "$cl" >/dev/null 2>&1
        p4 -c "$client" change -d "$cl" >/dev/null 2>&1
    done
    p4 client -d "$client" >/dev/null 2>&1
    case "$lr" in "$CLONES"/?*) rm -rf -- "$lr" ;; esac
    if [ -f "$P4WS" ]; then
        grep -v -F -- "$(printf '%s\t%s\t' "$root" "$client")" "$P4WS" > "$P4WS.tmp"; mv "$P4WS.tmp" "$P4WS"
    fi
}

# p4-ws-delete <path>: delete the workspace covering a path (client and local files).
cmd_p4_ws_delete() {
    local dp="${1:-}"
    valid_p4path "$dp"; need_ws "$dp"
    [ -z "$(p4 -c "$W_CLIENT" opened 2>/dev/null)" ] || die "files are still opened in this workspace; revert them first"
    [ -z "$(p4_pending_cl "$W_CLIENT")" ] || die "a changelist is still pending in this workspace; revert it first"
    p4_drop_ws "$W_ROOT" "$W_CLIENT" "$W_LOCAL"
    echo "Deleted workspace $W_CLIENT and its local files"
}

# p4-shelve <path>: shelve the pending CL for review.
cmd_p4_shelve() {
    local dp="${1:-}" cl out
    valid_p4path "$dp"; need_ws "$dp"
    cl=$(p4_pending_cl "$W_CLIENT"); [ -n "$cl" ] || die "no pending changelist to shelve"
    out=$(p4 -c "$W_CLIENT" shelve -f -c "$cl" 2>&1) || die "$(classify_err "$out")"
    echo "Shelved CL $cl"
}

# p4-discard <path>: revert everything opened and delete the pending CL.
cmd_p4_discard() {
    local dp="${1:-}" cl
    valid_p4path "$dp"; need_ws "$dp"
    cl=$(p4_pending_cl "$W_CLIENT")
    p4 -c "$W_CLIENT" revert -c default "//$W_CLIENT/..." >/dev/null 2>&1
    if [ -n "$cl" ]; then
        p4 -c "$W_CLIENT" revert -c "$cl" "//$W_CLIENT/..." >/dev/null 2>&1
        p4 -c "$W_CLIENT" shelve -d -f -c "$cl" >/dev/null 2>&1
        p4 -c "$W_CLIENT" change -d "$cl" >/dev/null 2>&1 || die "reverted files but could not delete CL $cl"
    fi
    p4_drop_ws "$W_ROOT" "$W_CLIENT" "$W_LOCAL"
    echo "Reverted all opened files${cl:+, deleted CL $cl} and deleted the workspace"
}

p4_revert_files() { # revert specific depot files (used by the popup)
    p4 -c "$W_CLIENT" revert "$(enc1 "$1")" >/dev/null 2>&1
}

# ------------------------------------------------------------ opened popup
# marker<TAB>depot path<TAB>local path
p4_opened_list() {
    p4 -c "$W_CLIENT" opened 2>/dev/null | while IFS= read -r op; do
        local path act m
        path=${op%%#*}
        act=${op#* - }; act=${act%% *}
        case "$act" in
            add|branch) m=A ;; edit|integrate) m=M ;; delete|move/delete|purge) m=D ;; move/add) m=R ;; *) m=M ;;
        esac
        printf '%s\t%s\n' "$m" "$(printf '%s' "$path" | p4_dec)"
    done
}

# p4-status-data <root>: data for the opened-files popup. First line
# "H<TAB>committed(0|1)<TAB>text" (committed = a numbered CL exists), then
# "<A|M|D|R><TAB>depot path" per opened file.
cmd_p4_status_data() {
    local root="${1:-}" cl desc state
    need_ws "$root"
    cl=$(p4_pending_cl "$W_CLIENT")
    if [ -n "$cl" ]; then
        desc=$(p4 -c "$W_CLIENT" describe -s "$cl" 2>/dev/null | sed -n '3p' | sed 's/^\t//')
        state="CL $cl (pending, not submitted)"
        p4 -c "$W_CLIENT" describe -s -S "$cl" 2>/dev/null | grep -q '^\.\.\. //' && state="$state [shelved]"
        [ -z "$desc" ] || state="$state $desc"
        printf 'H\t1\t%s\n' "$state"
    else
        printf 'H\t0\tdefault changelist\n'
    fi
    p4_opened_list
}

# p4-status-diff <root> <marker> <path>: show the diff of one opened file.
cmd_p4_status_diff() {
    local root="${1:-}" st="${2:-}" p="${3:-}" lp
    need_ws "$root"
    [ -n "$p" ] || return 0
    if [ "$st" = "A" ] || [ "$st" = "R" ]; then
        lp=$(p4_local_of "$p"); (cat -- "$lp" 2>/dev/null) | less
    else
        p4 -c "$W_CLIENT" diff -du "$(enc1 "$p")" 2>&1 | less
    fi
}

# p4-revert-file <root> <path>: revert one opened file (the plugin confirms first).
cmd_p4_revert_file() {
    local root="${1:-}" p="${2:-}"
    need_ws "$root"
    [ -z "$(p4_pending_cl "$W_CLIENT")" ] || die "CL is pending; revert it as a whole (e x)"
    p4_revert_files "$p"
    echo "Reverted $p"
}
