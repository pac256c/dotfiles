# gitp4v.yazi: usage notes

Install, dependencies and configuration are in `README.md`; this file is the day-to-day guide.

Browse GitHub Enterprise repos and Perforce depots like p4v from yazi, and edit them
(git: a local clone on one review branch; Perforce: a workspace with a changelist).

Quick reference: `cheatsheet.html` (open in a browser). Implementation notes and the reasons
behind the choices: `DESIGN.md`.

Outside the depot every key below behaves exactly like yazi's own (`e` does nothing).

## Keys

Navigation
- `g v`  "Go to network locations": the depot view. `//` lists GitHub orgs (git icon) and
  Perforce depots (p4 icon)
- git: `l` / Right on a repo loads its tree; Perforce: `l` / Right on a folder lists that folder
  (folders are listed lazily, one level at a time)
- Hovering a folder shows its contents in the right pane; hovering a file shows its history
- `l` / Right on a file: its history becomes the center list (colored), newest at the top.
  The index is larger for newer revisions (git: commit order, Perforce: #rev). The right pane shows
  the commit / CL message and that file's patch; `h` / Left goes back to the file
- `o` / Enter on a file: read the current version (read-only)
- `o` / Enter in a history list: view the hovered version. Mark versions with Space:
  1 marked = view it, 2 marked = diff them (newer on the left, files named `<name>#<index>`),
  more = error. The diff program is `diff` in your `gitp4v_opts` (default: git diff in less)

Pinned files
- `E`  pin the hovered / marked files (or unpin them if already pinned); works on local files,
  git files and Perforce files. In the pinned list it unpins the hovered file
- `g p`  "Go to pinned". Hovering an entry shows, in the header, the path that was on
  screen when it was pinned; the right pane is a normal preview. Local pins are symlinks and open
  normally; git/Perforce pins are the current version (fetched when the list opens), view-only
- Pins are stored in `~/.local/state/yazi/gitp4v/pins.tsv` (the folder is created when needed)

Editing: one review branch / one commit / one PR at a time per repo (git),
one pending changelist at a time per workspace (Perforce)
- `O`  edit the hovered file (or all marked files); works from a history list too. The file is opened
  with the first opener yazi.toml's `[open]` rules choose for a text file (for example `nvim`), else `$EDITOR`
- `a`  add a file to the current folder (asks for the name, then opens it)
- `d`  delete the hovered / marked files or folders (asks to confirm)
- `r`  rename the hovered file (asks for the new name)

Git (`e` menu)
- The first change in a repo asks for a branch name (default `$USER<yyyymmdd>`) and clones into
  `<clones>/<repo>-<branch>` with a "Cloning into ..." popup. After committing, further changes are
  blocked until the pull request is opened, and then until it is merged or closed (the old clone is
  then deleted when you start the next branch)
- `c` commit, `p` pull request (rebases if the default branch moved; a conflict is left in the clone),
  `s` changed-files popup (A/M/D/R, yellow triangle = not committed, green = committed; Enter diff,
  `d` discard a file), `x` discard the local branch **and delete its clone**, `l` refresh, `q` leave
- Clones are fast: a blobless, sparse clone (full history, no file contents; only the files you edit are
  fetched and checked out), so cloning takes a second or two instead of the whole repo. If a clone is
  deleted behind the plugin's back it is simply forgotten and the next change starts a new one

Perforce (`e` menu)
- Edits need a workspace: the first edit asks (popup) for the workspace root, a depot folder that
  contains the file (default: the file's folder; edit it to go higher), and creates a small client
  under `<clones>` that views `<root>/...`. Files are synced one by one as you edit them. `w` makes
  the current folder a workspace root explicitly. If checkout is not allowed (permissions, exclusive
  lock, ...) an error popup says so
- Edited / added / deleted files sit in the default changelist (yellow triangle). `c` creates a
  numbered CL from them (asks for the description; green triangle, "pending, not submitted");
  `p` submits it (asks to confirm; an out-of-date file is reported with where to resolve it);
  `v` shelves it; `s` lists opened files (A/M/D/R, Enter = diff, `d` reverts a file while in the
  default changelist; "No opened files" when clean); `x` reverts everything and deletes the CL
- A workspace (client) exists only while it has work: `x` (revert all) and a successful submit delete the
  client (`p4 client -d`) and its local folder; `D` deletes a workspace explicitly. A workspace whose
  folder was deleted behind the plugin's back is cleaned up (opened files reverted, CLs deleted, client
  deleted) and the next change creates a fresh one
- Until the pending CL is submitted or reverted, further changes are blocked with a popup
- `l` refresh, `q` leave

The `e s` list is yazi's own popup (the one `<Tab>` opens on a file): Up/Down (or j/k) move, Enter shows
the diff of the selected file, `d` discards / reverts it (confirm), Esc closes. `<Tab>` on any depot
file or folder still shows the stock info. This needs the spotter and `[spot]` key rules that
`install.sh` adds.

The "Loading ..." toast appears the first time a repo or depot is entered in a yazi session (and on a
refresh), not on every folder change inside it.

Errors: login problems show an "Authentication" box (Perforce / GitHub) with an offer to run
`p4 login` / `gh auth login`; permission problems show a "permission denied" box.

## How it works

Each depot is a tree of empty placeholder files under `/tmp/$USER/gitp4v/view/<top-level>/...`
(local disk: NFS home was 15-80x slower), so yazi search/filter/navigation work natively; local
changes are re-applied to it on refresh. `gitp4v.sh` (git, via `gh`) and `p4.sh` (Perforce) do the
work; run `gitp4v.sh` with no args for usage.

Limits: very large git repos whose tree is truncated by the GitHub API show a partial tree;
Perforce folder rename is not supported (files only). Extra git depots in `gitp4v_opts` are
`label -> URL`; the owner/repo comes from the URL.
