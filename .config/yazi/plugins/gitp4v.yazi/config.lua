-- gitp4v default settings (nothing here is specific to a site). Put YOUR values in
-- ~/.config/yazi/init.lua, above the gitp4v block, as a global table:
--
--   gitp4v_opts = {
--       org = "my-github-org",
--       p4 = { port = "perforce.example.com:1666", user = "me" },
--       clones = "/big/disk/gitp4v",
--       diff = "nvim -d",
--   }
--
-- Anything given there overrides the value below.

return {
	-- GitHub org whose non-archived repos are listed (needs `gh auth login`).
	-- nil: no org; only the repos in `depots` are listed.
	org = nil,

	-- Extra git depots, name -> repo URL (other orgs, single repos).
	-- The owner/repo comes from the URL; the name is only a label.
	depots = {
		-- some_name = "https://github.com/SOME-ORG/some_repo",
	},

	-- Perforce server and user. Depots of this server are listed next to the git
	-- ones. Login uses your normal p4 ticket (run `p4 login` once). No port: Perforce is off.
	p4 = {
		-- port = "perforce.example.com:1666",
		-- user = "me",
	},

	-- Icons for the top-level entries (Nerd Font glyphs): git orgs vs p4 depots.
	-- icons = { git = "\u{F02A2}", p4 = "\u{F01BC}" },

	-- Where edits live. Git: <clones>/<repo>-<branch name>. Perforce: one lightweight
	-- workspace per chosen depot folder, <clones>/<depot_path_with_underscores>.
	-- One branch / pending CL (and so one clone) per repo or workspace at a time.
	-- Discarding a branch or reverting / submitting a CL deletes its clone / workspace again.
	-- nil: ~/.local/share/gitp4v/clones
	clones = nil,

	-- Program used to diff two versions, run as "<diff> <left> <right>" with the
	-- newer version on the left. nil: git diff piped to less.
	-- Examples: "nvim -d", "vimdiff", "meld", "delta".
	diff = nil,

	-- ttl = 60,    -- minutes before a depot's shadow tree is re-fetched
	-- limit = 50,  -- commits shown per path
}
