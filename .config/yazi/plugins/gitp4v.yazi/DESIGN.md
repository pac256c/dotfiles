# gitp4v: design notes

Quick reference: open `cheatsheet.html` in a browser. This file explains how the gitp4v plugin
works and why it was built the way it is. Install and dependencies are in `README.md`, the day-to-day guide is `notes.md` (same folder).

## What it is

gitp4v turns yazi into a small p4v-style client for two kinds of "depots":

- GitHub (Enterprise) repos of a configured org, through the `gh` CLI
- Perforce depots of a configured server, through the `p4` CLI

You browse them in yazi's normal panes, see per-file history in the right pane, view and diff
versions, edit through a local clone or workspace, and pin files for quick access.

## Files

Everything is in `~/.config/yazi/plugins/gitp4v.yazi/`:

| File | Role |
|------|------|
| `main.lua` | Plugin entry: yazi state, header/icon/history-color overrides, previewer, key actions, git flows, pins |
| `p4.lua` | Perforce flows (workspaces, CL popups). Required by `main.lua` as `gitp4v.p4` |
| `config.lua` | Generic defaults and the option list. Site-specific values (org, p4 server/user, clones folder, diff program) live in your `init.lua` as `gitp4v_opts`, outside this folder; `setup()` merges them over these |
| `gitp4v.sh` | Backend: git/gh commands, shared helpers, pins, dispatch |
| `p4.sh` | Backend: p4 commands (sourced by `gitp4v.sh`) |
| `keymap.toml`, `yazi.toml` | Sources of the key bindings and previewer rules (not read by yazi from here) |
| `install.sh` | Copies those two files, plus a one-line `init.lua` hook, into your yazi config as marked blocks |
| `README.md`, `notes.md`, `DESIGN.md`, `cheatsheet.html` | Docs (install / usage / design / quick reference) |

Your own yazi config only holds the marked blocks written by `install.sh`
(`# >>> gitp4v ... <<< gitp4v` in `keymap.toml` and `yazi.toml`, the same in `init.lua` with `--`
comments; your settings table sits above the `init.lua` block, outside it). yazi has no include or import for its toml files, so packaging is "generate the blocks":
edit the source files here and re-run `install.sh`. `yazi.toml` is written only if it has no other
`[plugin]` table (a second one would be invalid TOML); otherwise the script says so.

Runtime data:

| Path | Contents |
|------|----------|
| `/tmp/$USER/gitp4v/view/` | Shadow tree of the depots (placeholder files) |
| `/tmp/$USER/gitp4v/commits/` | History lists (one placeholder per revision) |
| `/tmp/$USER/gitp4v/pinned/` | Pinned-files list (symlinks) |
| `/tmp/$USER/gitp4v/.meta .hist .kinds .pinned-content` | Metadata, history cache, top-level kinds, fetched pin contents |
| `~/.local/state/yazi/gitp4v/pins.tsv` | Your pins (persistent) |
| `<clones>/` (`clones` in `gitp4v_opts`) | Git clones and Perforce workspaces |
| `<clones>/.gitp4v/` | Per-repo active branch/clone, and `p4-ws.tsv` (workspace roots) |

## Design and why

### Shadow trees instead of a real file list

yazi plugins cannot inject virtual entries into a directory listing, and there is no custom
filesystem scheme. So each depot is materialized as a tree of zero-byte placeholder files. yazi
then lists, searches, filters, marks and sorts it natively, and a previewer plugin replaces the
file preview with history. The same trick builds history lists (a directory with one placeholder
per revision, named `IDX id date author  subject`, parsed back by the plugin) and the pinned list
(symlinks, so previews and opening just work).

### Local disk for the cache

Building a 3,800-entry tree took 78 seconds on the NFS home and under 1 second on `/tmp`. The
cache therefore lives in `/tmp/$USER/gitp4v`. Per-file forks were also removed (`xargs` batches
`mkdir`/`touch`), and the repo-info and tree API calls run in parallel. It is a cache: if `/tmp`
is cleaned, trees are rebuilt on demand.

### Loading on entry, not on hover

Hovering used to build trees, which made scrolling past repos expensive. Now the tree is built when
you press `l` on a repo (with a loading toast); a hovered, never-entered repo just says so.
Perforce depots can hold millions of files, so they are listed lazily: one folder level per `l`
(`p4 dirs` + `p4 files -e`), cached for the TTL, with local opened files overlaid.

### Overloaded keys fall through

`o O Enter l Right h Left a d r` are overridden in `keymap.toml` (via `prepend_keymap`, so every
other default is untouched). Each handler checks whether the cwd/hover is inside a gitp4v tree and,
if not, emits yazi's own action (`open`, `enter`, `leave`, `create`, `remove`, `rename`, ...). `e`
is a single key opening a menu inside the depot and doing nothing elsewhere. `w` stays the task
manager; pinning is `E`. Header text (`//org/repo/...`) and the git/p4 icons are done by
overriding `Header.cwd` and `Entity.icon` in `setup()`.

### Folder previews and history colors

A previewer rule covers the shadow trees. For a file it renders history; for a folder it lists the
folder's contents (`gitp4v.sh lsdir`): the tree for git, an on-demand `p4 dirs`/`p4 files` listing
for Perforce (debounced 0.15 s so scrolling past folders does not hit the server). The center pane
of a history list is yazi's own file list, so to keep the colors the preview has, `setup()` wraps
`Entity.highlights` and colors names of the form `IDX id date author  subject` (index dim, id yellow,
date cyan, author green) when the parent folder is under `commits/`.

### Popups

The changed-files list (`e s`) is yazi's own spot popup (the one `<Tab>` opens), drawn by the plugin's
`spot` hook with `ya.spot_table`. The popup is tied to the hovered file, so `yazi.toml` registers the
plugin as the spotter for the depot trees and `M:spot` delegates to yazi's stock `file` / `folder`
spotter unless the status popup was just requested (`e s` stores the data and a `pending` flag, then
emits `spot`). The Lua API cannot read which row is selected, so the `[spot]` keys j/k/Up/Down run
`arrow next|prev` as before **and** tell the plugin, which keeps its own cursor (header and hint are
the first two rows, so cursor 3 is the first file). Enter, `d` and the close keys are bound the same
way; Esc/Tab/Ctrl-c clear the plugin state so a later `<Tab>` is stock again. After a discard the data
is re-read and the popup redrawn; the folder listing is refreshed when the popup closes (a `cd` while
it is open would close it). An earlier version used fzf in a tmux popup; it only worked in tmux.
Text, confirm, authentication and error boxes use yazi's own `ya.input` / `ya.confirm` / `ya.notify`.

### Loading messages

"Loading //repo" is shown the first time a repo is entered per yazi session, or on a forced refresh;
Perforce shows it only for a depot's top level. A session-level set in plugin state remembers what
was entered.

### Which program edits

Before editing, the plugin asks yazi (`rt.open.rules:match`) which opener the `[open]` rules pick for
a text file and passes its name to the backend, which looks up that opener's `run` template in the
`[opener]` table of `yazi.toml` (`%s` = the quoted files) and runs it; with no match it uses
`$EDITOR`. The match uses the hovered entry and `text/plain`, so extension rules can differ for
files edited from a history list.

### Cleaning up

Disk is reclaimed when work is thrown away or done: discarding a git branch deletes its clone;
starting the next branch after a merged/closed PR deletes the previous clone; Perforce revert-all and
a successful submit delete the whole workspace (`p4 client -d`, folder, bookkeeping row), so a client
only exists while it has work; `e D` deletes one explicitly. A clone or workspace whose folder has
vanished is forgotten the next time it is looked up (for Perforce: `revert -k`, delete pending CLs,
`client -d`). Every removal is guarded to paths under the clones folder.

### History ordering and diff direction

History entries carry an index that is larger for newer revisions, and the list is sorted natural
descending so the newest is on top. Opening a list saves your sort preference and forces that
order; leaving restores it. Diffs always put the newer version on the left, files are named
`<name>#<index>`, and the diff program is configurable (`diff` in `gitp4v_opts`).

### Fast clones

A full `gh repo clone` of a 170 MB repo took about 11 s (and 19 s on the NFS clones folder); the clone is
now `--filter=blob:none --no-checkout --single-branch` followed by a no-cone sparse checkout that starts
with one dummy pattern (about 1-3 s). History is complete (merge-base, rebase and diffs work); file
contents are fetched lazily. `sp_add` adds a path to the sparse set before an edit, add, delete or
rename (it only acts if `core.sparseCheckout` is true, so older full clones keep working). Rebasing at PR
time fetches only what a conflict needs.

### Git model: one branch, one commit, one PR

Per repo there is at most one active review branch, stored with its clone in
`<clones>/.gitp4v/<owner>__<repo>`. The first change asks for a branch name (default
`$USER<yyyymmdd>`) and clones to `<clones>/<repo>-<branch>`. Changes accumulate uncommitted
(yellow). `e c` commits (green) and from then on edits are blocked until the PR exists, then until
it is merged or closed, at which point the next change starts a fresh branch. `e p` fetches, rebases
onto the default branch if it moved (a conflict is left in the clone and reported), pushes (force
with lease only after a rebase) and runs `gh pr create`. `e x` deletes the local branch and its clone; a pushed
remote copy is never touched. The default branch is never pushed to.

### Perforce model: workspace + default changelist + one pending CL

A "clone" is a lightweight client created per chosen depot folder (the *workspace root*), viewing
`<root>/...` under `<clones>/<root_with_underscores>`. Only files you edit are synced
(`p4 sync <file>`), so nothing big is downloaded. The first edit asks for the root (default: the
file's folder; edit it to go higher); roots are remembered in `p4-ws.tsv` and the longest matching
root wins. Existing mkwa clients are not touched.

Opened files live in the default changelist (yellow triangle). `e c` moves them into a numbered CL
with your description (green, pending, not submitted). While a CL is pending, further changes are
blocked. `e p` submits (after confirm), `e v` shelves, `e x` reverts everything and deletes the CL.
There is no rebase step: if a file is out of date at submit, p4's message is shown with the
workspace path to resolve in. Checkout (`p4 edit`) failures (permissions, exclusive locks, not
mapped) are reported, not hidden: p4 exits 0 for "not opened", so the code verifies with
`p4 opened` output instead of exit codes.

### Pins

`E` toggles a pin for the hovered or marked files. Each pin is a line in `pins.tsv`:
`kind <TAB> target <TAB> saved path <TAB> epoch`, kind being `local` (absolute path, opened through
a symlink), `depot` (git `owner/repo:path`, current version fetched when the list opens) or `p4`
(`//depot/path`, fetched with `p4 print`). `g p` rebuilds `pinned/` and loads the saved paths into
plugin state so the header can show where each file was pinned from. Depot pins are view-only.

### Errors

Errors from the backend are classified, in the script (`classify_err`) and again in Lua, into:
Perforce or GitHub login problems (a confirm box that offers to run `p4 login` / `gh auth login`),
git push/clone authentication problems, and permission problems ("access denied", "protected
namespace", checkout refused). Everything else is a plain error toast. `open-root` reports a
failing service as a warning line so the other still loads.

## Things learned the hard way

- yazi 26.x runs Lua 5.5: loop variables are constants (do not assign to them).
- A module loaded with `require("gitp4v.p4")` must return a table (a function errors). The module
  gets its helpers through a `ctx` table because `ya.sync` state belongs to `main.lua`.
- `%a` does not match the digit in `p4`; use `%w` when parsing kinds.
- The `cwd` of yazi may be a shadow directory the script replaces; the script starts with `cd /`.
- `p4 -F` is unreliable here; output is parsed from plain or `-ztag` text. `p4 files` on a level
  that holds no files answers "protected namespace" and is treated as empty when folders exist.
- A trap on `EXIT` must expand the temp-dir variable immediately (it is function-local).
- Typing into tmux-driven tests before a popup is up types into yazi; the tests wait for popups.

## Tested and not tested

Tested against the real services: depot listing, git repo load, history, previews, view and diff
(including `nvim -d`), pins (local, git, p4) and state-dir creation, git add/delete/rename/commit/
status/discard flows (local only, nothing pushed), p4 listing and history, p4 workspace creation, add,
CL creation, the one-pending-CL block, opened-files popup, revert-all (on a throwaway client in
a writable depot folder, all removed afterwards), checkout refusal on a read-only path, and the p4/gh
authentication boxes (with bad credentials).

Also tested since: the `e s` popup as yazi's native spot popup (git and p4, including diff and discard), folder previews (git and p4), colored
history entries, first-visit-only loading toast, git discard deleting its clone, p4 revert-all and
workspace delete (`e D`) freeing the local folder, the opener lookup (`nvim` from `[open]` rules), and
`install.sh` (idempotent).

Not exercised: git pull-request creation, push, and the rebase-conflict message; p4 submit (including
the workspace cleanup after it) and shelve (never run on purpose); a successful `p4 edit` on an
existing file, `p4 delete`, `p4 move`; `e w` and `e l` in p4; deleting the old clone when the next
branch starts after a merged PR; the p4 submit workspace deletion.

## Known limits

- Very large git repos whose tree is truncated by the GitHub API show a partial tree.
- Perforce folder rename is not supported (files only); delete of a folder opens everything under it.
- Search and filter only see what has been listed (for Perforce: folders you have opened).
- The p4 icon and git icon are Nerd Font code points; set `icons` in `gitp4v_opts` if your font differs.
- Not covered by this setup: p4 streams specifics, integrations/resolve, multiple pending CLs per workspace.

## Troubleshooting

- Nothing happens on `e`: you are outside the depot view (by design). Press `g v` first.
- "Authentication" box: accept it to log in, then repeat the action.
- A depot folder looks stale: `e l` refreshes it. Everything under `/tmp/$USER/gitp4v` can be deleted.
- Plugin errors: run `YAZI_LOG=debug yazi` and read `~/.local/state/yazi/yazi.log`.
- `gitp4v.sh` with no arguments prints the backend command list; the commands can be run by hand.
- To change a key, edit `keymap.toml` (the `run` lines call `plugin gitp4v -- <action>`).
