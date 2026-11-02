# gitp4v.yazi

A [yazi](https://yazi-rs.github.io) plugin that browses GitHub repos and Perforce depots like p4v,
shows per-file history in the preview pane, views and diffs versions, edits through a local clone
(git: one review branch, commit, pull request) or a workspace (Perforce: default changelist, CL,
submit, shelve), and pins files for quick access.

- `cheatsheet.html` - one-page quick reference of the keys (open it in a browser)
- `notes.md` - day-to-day usage guide
- `DESIGN.md` - how it works and why it was built this way

## Requirements

Required

| What | Why | Tested with |
|------|-----|-------------|
| [yazi](https://yazi-rs.github.io/docs/installation) 26.x | the host (uses the spot popup, `rt.open.rules`, `Entity` overrides) | 26.9.1 |
| A [Nerd Font](https://www.nerdfonts.com) (v3) in your terminal | file icons and the git / Perforce icons | - |
| `bash` 4+ and GNU `sed`, `awk`, `find`, `xargs`, `ls`, `date`, `readlink`, `mktemp`, `cksum`, `less` | the backend scripts | Linux |
| `git` 2.25+ | sparse checkout for fast clones | 2.52 |
| [`gh`](https://cli.github.com) (GitHub CLI), logged in (`gh auth login`) | listing repos, history, file contents, pull requests | 2.69 |

Optional

| What | Why |
|------|-----|
| `p4` (Perforce command line client) and a valid ticket (`p4 login`) | the Perforce half; without a configured `p4.port` it is simply off |
| An editor: `$EDITOR`, or an opener in your `yazi.toml` `[open]` rules (the first one for text files is used for edits) | opening files for edit |
| A diff program, for example `nvim -d`, `vimdiff`, `meld`, `delta` | version diffs; default is `git diff` in `less` |
| `fd`, `ripgrep`, `fzf`, `zoxide` | yazi's own search (`s`, `S`), jump (`z`, `Z`) and find; they work on the depot view like anywhere else. The plugin itself does not call them |
| `file`, `ffmpeg`, `jq`, `poppler` (pdf), `7zip`, `imagemagick`, `chafa`/a graphics-capable terminal | yazi's normal previewers for local files (for example pinned local files). See yazi's installation page |
| tmux | not needed |

Platform: Linux (written and tested there). The caches live on local disk under `/tmp/$USER/gitp4v`.

## Install

1. Put this folder at `~/.config/yazi/plugins/gitp4v.yazi/` (for example `git clone` / copy it there).
2. Run the installer:

   ```
   ~/.config/yazi/plugins/gitp4v.yazi/install.sh
   ```

   yazi has no include mechanism for its toml files, so the installer writes three small marked
   blocks into your config: the key bindings into `keymap.toml`, the previewer and spotter rules into
   `yazi.toml`, and a one-line hook into `init.lua`. The marked blocks are the only thing it touches;
   re-run it after editing `keymap.toml` or `yazi.toml` in this folder. If your `yazi.toml` already has a
   `[plugin]` table it tells you to merge the rules by hand. `install.sh --uninstall` removes the blocks.
3. Put your settings in `~/.config/yazi/init.lua`, above the gitp4v block (the installer adds a
   commented template the first time):

   ```lua
   gitp4v_opts = {
       org = "my-github-org",                              -- repos of this org are listed
       p4 = { port = "perforce.example.com:1666", user = "me" },  -- optional
       clones = "/big/disk/gitp4v",                        -- where clones / workspaces live
       diff = "nvim -d",                                   -- optional
   }
   ```

4. Log in once: `gh auth login`, and `p4 login` if you use Perforce.
5. Restart yazi and press `g` `v` ("Go to network locations").

## Configuration

Your values live in `gitp4v_opts` in `init.lua` (outside this folder). Defaults and the full option
list are in `config.lua`:

| Option | Meaning |
|--------|---------|
| `org` | GitHub org whose non-archived repos are listed (none by default) |
| `depots` | extra git repos, `name = "URL"` |
| `p4` | `{ port = ..., user = ... }`; no port means Perforce is off |
| `clones` | where clones and workspaces live (default `~/.local/share/gitp4v/clones`) |
| `diff` | diff program run as `<diff> <left> <right>` (default: `git diff` in `less`) |
| `icons` | glyphs for git and p4 top-level entries |
| `ttl`, `limit` | minutes before a repo tree is re-fetched; commits shown per path |

## Keys in one minute

`g v` network locations, `l`/Right open a repo / folder / file history, `h`/Left back, `o`/Enter read,
`O` edit, `a` add, `d` delete, `r` rename, `E` pin, `g p` pinned, `e` menu (commit, pull request /
submit, changed files, discard, ...). Outside the depot view all of them behave exactly like yazi's own
(and `e` does nothing). Details: `cheatsheet.html` and `notes.md`.

## Troubleshooting

- Nothing under `g v`: set `org` and/or `p4` in `gitp4v_opts`, then restart yazi.
- Login problems show an "Authentication" box with an offer to run `gh auth login` / `p4 login`.
- Missing icons: install a Nerd Font and select it in your terminal (or set `icons`).
- Debugging: `YAZI_LOG=debug yazi`, then read `~/.local/state/yazi/yazi.log`.
- Everything under `/tmp/$USER/gitp4v` is a cache and can be deleted.

## License

MIT, see `LICENSE`.
