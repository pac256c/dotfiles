#!/bin/bash
# gitp4v.sh - backend for the gitp4v yazi plugin.
# Browses GitHub Enterprise repos like a p4v depot: a zero-byte "shadow tree"
# per repo (so yazi can navigate/search it natively), per-path history, diff,
# read, and editing in a local clone on one review branch (commit, PR, discard).
#
# Shadow tree layout:  $CACHE/view/<owner>/<repo>/<path>
# A repo is identified everywhere by its "owner/repo" name (nwo).
# Clones live at $CLONES/<repo>-<branch>; the active branch and clone of each
# repo are remembered in $CLONES/.gitp4v/. One branch / one commit / one PR at
# a time per repo.
#
# Usage: gitp4v.sh <cmd> [args...]
#   list                            print "owner/repo<TAB>url" for every depot
#   open-root                       create <owner>/<repo> skeleton dirs, print view root
#   open <nwo> [force]              build/refresh a repo's shadow tree, print its root
#   hist <nwo> <relpath>            print "sha<TAB>date<TAB>author<TAB>subject" lines
#   histdir <nwo> <relpath>         dir of one placeholder file per commit, print it
#   show <nwo> <sha> <relpath>      commit message + this file's patch
#   diffv <nwo> <relpath> <lsha> <lidx> <rsha> <ridx>   diff two versions
#   read <nwo> <relpath> [ref] [idx]   open a version (default: current) read-only
#   branch <nwo>                    print the active review branch, empty if none
#   plan-branch <nwo> <name>        print "<clone dir><TAB>new|existing"
#   start-branch <nwo> <name>       clone (into <repo>-<branch>) and create the branch
#   pin-toggle <kind> <target> <saved-path>   pin / unpin a file (local | depot)
#   pin-build                       rebuild the pinned-files dir, list the pins
#   edit <nwo> <relpath>...         open files from the review branch in $EDITOR
#   rm <nwo> <relpath>              delete a file/dir on the review branch
#   add <nwo> <relpath>             create an empty file on the review branch
#   mv <nwo> <old> <new>            rename a file/dir on the review branch
#   commit <nwo> <message>          commit all changes
#   pr-info <nwo>                   branch/dir/dirty/ahead/subject/pr/prstate
#   pr <nwo> <title> <body>         rebase if needed, push, open (or reuse) a PR
#   status-data <nwo>               changed files for the popup (H line, then A/M/D/R rows)
#   status-diff <nwo> <m> <path> <old>   show the diff of one changed file
#   discard-file <nwo> <m> <path> <old>  throw away one file's changes
#   discard <nwo>                   delete the local review branch and changes
#   kind <name>                     git or p4 for a top-level entry of the view root
#   p4-login | gh-login             interactive logins
#   p4-list <dir> [force]           list one depot folder into the shadow tree
#   p4-hist | p4-histdir | p4-show  history of a depot file (see p4.sh)
#   p4-print <file> [rev]           view a revision read-only
#   p4-diffv <file> <lrev> <rrev>   diff two revisions
#   p4-ws-find | p4-ws-create | p4-info   workspaces and their state
#   p4-checkout | p4-editor | p4-add | p4-rm | p4-mv   change files in a workspace
#   p4-cl-create | p4-submit | p4-shelve | p4-discard | p4-status   changelists
#
# Environment (all optional):
#   GITP4V_ORG      GitHub org whose repos are listed (default: none; only GITP4V_DEPOTS)
#   GITP4V_DEPOTS   extra depots, lines "label<TAB>url"
#   GITP4V_CACHE    cache root                       (default /tmp/$USER/gitp4v)
#   GITP4V_CLONES   where clones / workspaces live   (default ~/.local/share/gitp4v/clones)
#   P4PORT, P4USER  Perforce server and user         (no P4PORT: Perforce is skipped)
#   GITP4V_TTL      shadow-tree age limit, minutes   (default 60)
#   GITP4V_LIMIT    commits shown per path           (default 50)
#   GITP4V_DIFF     diff program, run as "$GITP4V_DIFF <left> <right>"
#                   (default: git diff --no-index piped to less -R)
#   GITP4V_INTERACTIVE  set by the plugin when the terminal is handed over:
#                   errors then wait for Enter so they can be read

set -u

SELF=$(readlink -f "$0")
# yazi may be sitting in a shadow-tree dir that this script replaces (refresh,
# discard); a vanished cwd breaks git ("invalid branch name") and bash itself.
cd / || exit 1

ORG="${GITP4V_ORG:-}"
# Default is local disk: on the NFS home the same build took 15-80x longer.
CACHE="${GITP4V_CACHE:-/tmp/${USER:-user}/gitp4v}"
CLONES="${GITP4V_CLONES:-${XDG_DATA_HOME:-$HOME/.local/share}/gitp4v/clones}"
TTL="${GITP4V_TTL:-60}"
LIMIT="${GITP4V_LIMIT:-50}"
VIEW="$CACHE/view"
META="$CACHE/.meta"
HIST="$CACHE/.hist"
COMMITS="$CACHE/commits"
STATE="$CLONES/.gitp4v"
PINS="${GITP4V_PINS:-${XDG_STATE_HOME:-$HOME/.local/state}/yazi/gitp4v/pins.tsv}"
PINDIR="$CACHE/pinned"
PINCONTENT="$CACHE/.pinned-content"

[ -z "${P4PORT:-}" ] || export P4PORT
export P4USER="${P4USER:-${USER:-}}"
export P4CONFIG= P4CLIENT=

pause() { printf '\n[press Enter to return to yazi] '; read -r _ </dev/tty; }

# The program used to edit files: the first opener yazi.toml's [open] rules
# pick (the plugin passes its name in GITP4V_OPENER), else $EDITOR. The opener's
# "run" template comes from the [opener] table of yazi.toml; %s is replaced by
# the quoted file names.
open_in_editor() { # files...
    local tpl="" cfgf q f
    cfgf="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}/yazi.toml"
    if [ -n "${GITP4V_OPENER:-}" ] && [ -f "$cfgf" ]; then
        tpl=$(sed -n '/^\[opener\]/,/^\[/p' "$cfgf" \
            | sed -n -E "s/^[[:space:]]*${GITP4V_OPENER}[[:space:]]*=[[:space:]]*\\[[[:space:]]*\\{[[:space:]]*run[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\\1/p" | head -1)
    fi
    if [ -n "$tpl" ]; then
        q=""
        for f in "$@"; do q="$q $(printf '%q' "$f")"; done
        tpl=${tpl//%S/%s}
        eval "${tpl//%s/$q}"
    else
        ${EDITOR:-vi} "$@"
    fi
}
die() {
    echo "gitp4v: $*" >&2
    [ -n "${GITP4V_INTERACTIVE:-}" ] && pause
    exit 1
}

# Turn a tool's raw error text into one line the plugin can recognise:
# "AUTH-P4:", "AUTH-GH:", "AUTH-GIT:" (log in again), "DENIED:" (permissions),
# otherwise the first non-empty line unchanged.
classify_err() {
    local m="$1" first
    first=$(printf '%s\n' "$m" | grep -v '^[[:space:]]*$' | head -1)
    case "$m" in
        *P4PASSWD*|*"session has expired"*|*"ticket"*expired*|*"Perforce password"*|*"login again"*)
            echo "AUTH-P4: Perforce login needed: $first" ;;
        *"Connect to server failed"*|*"TCP connect"*|*"check \$P4PORT"*)
            echo "AUTH-P4: cannot reach the Perforce server: $first" ;;
        *"gh auth login"*|*"HTTP 401"*|*"Bad credentials"*|*"authentication token"*|*"not logged in"*|*"To authenticate"*)
            echo "AUTH-GH: GitHub authentication failed: $first" ;;
        *"Permission denied (publickey)"*|*"Authentication failed"*|*"could not read Username"*)
            echo "AUTH-GIT: git authentication failed: $first" ;;
        *"access denied"*|*"protected namespace"*|*"no permission"*|*"not permitted"*)
            echo "DENIED: $first" ;;
        *) printf '%s\n' "${first:-$m}" ;;
    esac
}

# owner/repo only: exactly one slash, no empty parts, no dot-leading or ".."
valid_nwo() {
    case "$1" in
        ''|*/*/*|/*|*/|*..*|.*|*/.*) die "bad depot name '$1'" ;;
        */*) ;;
        *) die "bad depot name '$1'" ;;
    esac
}
valid_rel() { case "$1" in ''|/*|*..*) die "bad path '$1'" ;; esac; }
mkey() { printf '%s' "${1//\//__}"; }
nwo_of_url() { printf '%s' "$1" | sed -E 's#^.*://[^/]+/##; s#\.git$##; s#/$##'; }

# shellcheck disable=SC1091
. "$(dirname "$SELF")/p4.sh"

# ---------------------------------------------------------------- depots
cmd_list() {
    {
        if [ -n "${GITP4V_DEPOTS:-}" ]; then
            printf '%s\n' "$GITP4V_DEPOTS" | while IFS=$'\t' read -r _ u; do
                [ -n "$u" ] && printf '%s\t%s\n' "$(nwo_of_url "$u")" "$u"
            done
        fi
        if [ -n "$ORG" ]; then
            gh repo list "$ORG" --limit 500 --no-archived \
                --json nameWithOwner,url --jq '.[] | "\(.nameWithOwner)\t\(.url)"' 2>/dev/null
        fi
    } | awk -F'\t' 'NF >= 2 && !seen[$1]++'
}

# open-root: create the top-level skeleton (git orgs with their repos, p4
# depots), print the view root, then "name<TAB>git|p4" per top-level entry and
# "!message" for anything that failed (so one broken service does not hide the other).
cmd_open_root() {
    local gl pl nwo owner name errf gerr perr
    mkdir -p "$VIEW" "$META" "$HIST" || die "cannot create $CACHE"
    : > "$CACHE/.kinds.tmp"
    errf=$(mktemp)

    # git (gh)
    { [ -z "${GITP4V_DEPOTS:-}" ] || printf '%s\n' "$GITP4V_DEPOTS" | while IFS=$'\t' read -r _ u; do
          [ -n "$u" ] && printf '%s\t%s\n' "$(nwo_of_url "$u")" "$u"
      done; } > "$errf.git"
    if [ -z "$ORG" ]; then
        :   # no org configured: only the extra depots (GITP4V_DEPOTS), if any
    elif gl=$(gh repo list "$ORG" --limit 500 --no-archived \
            --json nameWithOwner,url --jq '.[] | "\(.nameWithOwner)\t\(.url)"' 2>"$errf"); then
        printf '%s\n' "$gl" >> "$errf.git"
    else
        gerr=$(classify_err "$(cat "$errf")")
    fi
    while IFS=$'\t' read -r nwo _; do
        case "$nwo" in ''|*/*/*|*..*|.*|*/.*) continue ;; esac
        mkdir -p "$VIEW/$nwo"
        owner=${nwo%%/*}
        grep -q "^$owner	" "$CACHE/.kinds.tmp" || printf '%s\tgit\n' "$owner" >> "$CACHE/.kinds.tmp"
    done < "$errf.git"
    rm -f "$errf.git"

    # perforce
    if [ -z "${P4PORT:-}" ]; then
        :   # no Perforce server configured
    elif pl=$(p4_depots 2>"$errf"); then
        while IFS=$'\t' read -r name _; do
            [ -n "$name" ] || continue
            grep -q "^$name	" "$CACHE/.kinds.tmp" && continue
            mkdir -p "$VIEW/$name"
            printf '%s\tp4\n' "$name" >> "$CACHE/.kinds.tmp"
        done <<< "$pl"
    else
        perr=$(classify_err "$(cat "$errf")")
    fi
    rm -f "$errf"
    mv "$CACHE/.kinds.tmp" "$CACHE/.kinds"

    echo "$VIEW"
    cat "$CACHE/.kinds"
    [ -z "${gerr:-}" ] || printf '!%s\n' "$gerr"
    [ -z "${perr:-}" ] || printf '!%s\n' "$perr"
    return 0
}

# kind <name>: git or p4 for a top-level entry of the view root.
cmd_kind() {
    local name="${1:-}"
    [ -f "$CACHE/.kinds" ] || cmd_open_root >/dev/null
    awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$CACHE/.kinds"
}

# lsdir <owner/path...>: contents of a shadow folder, for the preview pane.
# Perforce folders are listed on demand; a git repo that was never opened says so.
cmd_lsdir() {
    local rest="${1:-}" owner dir
    case "$rest" in ''|*..*|/*) die "bad path '$rest'" ;; esac
    rest=${rest%/}
    owner=${rest%%/*}
    dir="$VIEW/$rest"
    if [ "$(cmd_kind "$owner")" = p4 ]; then
        cmd_p4_list "//$rest" >/dev/null || exit 1
    else
        case "$rest" in
            */*/*) ;;                                  # inside a repo: its tree exists
            */*) [ -f "$META/$(mkey "$rest")" ] || { echo NOTLOADED; return 0; } ;;
        esac
    fi
    ls -1 -p --group-directories-first -- "$dir" 2>/dev/null | head -n 400
}

# Interactive logins (the plugin offers these when it sees an AUTH error).
cmd_p4_login() { p4 login; local rc=$?; pause; return $rc; }
cmd_gh_login() { gh auth login; local rc=$?; pause; return $rc; }

# Load nwo/branch/url for a repo from its meta file.
load_meta() {
    local f="$META/$(mkey "$1")"
    [ -f "$f" ] || die "unknown depot '$1' (open it first)"
    # shellcheck disable=SC1090
    . "$f"
}

# ------------------------------------------------- local state (clone/branch)
# st_dir / st_branch: the repo's active clone and review branch.
st_dir=""; st_branch=""
state_load() {
    st_dir=""; st_branch=""
    local f="$STATE/$(mkey "$nwo")"
    # shellcheck disable=SC1090
    [ -f "$f" ] && . "$f"
    return 0
}
state_save() { # dir branch
    mkdir -p "$STATE" || die "cannot create $STATE"
    printf 'st_dir=%q\nst_branch=%q\n' "$1" "$2" > "$STATE/$(mkey "$nwo")"
}
clone_dir() { state_load; echo "$st_dir"; }

dirty_count() { git -C "$1" status --porcelain | wc -l; }

# Prints the repo's review branch if one has been started, else nothing.
review_branch() {
    state_load
    [ -n "$st_dir" ] || return 0
    # The clone was deleted behind our back: forget it (the next change starts
    # a fresh branch and clone) instead of reporting it as missing.
    if [ ! -d "$st_dir/.git" ]; then rm -f "$STATE/$(mkey "$nwo")"; return 0; fi
    git -C "$st_dir" show-ref -q --verify "refs/heads/$st_branch" && echo "$st_branch"
    return 0
}

# Commits on the review branch not on origin/<default>.
ahead_count() { # dir branch
    git -C "$1" rev-list --count "origin/$branch..$2" 2>/dev/null || echo 0
}

rebase_in_progress() { [ -d "$1/.git/rebase-merge" ] || [ -d "$1/.git/rebase-apply" ]; }

# Require a started review branch, make sure it is checked out, print it.
need_branch() {
    local dir b cur
    b=$(review_branch)
    [ -n "$b" ] || die "no review branch started for $nwo"
    dir=$(clone_dir)
    rebase_in_progress "$dir" && die "a rebase is in progress in $dir; finish it there (git rebase --continue) and retry"
    cur=$(git -C "$dir" symbolic-ref --short -q HEAD || true)
    if [ "$cur" != "$b" ]; then
        [ "$(dirty_count "$dir")" -eq 0 ] || die "clone is on '$cur' with uncommitted changes; resolve in $dir"
        git -C "$dir" switch -q "$b" || die "cannot switch to $b"
    fi
    echo "$b"
}

# One commit per branch: after committing, no more edits until the PR is done.
block_if_committed() { # dir branch
    [ "$(ahead_count "$1" "$2")" -eq 0 ] || die "already committed on $2; open the pull request first"
}

# Like load_meta, but works for a repo that was never opened (e.g. a pinned
# file): falls back to asking GitHub for the default branch.
light_meta() {
    if [ -f "$META/$(mkey "$1")" ]; then load_meta "$1"; return; fi
    nwo="$1"
    branch=$(gh api "repos/$1" --jq .default_branch 2>/dev/null) || die "cannot query $1"
    [ -n "$branch" ] || die "cannot query $1"
}

# ------------------------------------------------------------- shadow tree
# Re-apply the review branch's changes to a freshly built placeholder tree so
# added files show up and deleted ones stay gone.
overlay_local() { # root
    local root="$1" dir b base st p old
    b=$(review_branch); [ -n "$b" ] || return 0
    dir=$(clone_dir)
    base=$(git -C "$dir" merge-base HEAD "origin/$branch" 2>/dev/null) || return 0
    changes_list "$dir" "$base" | while IFS=$'\t' read -r st p old; do
        case "$st" in
            D) rm -rf -- "${root:?}/$p" ;;
            R) rm -rf -- "${root:?}/$old"; mkdir -p "$root/$(dirname "$p")"; [ -e "$root/$p" ] || : > "$root/$p" ;;
            *) mkdir -p "$root/$(dirname "$p")"; [ -e "$root/$p" ] || : > "$root/$p" ;;
        esac
    done
}

cmd_open() {
    local nwo="${1:-}" force="${2:-}" url branch root tmp lst trunc=0
    valid_nwo "$nwo"
    root="$VIEW/$nwo"
    mkdir -p "$VIEW" "$META" "$HIST" || die "cannot create $CACHE"
    [ -n "$force" ] && rm -f "$HIST/$(mkey "$nwo")."*

    if [ -z "$force" ] && [ -f "$META/$(mkey "$nwo")" ] \
        && [ -n "$(ls -A "$root" 2>/dev/null)" ] \
        && [ -n "$(find "$META/$(mkey "$nwo")" -mmin "-$TTL" 2>/dev/null)" ]; then
        echo "$root"; return 0
    fi

    # Repo info and the full tree are independent API calls: run them together.
    tmp=$(mktemp -d "$VIEW/.build.XXXXXX") || die "mktemp failed"
    lst=$(mktemp "$VIEW/.paths.XXXXXX") || die "mktemp failed"
    gh api "repos/$nwo" --jq '[.default_branch, .html_url] | @tsv' > "$tmp.info" 2>/dev/null &
    gh api "repos/$nwo/git/trees/HEAD?recursive=1" --jq \
        '(if .truncated then "truncated\t-" else empty end), (.tree[] | "\(.type)\t\(.path)")' \
        > "$lst" 2>/dev/null &
    wait
    IFS=$'\t' read -r branch url < "$tmp.info"
    rm -f "$tmp.info"
    if [ -z "$branch" ] || [ ! -s "$lst" ]; then
        rm -rf "$tmp" "$lst"; die "cannot query $nwo"
    fi
    grep -q '^truncated' "$lst" && trunc=1

    # One mkdir / touch per few thousand paths instead of one fork per path
    # (per-file forks made big repos take over a minute). Unsafe paths skipped.
    awk -F'\t' '$1 == "tree" && $2 !~ /(^|\/)\.\.(\/|$)/ && $2 !~ /^\// { printf "%s\0", $2 }' "$lst" \
        | (cd "$tmp" && xargs -0 -r mkdir -p --)
    awk -F'\t' '$1 == "blob" && $2 !~ /(^|\/)\.\.(\/|$)/ && $2 !~ /^\// { printf "%s\0", $2 }' "$lst" \
        | (cd "$tmp" && xargs -0 -r touch --)
    rm -f "$lst"
    overlay_local "$tmp"

    # Replace the old tree only after the new one is fully built.
    case "$root" in "$VIEW"/?*/?*) rm -rf "$root" ;; *) die "refusing to remove $root" ;; esac
    mkdir -p "$(dirname "$root")"
    mv "$tmp" "$root" || die "cannot install shadow tree"
    printf 'nwo=%q\nbranch=%q\nurl=%q\ntruncated=%q\n' "$nwo" "$branch" "$url" "$trunc" \
        > "$META/$(mkey "$nwo")"
    echo "$root"
}

# ----------------------------------------------------------------- history
cmd_hist() {
    local nwo="${1:-}" rel="${2:-}" key out
    valid_nwo "$nwo"
    load_meta "$nwo"
    mkdir -p "$HIST"
    key=$(printf '%s\0%s' "$nwo" "$rel" | cksum | cut -d' ' -f1)
    out="$HIST/$(mkey "$nwo").$key"
    if [ -z "$(find "$out" -mmin -10 2>/dev/null)" ]; then
        if gh api "repos/$nwo/commits?sha=$branch&per_page=$LIMIT${rel:+&path=$rel}" --jq \
            '.[] | [.sha[0:7], (.commit.author.date[0:10]), (.commit.author.name // "?"), (.commit.message | split("\n")[0])] | @tsv' \
            > "$out.tmp" 2>/dev/null; then
            mv "$out.tmp" "$out"
        else
            rm -f "$out.tmp"; die "history query failed"
        fi
    fi
    cat "$out"
}

fetch_blob() { # ref rel dest
    gh api -H "Accept: application/vnd.github.raw" "repos/$nwo/contents/$2?ref=$1" > "$3" 2>/dev/null \
        || : > "$3"
}

# diffv <nwo> <relpath> <left-sha> <left-idx> <right-sha> <right-idx>
# The files are named <filename>#<index> so the diff shows which is which.
cmd_diffv() {
    local nwo="${1:-}" rel="${2:-}" a="${3:-}" ai="${4:-}" b="${5:-}" bi="${6:-}" tmp base fa fb
    valid_nwo "$nwo"; load_meta "$nwo"; valid_rel "$rel"
    [ -n "$a" ] && [ -n "$b" ] || die "need two versions"
    base=$(basename "$rel"); fa="$base#$ai"; fb="$base#$bi"
    tmp=$(mktemp -d) || die "mktemp failed"
    trap "rm -rf '$tmp'" EXIT   # expand now: $tmp is function-local
    echo "gitp4v: fetching two versions of $rel ..." >&2
    fetch_blob "$a" "$rel" "$tmp/$fa"
    fetch_blob "$b" "$rel" "$tmp/$fb"
    if [ -n "${GITP4V_DIFF:-}" ]; then
        (cd "$tmp" && $GITP4V_DIFF "$fa" "$fb")
    else
        { echo "# $nwo:$rel   left=$a ($ai)  right=$b ($bi)"
          (cd "$tmp" && git diff --no-index --color=always -- "$fa" "$fb"); } | less -R
    fi
}

# histdir <nwo> <relpath>: build a directory of placeholder files, one per
# commit touching the file, so yazi can list/select them. Names are
# "IDX sha date author  subject"; IDX is larger for newer commits (the plugin
# sorts the list descending, so the newest is at the top).
cmd_histdir() {
    local nwo="${1:-}" rel="${2:-}" dir list total n=0 w sha date author subj name
    valid_nwo "$nwo"; load_meta "$nwo"; valid_rel "$rel"
    list=$(cmd_hist "$nwo" "$rel") || exit 1
    total=$(printf '%s\n' "$list" | grep -c .)
    w=${#total}; [ "$w" -lt 2 ] && w=2
    dir="$COMMITS/$nwo/$rel"
    case "$dir" in "$COMMITS"/?*/?*/?*) rm -rf "$dir" ;; *) die "refusing to remove $dir" ;; esac
    mkdir -p "$dir" || die "cannot create $dir"
    while IFS=$'\t' read -r sha date author subj; do
        [ -n "$sha" ] || continue
        n=$((n + 1))
        name=$(printf '%0*d %s %s  %s  %s' "$w" "$((total - n + 1))" "$sha" "$date" "$author" "$subj")
        name=${name//\//-}
        : > "$dir/${name:0:150}"
    done <<< "$list"
    echo "$dir"
}

# show <nwo> <sha> <relpath>: commit header, message and this file's patch.
cmd_show() {
    local nwo="${1:-}" sha="${2:-}" rel="${3:-}" key out
    valid_nwo "$nwo"; load_meta "$nwo"; valid_rel "$rel"
    case "$sha" in ''|*[!0-9a-f]*) die "bad commit '$sha'" ;; esac
    mkdir -p "$HIST"
    key=$(printf '%s\0%s\0%s' "$nwo" "$sha" "$rel" | cksum | cut -d' ' -f1)
    out="$HIST/$(mkey "$nwo").show.$key"   # commits are immutable: cache forever
    if [ ! -s "$out" ]; then
        REL="$rel" gh api "repos/$nwo/commits/$sha" --jq \
            '"commit \(.sha)\nAuthor: \(.commit.author.name)\nDate:   \(.commit.author.date)\n\n\(.commit.message)\n\n" + ([.files[] | select(.filename == $ENV.REL) | "--- \(.filename) (\(.status), +\(.additions) -\(.deletions))\n\(.patch // "(no textual patch)")"] | join("\n"))' \
            > "$out.tmp" 2>/dev/null && mv "$out.tmp" "$out" || { rm -f "$out.tmp"; die "commit query failed"; }
    fi
    cat "$out"
}

cmd_read() {
    local nwo="${1:-}" rel="${2:-}" ref idx="${4:-}" tmp f ed
    valid_nwo "$nwo"; light_meta "$nwo"; valid_rel "$rel"
    ref="${3:-$branch}"
    tmp=$(mktemp -d) || die "mktemp failed"
    trap "rm -rf '$tmp'" EXIT   # expand now: $tmp is function-local
    f="$tmp/$(basename "$rel")${idx:+#$idx}"
    echo "gitp4v: fetching $rel@${ref:0:12} ..." >&2
    fetch_blob "$ref" "$rel" "$f"
    chmod 444 "$f"
    ed="${EDITOR:-vi}"
    case "$(basename "${ed%% *}")" in
        vi|vim|nvim|view) $ed -R "$f" ;;
        *) ${PAGER:-less} "$f" ;;
    esac
}

# ----------------------------------------------- local clone / review branch
# All prompting (branch name, commit message, PR text) is done by the plugin;
# these commands take the answers as arguments.

# branch <nwo>: print the active review branch, empty if none yet.
cmd_branch() {
    local nwo="${1:-}"
    valid_nwo "$nwo"; load_meta "$nwo"
    review_branch
}

# Make paths part of a sparse clone's working tree (fetching their contents).
# Clones made before sparse checkout existed have everything, so nothing to do.
sp_add() { # dir path...
    local dir="$1" p esc; shift
    [ "$(git -C "$dir" config --get core.sparseCheckout)" = true ] || return 0
    for p in "$@"; do
        esc=$(printf '%s' "$p" | sed -e 's/[][*?\\]/\\&/g')
        git -C "$dir" sparse-checkout add "/$esc" >/dev/null 2>&1 || die "cannot fetch $p from the repo"
    done
}

# Where a branch's clone lives: $CLONES/<repo>-<branch> (slashes become _).
branch_clone_dir() { # nwo name
    local safe=${2//\//_}
    echo "$CLONES/${1#*/}-$safe"
}

# plan-branch <nwo> <name>: print "<clone dir><TAB>new|existing" so the plugin
# can say it is about to clone.
cmd_plan_branch() {
    local nwo="${1:-}" name="${2:-}" dir
    valid_nwo "$nwo"; load_meta "$nwo"
    git check-ref-format --branch "$name" >/dev/null 2>&1 || die "invalid branch name '$name'"
    dir=$(branch_clone_dir "$nwo" "$name")
    if [ -d "$dir/.git" ]; then printf '%s\texisting\n' "$dir"; else printf '%s\tnew\n' "$dir"; fi
}

# start-branch <nwo> <name>: clone into $CLONES/<repo>-<branch> and start the branch.
cmd_start_branch() {
    local nwo="${1:-}" name="${2:-}" dir created=""
    valid_nwo "$nwo"; load_meta "$nwo"
    git check-ref-format --branch "$name" >/dev/null 2>&1 || die "invalid branch name '$name'"
    [ "$name" != "$branch" ] || die "pick a branch other than the default ($branch)"
    dir=$(branch_clone_dir "$nwo" "$name")
    if [ -d "$dir/.git" ]; then
        git -C "$dir" remote get-url origin 2>/dev/null | grep -qi -- "$nwo" \
            || die "$dir is a clone of a different repo"
    else
        mkdir -p "$CLONES" || die "cannot create $CLONES"
        echo "Cloning $nwo into $dir ..." >&2
        # Fast clone: full history but no file contents (--filter=blob:none), and
        # no checkout. Only the files you edit are fetched and checked out, via a
        # sparse-checkout that grows as you edit (see sp_add). A 170 MB repo goes
        # from about 11 s to about 1 s.
        gh repo clone "$nwo" "$dir" -- --filter=blob:none --no-checkout --single-branch >&2 \
            || { rm -rf -- "$dir"; die "clone failed"; }
        # (--no-checkout leaves an empty index; checking the branch out with an
        # empty sparse set fills the index without writing any files)
        { git -C "$dir" sparse-checkout set --no-cone '/.gitp4v-sparse-empty' \
            && git -C "$dir" checkout -q "$branch"; } >&2 \
            || { rm -rf -- "$dir"; die "sparse-checkout setup failed"; }
        created=1
    fi
    git -C "$dir" fetch -q origin || { [ -n "$created" ] && rm -rf -- "$dir"; die "fetch failed"; }
    [ "$(dirty_count "$dir")" -eq 0 ] || die "clone has uncommitted changes; resolve in $dir first"
    if git -C "$dir" show-ref -q --verify "refs/heads/$name"; then
        git -C "$dir" switch -q "$name" || die "switch failed"
    else
        git -C "$dir" switch -q -c "$name" "origin/$branch" || die "cannot create $name"
    fi
    state_save "$dir" "$name"
    echo "$name"
}

# edit <nwo> <relpath>...: open one or more files from the clone's review branch.
cmd_edit() {
    local nwo="${1:-}" dir b rel files=()
    valid_nwo "$nwo"; load_meta "$nwo"; shift
    [ $# -gt 0 ] || die "no files given"
    b=$(need_branch) || exit 1
    dir=$(clone_dir)
    block_if_committed "$dir" "$b"
    for rel in "$@"; do
        valid_rel "$rel"
        sp_add "$dir" "$rel"
        [ -f "$dir/$rel" ] || die "$rel is not a file on the review branch"
        files+=("$dir/$rel")
    done
    open_in_editor "${files[@]}"
}

# rm <nwo> <relpath>: delete a file or directory on the review branch.
cmd_rm() {
    local nwo="${1:-}" rel="${2:-}" dir b
    valid_nwo "$nwo"; load_meta "$nwo"; valid_rel "$rel"
    b=$(need_branch) || exit 1
    dir=$(clone_dir)
    block_if_committed "$dir" "$b"
    sp_add "$dir" "$rel"
    git -C "$dir" rm -q -r -f -- "$rel" || die "git rm failed for $rel"
    rm -rf -- "${VIEW:?}/$nwo/$rel"
    echo "Deleted $rel"
}

# add <nwo> <relpath>: create an empty file on the review branch; show a placeholder.
cmd_add() {
    local nwo="${1:-}" rel="${2:-}" dir b
    valid_nwo "$nwo"; load_meta "$nwo"; valid_rel "$rel"
    case "$rel" in */) die "file name expected, not a directory" ;; esac
    b=$(need_branch) || exit 1
    dir=$(clone_dir)
    block_if_committed "$dir" "$b"
    sp_add "$dir" "$rel"
    [ ! -e "$dir/$rel" ] || die "$rel already exists"
    mkdir -p "$dir/$(dirname "$rel")" && : > "$dir/$rel" || die "cannot create $rel"
    mkdir -p "$VIEW/$nwo/$(dirname "$rel")" && : > "$VIEW/$nwo/$rel"
    echo "Added $rel"
}

# mv <nwo> <old> <new>: rename a file or directory on the review branch.
cmd_mv() {
    local nwo="${1:-}" old="${2:-}" new="${3:-}" dir b
    valid_nwo "$nwo"; load_meta "$nwo"; valid_rel "$old"; valid_rel "$new"
    b=$(need_branch) || exit 1
    dir=$(clone_dir)
    block_if_committed "$dir" "$b"
    sp_add "$dir" "$old" "$new"
    [ ! -e "$dir/$new" ] || die "$new already exists"
    mkdir -p "$dir/$(dirname "$new")"
    git -C "$dir" mv -- "$old" "$new" || die "git mv failed"
    mkdir -p "$VIEW/$nwo/$(dirname "$new")"
    mv -- "$VIEW/$nwo/$old" "$VIEW/$nwo/$new" 2>/dev/null || : > "$VIEW/$nwo/$new"
    echo "Renamed $old to $new"
}

# commit <nwo> <message>: commit everything changed in the clone.
cmd_commit() {
    local nwo="${1:-}" msg="${2:-}" dir b
    valid_nwo "$nwo"; load_meta "$nwo"
    [ -n "$msg" ] || die "empty commit message"
    b=$(need_branch) || exit 1
    dir=$(clone_dir)
    block_if_committed "$dir" "$b"
    [ "$(dirty_count "$dir")" -gt 0 ] || die "nothing to commit"
    git -C "$dir" add -A || die "git add failed"
    git -C "$dir" commit -q -m "$msg" || die "commit failed"
    echo "Committed: $(git -C "$dir" log -1 --format='%h %s')"
}

# pr-info <nwo>: key<TAB>value lines (branch, dir, dirty, ahead, subject, pr, prstate).
cmd_pr_info() {
    local nwo="${1:-}" dir b pr
    valid_nwo "$nwo"; load_meta "$nwo"
    b=$(review_branch)
    printf 'branch\t%s\n' "$b"
    [ -n "$b" ] || return 0
    dir=$(clone_dir)
    printf 'dir\t%s\n' "$dir"
    printf 'dirty\t%s\n' "$(dirty_count "$dir")"
    printf 'ahead\t%s\n' "$(ahead_count "$dir" "$b")"
    printf 'subject\t%s\n' "$(git -C "$dir" log -1 --format=%s "$b")"
    pr=$(cd "$dir" && gh pr view "$b" --json url,state --jq '[.url, .state] | @tsv' 2>/dev/null)
    printf 'pr\t%s\n' "${pr%%$'\t'*}"
    printf 'prstate\t%s\n' "${pr#*$'\t'}"
}

# pr <nwo> <title> <body>: rebase onto the default branch if it moved, push the
# review branch and open (or reuse) a PR. A rebase conflict is left in place in
# the clone for the user to resolve.
cmd_pr() {
    local nwo="${1:-}" title="${2:-}" body="${3:-}" dir b url forced=0
    valid_nwo "$nwo"; load_meta "$nwo"
    [ -n "$title" ] || die "empty PR title"
    b=$(need_branch) || exit 1
    dir=$(clone_dir)
    [ "$(ahead_count "$dir" "$b")" -gt 0 ] || die "nothing committed on $b yet"
    [ "$(dirty_count "$dir")" -eq 0 ] || echo "gitp4v: note: uncommitted changes are not in the PR" >&2

    git -C "$dir" fetch -q origin || die "fetch failed"
    if ! git -C "$dir" merge-base --is-ancestor "origin/$branch" "$b"; then
        if ! git -C "$dir" rebase -q "origin/$branch" >/dev/null 2>&1; then
            die "rebase onto origin/$branch hit conflicts. Go to $dir, fix them (git status, git rebase --continue), then open the pull request again"
        fi
        forced=1
    fi
    if [ "$forced" -eq 1 ]; then
        git -C "$dir" push -q -u --force-with-lease origin "$b" >&2 || die "push failed"
    else
        git -C "$dir" push -q -u origin "$b" >&2 || die "push failed"
    fi
    url=$(cd "$dir" && gh pr view "$b" --json url --jq .url 2>/dev/null)
    if [ -z "$url" ]; then
        url=$(cd "$dir" && gh pr create --base "$branch" --head "$b" --title "$title" --body "$body") \
            || die "pr create failed"
    fi
    echo "$url"
}

# discard <nwo>: throw away the local review branch and all its changes.
# (A remote copy of the branch, if it was pushed, is left alone.)
cmd_discard() {
    local nwo="${1:-}" dir b
    valid_nwo "$nwo"; load_meta "$nwo"
    b=$(review_branch)
    [ -n "$b" ] || die "no review branch to discard"
    dir=$(clone_dir)
    remove_clone "$dir"
    rm -f "$STATE/$(mkey "$nwo")"
    echo "Discarded local branch $b and deleted its clone ($(basename "$dir"))"
}

# Delete a clone directory (only ever something under $CLONES that is a git
# clone, so a bad argument cannot remove anything else).
remove_clone() { # dir
    local dir="$1"
    case "$dir" in "$CLONES"/?*) ;; *) die "refusing to remove $dir (outside $CLONES)" ;; esac
    [ -d "$dir/.git" ] || return 0
    rm -rf -- "$dir" || die "cannot remove $dir"
}

# clean-clone <dir>: delete the clone of a branch whose PR is done.
cmd_clean_clone() { remove_clone "${1:-}"; }

# ------------------------------------------------------------ changes popup
# Changed files vs the point where the review branch left the default branch
# (committed + staged + unstaged + new): "<A|M|D|R><TAB>path<TAB>old-path".
changes_list() { # dir base
    git -C "$1" -c core.quotepath=false diff --name-status -M "$2" \
        | while IFS=$'\t' read -r st a b; do
            case "$st" in
                R*) printf 'R\t%s\t%s\n' "$b" "$a" ;;
                A)  printf 'A\t%s\t\n' "$a" ;;
                D)  printf 'D\t%s\t\n' "$a" ;;
                *)  printf 'M\t%s\t\n' "$a" ;;
            esac
        done
    git -C "$1" -c core.quotepath=false ls-files --others --exclude-standard \
        | while IFS= read -r p; do printf 'A\t%s\t\n' "$p"; done
}

# status-data <nwo>: data for the changed-files popup. First line
# "H<TAB>committed(0|1)<TAB>text", then "<A|M|D|R><TAB>path<TAB>old-path" per file.
cmd_status_data() {
    local nwo="${1:-}" dir b base ahead
    valid_nwo "$nwo"; load_meta "$nwo"
    b=$(review_branch); [ -n "$b" ] || die "no review branch started for $nwo"
    dir=$(clone_dir)
    ahead=$(ahead_count "$dir" "$b")
    base=$(git -C "$dir" merge-base HEAD "origin/$branch" 2>/dev/null || echo HEAD)
    if [ "$ahead" -gt 0 ]; then
        printf 'H\t1\t%s (committed)\n' "$b"
    else
        printf 'H\t0\t%s (not committed)\n' "$b"
    fi
    changes_list "$dir" "$base"
}

# status-diff <nwo> <marker> <path> <old-path>: show the diff for one entry.
cmd_status_diff() {
    local nwo="${1:-}" st="${2:-}" p="${3:-}" old="${4:-}" dir b base
    valid_nwo "$nwo"; load_meta "$nwo"
    [ -n "$p" ] || return 0
    b=$(review_branch); dir=$(clone_dir)
    base=$(git -C "$dir" merge-base HEAD "origin/$branch" 2>/dev/null || echo HEAD)
    if [ "$st" = "A" ] && ! git -C "$dir" ls-files --error-unmatch -- "$p" >/dev/null 2>&1 \
        && git -C "$dir" ls-files --others --exclude-standard -- "$p" | grep -q .; then
        (cd "$dir" && git diff --no-index --color=always -- /dev/null "$p"; true) | less -R
    elif [ -n "$old" ]; then
        git -C "$dir" diff -M --color=always "$base" -- "$old" "$p" | less -R
    else
        git -C "$dir" diff --color=always "$base" -- "$p" | less -R
    fi
}

# discard-file <nwo> <marker> <path> <old-path>: throw away our changes to one
# file (only while uncommitted). The plugin asks for confirmation first.
cmd_discard_file() {
    local nwo="${1:-}" st="${2:-}" p="${3:-}" old="${4:-}" dir b
    valid_nwo "$nwo"; load_meta "$nwo"; valid_rel "$p"
    b=$(need_branch) || exit 1
    dir=$(clone_dir)
    block_if_committed "$dir" "$b"
    case "$st" in
        M|D) git -C "$dir" restore -q --source=HEAD --staged --worktree -- "$p" ;;
        A)   git -C "$dir" rm -q -f -- "$p" 2>/dev/null || rm -f -- "${dir:?}/$p" ;;
        R)   git -C "$dir" restore -q --source=HEAD --staged --worktree -- "$old"
             git -C "$dir" rm -q -f -- "$p" 2>/dev/null || rm -f -- "${dir:?}/$p" ;;
    esac
    echo "Discarded your changes to $p"
}

# ------------------------------------------------------------- pinned files
# The pin list lives in yazi's state dir (it is user data, not a cache). Each
# line: kind<TAB>target<TAB>saved-path<TAB>epoch
#   kind local: target is an absolute path, opened through a symlink
#   kind depot: target is "owner/repo:relpath", opened as the repo's current
#               version (view only)
# saved-path is what the yazi header showed when the file was pinned.

# pin-toggle <kind> <target> <saved-path>: pin it, or unpin if already pinned.
cmd_pin_toggle() {
    local kind="${1:-}" target="${2:-}" saved="${3:-}"
    case "$kind" in local|depot|p4) ;; *) die "bad pin kind '$kind'" ;; esac
    [ -n "$target" ] || die "nothing to pin"
    mkdir -p "$(dirname "$PINS")" || die "cannot create $(dirname "$PINS")"
    touch "$PINS"
    if K="$kind" T="$target" awk -F'\t' '$1 == ENVIRON["K"] && $2 == ENVIRON["T"] { f = 1 } END { exit !f }' "$PINS"; then
        K="$kind" T="$target" awk -F'\t' '!($1 == ENVIRON["K"] && $2 == ENVIRON["T"])' "$PINS" > "$PINS.tmp" \
            && mv "$PINS.tmp" "$PINS"
        echo unpinned
    else
        printf '%s\t%s\t%s\t%s\n' "$kind" "$target" "$saved" "$(date +%s)" >> "$PINS"
        echo pinned
    fi
}

# pin-build: rebuild the pinned-files directory (one symlink per pin, depot
# files fetched fresh from the repo's default branch). Prints the directory,
# then "name<TAB>kind<TAB>target<TAB>saved-path" per pin.
cmd_pin_build() {
    local kind target saved when name base n src nwo rel
    local -A used=()
    mkdir -p "$PINDIR" "$PINCONTENT" || die "cannot create $CACHE"
    find "$PINDIR" -mindepth 1 -delete
    find "$PINCONTENT" -mindepth 1 -delete
    echo "$PINDIR"
    [ -s "$PINS" ] || return 0
    while IFS=$'\t' read -r kind target saved when; do
        [ -n "$target" ] || continue
        case "$kind" in
            local)
                src="$target"; base=$(basename "$target") ;;
            depot)
                nwo=${target%%:*}; rel=${target#*:}
                case "$rel" in ''|/*|*..*) continue ;; esac
                src="$PINCONTENT/$(mkey "$nwo")/$rel"; base=$(basename "$rel")
                ( valid_nwo "$nwo"; light_meta "$nwo"
                  mkdir -p "$(dirname "$src")"
                  fetch_blob "$branch" "$rel" "$src"; chmod 444 "$src" ) &
                ;;
            p4)
                case "$target" in //?*) ;; *) continue ;; esac
                src="$PINCONTENT/p4/${target#//}"; base=$(basename "$target")
                ( mkdir -p "$(dirname "$src")"; p4_fetch "$target" "" "$src"; chmod 444 "$src" ) &
                ;;
            *) continue ;;
        esac
        name="$base"; n=1
        while [ -n "${used[$name]:-}" ]; do n=$((n + 1)); name="$base ($n)"; done
        used[$name]=1
        ln -s -- "$src" "$PINDIR/$name"
        printf '%s\t%s\t%s\t%s\n' "$name" "$kind" "$target" "$saved"
    done < "$PINS"
    wait
}

# --------------------------------------------------------------- dispatch
cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
    list)           cmd_list ;;
    open-root)      cmd_open_root ;;
    open)           cmd_open "$@" ;;
    hist)           cmd_hist "$@" ;;
    histdir)        cmd_histdir "$@" ;;
    show)           cmd_show "$@" ;;
    diffv)          cmd_diffv "$@" ;;
    read)           cmd_read "$@" ;;
    branch)         cmd_branch "$@" ;;
    kind)           cmd_kind "$@" ;;
    p4-login)       cmd_p4_login ;;
    gh-login)       cmd_gh_login ;;
    p4-list)        cmd_p4_list "$@" ;;
    p4-hist)        cmd_p4_hist "$@" ;;
    p4-histdir)     cmd_p4_histdir "$@" ;;
    p4-show)        cmd_p4_show "$@" ;;
    p4-print)       cmd_p4_print "$@" ;;
    p4-diffv)       cmd_p4_diffv "$@" ;;
    p4-ws-find)     cmd_p4_ws_find "$@" ;;
    p4-ws-create)   cmd_p4_ws_create "$@" ;;
    p4-info)        cmd_p4_info "$@" ;;
    p4-checkout)    cmd_p4_checkout "$@" ;;
    p4-editor)      cmd_p4_editor "$@" ;;
    p4-add)         cmd_p4_add "$@" ;;
    p4-rm)          cmd_p4_rm "$@" ;;
    p4-mv)          cmd_p4_mv "$@" ;;
    p4-cl-create)   cmd_p4_cl_create "$@" ;;
    p4-submit)      cmd_p4_submit "$@" ;;
    p4-shelve)      cmd_p4_shelve "$@" ;;
    p4-discard)     cmd_p4_discard "$@" ;;
    p4-status-data) cmd_p4_status_data "$@" ;;
    p4-ws-delete)   cmd_p4_ws_delete "$@" ;;
    clean-clone)    cmd_clean_clone "$@" ;;
    lsdir)          cmd_lsdir "$@" ;;
    p4-status-diff)    cmd_p4_status_diff "$@" ;;
    p4-revert-file) cmd_p4_revert_file "$@" ;;
    plan-branch)    cmd_plan_branch "$@" ;;
    start-branch)   cmd_start_branch "$@" ;;
    pin-toggle)     cmd_pin_toggle "$@" ;;
    pin-build)      cmd_pin_build "$@" ;;
    edit)           cmd_edit "$@" ;;
    rm)             cmd_rm "$@" ;;
    add)            cmd_add "$@" ;;
    mv)             cmd_mv "$@" ;;
    commit)         cmd_commit "$@" ;;
    pr-info)        cmd_pr_info "$@" ;;
    pr)             cmd_pr "$@" ;;
    discard)        cmd_discard "$@" ;;
    status-data)    cmd_status_data "$@" ;;
    status-diff)    cmd_status_diff "$@" ;;
    discard-file)   cmd_discard_file "$@" ;;
    *) sed -n '2,/^$/p' "$SELF" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
