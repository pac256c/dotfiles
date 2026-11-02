-- gitp4v: browse GitHub Enterprise repos like a p4v depot from inside yazi.
--
-- Two shadow trees of zero-byte placeholder files live on local disk, so
-- yazi's own navigation/search/filter/selection work unchanged:
--   view/<owner>/<repo>/<path>             the repo's files
--   commits/<owner>/<repo>/<path>/<entry>  one entry per commit touching <path>
--
-- Keys (see keymap.toml). Outside the depot every one of them falls through
-- to yazi's own action, except `e`, which then does nothing.
--   g v   open the depot view        l / Right   load a repo / open a file's history
--   h / Left   back from history     o / Enter   read a file or version (2 marked = diff)
--   O     edit file(s) on the review branch   a add a file   d delete   r rename
--   e     menu: commit, pull request, changed files, discard, refresh, leave
-- One review branch / one commit / one PR at a time per repo.
-- All heavy lifting is in gitp4v.sh next to this file.

local M = {}
local P4 -- the Perforce half (p4.lua), created below once the helpers exist

-- ---------------------------------------------------------------- state
local function tab()
	local ok, t = pcall(function() return cx.tab end)
	if ok and t then
		return t
	end
	return cx.active
end

local get_cfg = ya.sync(function(st) return st.cfg or {} end)
local get_prev = ya.sync(function(st) return st.prev end)
local set_prev = ya.sync(function(st, p) st.prev = p end)

-- Sort preference saved while a history list forces newest-first order.
local get_saved = ya.sync(function(st) return st.saved_sort end)
local set_saved = ya.sync(function(st, v) st.saved_sort = v end)
local read_sort = ya.sync(function()
	local p = tab().pref
	return { by = tostring(p.sort_by), reverse = p.sort_reverse and true or false, dir_first = p.sort_dir_first and true or false }
end)

-- Top-level entries of the view root: name -> "git" | "p4" (from open-root).
local get_kinds = ya.sync(function(st) return st.kinds or {} end)
local set_kinds = ya.sync(function(st, k) st.kinds = k end)

-- Repos / depots entered in this yazi session (the "Loading ..." toast is for the first visit only).
local get_entered = ya.sync(function(st) return st.entered or {} end)
local mark_entered = ya.sync(function(st, key)
	st.entered = st.entered or {}
	st.entered[key] = true
end)
local function first_visit(key)
	if get_entered()[key] then
		return false
	end
	mark_entered(key)
	return true
end

-- Data behind the changed-files popup (see M:spot and spot_action):
-- { active, pending, kind, id, cwd, dir_dp, committed, header, rows = { {m, p, old} }, cursor }
local get_status = ya.sync(function(st) return st.status end)
local set_status = ya.sync(function(st, v) st.status = v end)

-- The opener yazi.toml's [open] rules choose for a text file (name, e.g. "nvim"),
-- judged from the hovered entry; nil if no rule matches (then $EDITOR is used).
local resolve_opener = ya.sync(function()
	local h = tab().current.hovered
	if not h then
		return nil
	end
	local ok, name = pcall(function()
		for _, rule in pairs(rt.open.rules:match({ file = h, mime = "text/plain" })) do
			local use = rule.use
			if use and use[1] then
				return use[1]
			end
		end
	end)
	return ok and name or nil
end)

-- Pinned files shown in the pinned list, keyed by entry name:
-- { kind = "local"|"depot", target = ..., saved = path shown in the header }
local get_pins = ya.sync(function(st) return st.pins or {} end)
local set_pins = ya.sync(function(st, p) st.pins = p end)

-- Depot paths shown as //owner/repo/... (history lists get a [history] tag).
local function display_path(path)
	local rest = path:match("/gitp4v/view(/.*)$")
	if rest then
		return "/" .. rest
	end
	if path:match("/gitp4v/view$") then
		return "//"
	end
	rest = path:match("/gitp4v/commits(/.*)$")
	if rest then
		return "/" .. rest .. "  [history]"
	end
	if path:match("/gitp4v/pinned$") then
		return "[pinned files]"
	end
end

-- hovered url, is_dir, cwd, list of selected urls, header text for cwd
local hovered = ya.sync(function()
	local t = tab()
	local h = t.current.hovered
	local sel = {}
	for _, f in pairs(t.selected) do
		sel[#sel + 1] = tostring(f.url or f)
	end
	table.sort(sel)
	local cwd = tostring(t.current.cwd)
	return h and tostring(h.url) or nil, h and h.cha.is_dir or false, cwd, sel,
		display_path(cwd) or ya.readable_path(cwd)
end)

-- Shallow-recursive merge: values in `over` win; tables are merged key by key.
local function merge(base, over)
	local out = {}
	for k, v in pairs(base or {}) do
		out[k] = v
	end
	for k, v in pairs(over or {}) do
		if type(v) == "table" and type(out[k]) == "table" then
			out[k] = merge(out[k], v)
		else
			out[k] = v
		end
	end
	return out
end

-- Called from init.lua: require("gitp4v"):setup()  (settings live in config.lua;
-- anything passed here overrides them)
function M:setup(opts)
	self.cfg = merge(require("gitp4v.config"), opts)
	local st = self

	Header.cwd = function(h)
		local max = h._area.w - h._right_width
		if max <= 0 then
			return ""
		end
		local path = tostring(h._current.cwd)
		local s
		if path:match("/gitp4v/pinned$") then
			-- In the pinned list, show the path that was on screen when the
			-- hovered file was pinned.
			local hv = h._current.hovered
			local rec = hv and st.pins and st.pins[hv.name]
			s = rec and rec.saved or display_path(path)
		else
			s = display_path(path) or ya.readable_path(path)
		end
		s = s .. h:flags()
		return ui.Span(ui.truncate(s, { max = max, rtl = true })):style(th.mgr.cwd)
	end

	-- Different icons for git orgs and p4 depots in the depot-view root.
	-- Glyphs are Nerd Font code points (override with `icons` in init.lua).
	local default_icons = { git = "\u{F02A2}", p4 = "\u{F01BC}" }
	local icon_styles = { git = ui.Style():fg("#f05133"), p4 = ui.Style():fg("#4aa3df") }
	-- History lists: color the entry names like the preview does (index dim,
	-- id yellow, date cyan, author/user green).
	local orig_highlights = Entity.highlights
	Entity.highlights = function(e)
		local f = e._file
		if not f.cha.is_dir then
			local parent = f.url.parent
			if parent and tostring(parent):find("/gitp4v/commits/", 1, true) then
				local idx, id, date, author, subj =
					f.name:match("^(%d+) (%w+) (%d%d%d%d%-%d%d%-%d%d)  (.-)  (.*)$")
				if idx then
					return ui.Line {
						ui.Span(idx .. " "):fg("#8a93a6"),
						ui.Span(id .. " "):fg("yellow"),
						ui.Span(date .. "  "):fg("cyan"),
						ui.Span(author .. "  "):fg("green"),
						ui.Span(subj),
					}
				end
			end
		end
		return orig_highlights(e)
	end

	local orig_icon = Entity.icon
	Entity.icon = function(e)
		local f = e._file
		if f.cha.is_dir then
			local parent = f.url.parent
			if parent and tostring(parent):match("/gitp4v/view$") then
				local kind = st.kinds and st.kinds[f.name]
				local glyph = kind and (((st.cfg or {}).icons or {})[kind] or default_icons[kind])
				if glyph then
					if f.is_hovered then
						return glyph .. " "
					end
					return ui.Span(glyph .. " "):style(icon_styles[kind])
				end
			end
		end
		return orig_icon(e)
	end
end

-- --------------------------------------------------------------- helpers
local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Recognise authentication / permission failures in a backend or tool error
-- message. Returns "p4" | "gh" | "git" | "denied" and the one-line reason.
local function classify(msg)
	msg = tostring(msg or "")
	local k, t = msg:match("AUTH%-([%u%d]+): ([^\n]*)")
	if k then
		return k:lower(), t
	end
	if msg:find("DENIED: ", 1, true) then
		-- keep the whole sentence ("cannot check out X (edit not allowed): ...")
		return "denied", (msg:gsub("DENIED: ", "", 1):match("[^\n]+"))
	end
	local first = msg:match("([^\n]+)") or msg
	if msg:find("P4PASSWD", 1, true) or msg:find("session has expired", 1, true) or msg:find("Connect to server failed", 1, true) then
		return "p4", first
	elseif msg:find("gh auth login", 1, true) or msg:find("HTTP 401", 1, true) or msg:find("Bad credentials", 1, true) then
		return "gh", first
	elseif msg:find("Permission denied (publickey)", 1, true) or msg:find("Authentication failed", 1, true) or msg:find("could not read Username", 1, true) then
		return "git", first
	elseif msg:find("protected namespace", 1, true) or msg:find("access denied", 1, true) then
		return "denied", first
	end
end

local show_auth -- set below, once interactive() exists

-- Toast for info/warn; errors that are really login or permission problems
-- get a proper box saying so (with an offer to log in).
local function notify(level, content, timeout)
	if level == "error" then
		local kind, text = classify(content)
		if kind then
			return show_auth(kind, text)
		end
	end
	ya.notify { title = "gitp4v", content = content, timeout = timeout or 5, level = level }
end

-- Text popup. Returns the trimmed text, or nil if cancelled (or empty,
-- unless allow_empty).
local function input(title, value, allow_empty)
	local v, event = ya.input {
		pos = { "center", w = 70 },
		title = title,
		value = value or "",
	}
	if event ~= 1 or not v then
		return nil
	end
	v = trim(v)
	if v == "" and not allow_empty then
		return nil
	end
	return v
end

local function confirm(title, body)
	return ya.confirm {
		pos = { "center", w = 70, h = 10 },
		title = title,
		body = body,
	}
end

local function script_path(cfg)
	if cfg.script then
		return cfg.script
	end
	local base = os.getenv("YAZI_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config/yazi")
	return base .. "/plugins/gitp4v.yazi/gitp4v.sh"
end

local function build(cfg, args, terminal)
	local c = Command("bash"):arg(script_path(cfg))
	for _, a in ipairs(args) do
		c = c:arg(a)
	end
	local env = {
		GITP4V_ORG = cfg.org,
		GITP4V_CACHE = cfg.cache,
		GITP4V_CLONES = cfg.clones,
		GITP4V_TTL = cfg.ttl and tostring(cfg.ttl) or nil,
		GITP4V_LIMIT = cfg.limit and tostring(cfg.limit) or nil,
		GITP4V_DIFF = cfg.diff,
		GITP4V_INTERACTIVE = terminal and "1" or nil,
		P4PORT = cfg.p4 and cfg.p4.port or nil,
		P4USER = cfg.p4 and cfg.p4.user or nil,
		GITP4V_OPENER = cfg.opener,
	}
	if cfg.depots then
		local names = {}
		for name in pairs(cfg.depots) do
			names[#names + 1] = name
		end
		table.sort(names)
		local lines = {}
		for _, name in ipairs(names) do
			lines[#lines + 1] = name .. "\t" .. cfg.depots[name]
		end
		env.GITP4V_DEPOTS = table.concat(lines, "\n")
	end
	for k, v in pairs(env) do
		c = c:env(k, v)
	end
	return c
end

-- Run the backend without a terminal; returns stdout or nil, message.
local function capture(cfg, args)
	local child, err = build(cfg, args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if not child then
		return nil, "cannot start gitp4v.sh: " .. tostring(err)
	end
	local out, err2 = child:wait_with_output()
	if not out then
		return nil, tostring(err2)
	end
	if not out.status.success then
		local msg = trim(out.stderr):gsub("^gitp4v: ", "")
		return nil, msg ~= "" and msg or ("exit code " .. tostring(out.status.code))
	end
	return out.stdout
end

-- Run the backend on the real terminal (yazi UI suspended). Returns an
-- error message (or nil) and the exit code. The backend waits for Enter
-- after an error.
local function interactive(cfg, args)
	local permit = ui.hide()
	local c = build(cfg, args, true):stdin(Command.INHERIT):stdout(Command.INHERIT):stderr(Command.INHERIT)
	local child, err = c:spawn()
	local msg, code
	if not child then
		msg = "cannot start gitp4v.sh: " .. tostring(err)
	else
		local status, err2 = child:wait()
		if not status then
			msg = tostring(err2)
		else
			code = status.code
		end
	end
	permit:drop()
	return msg, code
end

-- A copy of cfg that carries the opener to use for editing (see resolve_opener).
local function with_opener(cfg)
	local name = resolve_opener()
	if not name then
		return cfg
	end
	local c = {}
	for k, v in pairs(cfg) do
		c[k] = v
	end
	c.opener = name
	return c
end

show_auth = function(kind, text)
	local cfg = get_cfg()
	if kind == "denied" then
		ya.notify { title = "gitp4v: permission denied", content = text, timeout = 10, level = "error" }
	elseif kind == "git" then
		ya.notify {
			title = "gitp4v: git authentication failed",
			content = text .. "\nCheck your ssh key or run `gh auth status`.",
			timeout = 12, level = "error",
		}
	elseif kind == "p4" then
		local ok = ya.confirm {
			pos = { "center", w = 76, h = 10 },
			title = "Perforce authentication",
			body = text .. "\n\nRun `p4 login` now?",
		}
		if ok then
			interactive(cfg, { "p4-login" })
			ya.notify { title = "gitp4v", content = "Back from p4 login. Retry what you were doing.", timeout = 5, level = "info" }
		end
	else
		local ok = ya.confirm {
			pos = { "center", w = 76, h = 10 },
			title = "GitHub authentication",
			body = text .. "\n\nRun `gh auth login` now?",
		}
		if ok then
			interactive(cfg, { "gh-login" })
			ya.notify { title = "gitp4v", content = "Back from gh login. Retry what you were doing.", timeout = 5, level = "info" }
		end
	end
end

-- Classify a path inside a shadow tree. Matches on the .../gitp4v/<tree>/...
-- suffix so it does not depend on how the cache root is spelled.
-- Returns nil outside the depot, else { kind=, owner=, repo=, nwo=, rel= }
-- (owner/repo/rel are nil above that level).
local function split(url)
	if not url then
		return nil
	end
	if url:match("/gitp4v/view$") then
		return { kind = "view" }
	end
	if url:match("/gitp4v/pinned$") then
		return { kind = "pinned" }
	end
	local pinned = url:match("/gitp4v/pinned/([^/]+)$")
	if pinned then
		return { kind = "pinned", name = pinned }
	end
	local kind, rest = "view", url:match("/gitp4v/view/(.*)$")
	if not rest then
		kind, rest = "commits", url:match("/gitp4v/commits/(.*)$")
	end
	if not rest or rest == "" then
		return nil
	end
	local owner, repo, rel = rest:match("^([^/]+)/([^/]+)/?(.*)$")
	if owner then
		return { kind = kind, owner = owner, repo = repo, nwo = owner .. "/" .. repo, rel = rel, rest = rest }
	end
	return { kind = kind, owner = rest:match("^([^/]+)"), rest = rest }
end

-- "git" or "p4" for a top-level entry of the view root (cached; asks the
-- backend if this session has not seen the name yet).
local function vendor_of(cfg, owner)
	if not owner then
		return nil
	end
	local k = get_kinds()[owner]
	if k then
		return k
	end
	local out = capture(cfg, { "kind", owner })
	k = trim(out)
	if k == "" then
		return nil
	end
	local t = get_kinds()
	t[owner] = k
	set_kinds(t)
	return k
end

-- History entry name "IDX sha date ..." -> index (larger = newer), sha, text
local function version(url)
	local name = tostring(url):match("([^/]+)$") or ""
	local idx, sha = name:match("^(%d+) (%x+) ")
	if idx then
		return { idx = tonumber(idx), sha = sha }
	end
end

-- --------------------------------------------------------------- preview
-- Pad/truncate to n display columns without splitting UTF-8 sequences.
local function fit(s, n)
	local len = utf8 and utf8.len(s)
	if not len then
		s = s:gsub("[\128-\255]", "?")
		len = #s
	end
	if len > n then
		local off = utf8 and utf8.offset(s, n + 1) or (n + 1)
		s = s:sub(1, off - 1)
		len = n
	end
	return s .. string.rep(" ", n - len)
end

local function render_history(label, out, p4)
	local lines = {
		ui.Line({ ui.Span(label):bold() }),
		ui.Line({ ui.Span(string.format("%-8s%-11s%-19s%s", p4 and "CL#" or "commit", "date", p4 and "user" or "author", "description")):dim() }),
	}
	for l in out:gmatch("[^\n]+") do
		local sha, date, author, subj = l:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
		if sha then
			lines[#lines + 1] = ui.Line({
				ui.Span(fit(sha, 8)):fg("yellow"),
				ui.Span(fit(date, 11)):fg("cyan"),
				ui.Span(fit(author, 19)):fg("green"),
				ui.Span(subj),
			})
		end
	end
	return lines
end

-- Commit header + message + this file's patch, colored.
local function render_commit(out)
	local lines = {}
	local in_patch = false
	for raw in (out .. "\n"):gmatch("(.-)\n") do
		local l = raw:gsub("\r", ""):gsub("\t", "    ")
		local line
		if l:match("^commit %x+$") or l:match("^CL %d+$") then
			line = ui.Line({ ui.Span(l):fg("yellow") })
		elseif l:match("^Author:") or l:match("^Date:") then
			line = ui.Line({ ui.Span(l):fg("cyan") })
		elseif l:match("^%-%-%- .* %(.-, %+%d+ %-%d+%)$") then
			in_patch = true
			line = ui.Line({ ui.Span(l):bold() })
		elseif in_patch and l:sub(1, 2) == "@@" then
			line = ui.Line({ ui.Span(l):fg("magenta") })
		elseif in_patch and l:sub(1, 1) == "+" then
			line = ui.Line({ ui.Span(l):fg("green") })
		elseif in_patch and l:sub(1, 1) == "-" then
			line = ui.Line({ ui.Span(l):fg("red") })
		else
			line = ui.Line(l)
		end
		lines[#lines + 1] = line
	end
	return lines
end

-- Preview lines for something under a p4 depot (see p4.sh).
local function p4_peek_lines(cfg, d, url, job)
	local dp = "//" .. d.rest
	if d.kind == "commits" then
		local v = version(url)
		local file = dp:match("^(.*)/[^/]+$")
		if v and file then
			local out, err = capture(cfg, { "p4-show", file, tostring(v.idx) })
			if out then
				return render_commit(out)
			end
			return { ui.Line({ ui.Span("revision unavailable: " .. tostring(err)):fg("red") }) }
		end
		return { ui.Line("") }
	end
	if job.file.cha.is_dir then
		return { ui.Line({ ui.Span(dp):bold() }), ui.Line("Press l or Enter to open this folder.") }
	end
	local out, err = capture(cfg, { "p4-hist", dp })
	if out then
		return render_history(dp, out, true)
	end
	return { ui.Line({ ui.Span("history unavailable: " .. tostring(err)):fg("red") }) }
end

-- A folder's contents (git: the repo tree; Perforce: listed on demand), shown
-- instead of history when hovering a folder.
local function dir_lines(cfg, d, vend, job)
	local label = "//" .. d.rest
	if vend == "p4" then
		ya.sleep(0.15) -- debounce: scrolling past folders must not hit the server
	end
	local out, err = capture(cfg, { "lsdir", d.rest })
	if not out then
		return { ui.Line({ ui.Span(label):bold() }), ui.Line({ ui.Span(tostring(err)):fg("red") }) }
	end
	if trim(out) == "NOTLOADED" then
		return {
			ui.Line({ ui.Span(label):bold() }),
			ui.Line("Not loaded yet. Press l or Enter to load this repo."),
		}
	end

	-- yazi's own icon for an entry (the folder tree exists on disk, so ask the theme),
	-- only for the rows that can be on screen
	local visible = job.skip + job.area.h + 1
	local function icon(name)
		local ok, f = pcall(fs.file, job.file.url:join(name))
		if ok and f then
			local ok2, ic = pcall(function() return th.icon:match(f, {}) end)
			if ok2 and ic then
				return ui.Span(ic.text .. " "):style(ic.style)
			end
		end
	end

	local lines = { ui.Line({ ui.Span(label):bold() }) }
	for l in out:gmatch("[^\n]+") do
		local is_dir = l:sub(-1) == "/"
		local name = is_dir and l:sub(1, -2) or l
		local spans = {}
		if #lines <= visible then
			spans[1] = icon(name)
		end
		spans[#spans + 1] = is_dir and ui.Span(name):fg("blue"):bold() or ui.Span(name)
		lines[#lines + 1] = ui.Line(spans)
	end
	if #lines == 1 then
		lines[2] = ui.Line({ ui.Span("(empty)"):dim() })
	end
	return lines
end

function M:peek(job)
	local cfg = get_cfg()
	local url = tostring(job.file.url)
	local d = split(url)
	local lines
	local vend = d and (d.kind == "view" or d.kind == "commits") and d.owner and vendor_of(cfg, d.owner) or nil

	if d and d.kind == "view" and d.owner and job.file.cha.is_dir then
		lines = dir_lines(cfg, d, vend, job)
	elseif vend == "p4" then
		lines = p4_peek_lines(cfg, d, url, job)
	elseif d and d.kind == "commits" and d.repo then
		local v = version(url)
		local file_rel = d.rel:match("^(.*)/[^/]+$")
		if v and file_rel then
			local out, err = capture(cfg, { "show", d.nwo, v.sha, file_rel })
			if out then
				lines = render_commit(out)
			else
				lines = { ui.Line({ ui.Span("commit unavailable: " .. tostring(err)):fg("red") }) }
			end
		else
			lines = { ui.Line("") }
		end
	elseif not d or not d.owner then
		lines = { ui.Line("GitHub depots") }
	else
		-- A repo's tree is only built when you enter it (see load_repo), so a
		-- hovered repo that was never entered has no metadata yet.
		local out, err = capture(cfg, { "hist", d.nwo, d.rel })
		if out then
			lines = render_history("//" .. d.nwo .. (d.rel ~= "" and ("/" .. d.rel) or ""), out)
		elseif tostring(err):find("open it first", 1, true) then
			lines = {
				ui.Line({ ui.Span("//" .. d.nwo):bold() }),
				ui.Line("Not loaded yet. Press l or Enter to load this repo."),
			}
		else
			lines = { ui.Line({ ui.Span("history unavailable: " .. tostring(err)):fg("red") }) }
		end
	end

	local bound = math.max(0, #lines - job.area.h)
	if job.skip > bound then
		return ya.emit("peek", { bound, only_if = job.file.url, upper_bound = true, scope = job.scope })
	end

	local visible = {}
	for i = job.skip + 1, math.min(#lines, job.skip + job.area.h) do
		visible[#visible + 1] = lines[i]
	end
	ya.preview_widget(job, ui.Text(visible):area(job.area))
end

function M:seek(job)
	local h = tab().current.hovered
	if not h or h.url ~= job.file.url then
		return
	end
	local step = math.floor(job.units * job.area.h / 10)
	step = step == 0 and ya.clamp(-1, job.units, 1) or step
	ya.emit("peek", {
		math.max(0, tab().preview.skip + step),
		only_if = job.file.url,
		scope = job.scope,
	})
end


-- <Tab> popup. For the changed-files popup it draws our table; otherwise it is
-- yazi's stock file / folder info, so <Tab> behaves as usual in the depot view.
function M:spot(job)
	local s = get_status()
	if not (s and s.active and s.pending) then
		return require(job.file.cha.is_dir and "folder" or "file"):spot(job)
	end
	s.pending = false
	set_status(s)

	local rows = {
		ui.Row {
			ui.Line { ui.Span("\u{25B2}"):fg(s.committed and "green" or "yellow") },
			ui.Line { ui.Span((s.header:gsub("\t", " "))):bold() },
		},
		ui.Row {
			"",
			ui.Line { ui.Span(s.committed and "Enter: diff    Esc: close" or "Enter: diff    d: discard    Esc: close"):dim() },
		},
	}
	local colors = { A = "green", M = "yellow", D = "red", R = "cyan" }
	for _, e in ipairs(s.rows) do
		rows[#rows + 1] = ui.Row {
			ui.Line { ui.Span(e.m):fg(colors[e.m] or "white") },
			e.old and (e.p .. "   <- " .. e.old) or e.p,
		}
	end
	if #s.rows == 0 then
		rows[#rows + 1] = ui.Row { "", ui.Line { ui.Span(s.kind == "p4" and "No opened files" or "Working tree clean"):dim() } }
	end

	ya.spot_table(
		job,
		ui.Table(rows)
			:area(ui.Pos { "center", w = 90, h = math.min(#rows + 2, 26) })
			:row(s.cursor)
			:col(1)
			:col_style(th.spot.tbl_col)
			:cell_style(th.spot.tbl_cell)
			:widths { ui.Constraint.Length(3), ui.Constraint.Fill(1) }
	)
end

-- ------------------------------------------------------- navigation actions
local function yn(b)
	return b and "yes" or "no"
end

local function open_depot(cfg)
	local _, _, cwd = hovered()
	if not split(cwd) then
		set_prev(cwd)
	end
	notify("info", "Loading depot list ...", 4)
	local out, err = capture(cfg, { "open-root" })
	if not out then
		return notify("error", err)
	end
	-- First line: the view root. Then "name<TAB>git|p4" per top-level entry and
	-- "!message" for a service that failed (the other one still loads).
	local root
	local kinds, warns = {}, {}
	for l in out:gmatch("[^\n]+") do
		if not root then
			root = l
		elseif l:sub(1, 1) == "!" then
			warns[#warns + 1] = l:sub(2)
		else
			local n, k = l:match("^([^\t]+)\t(%w+)$")
			if n then
				kinds[n] = k
			end
		end
	end
	set_kinds(kinds)
	if next(kinds) == nil and #warns == 0 then
		notify("warn", "Nothing is configured yet: set org and/or p4 in gitp4v_opts in your init.lua (see config.lua).", 10)
	end
	ya.emit("cd", { trim(root), raw = true })
	for _, w in ipairs(warns) do
		notify("error", w, 10)
	end
end

local function restore_sort()
	local s = get_saved()
	if s then
		ya.emit("sort", { s.by, reverse = yn(s.reverse), dir_first = yn(s.dir_first) })
		set_saved(nil)
	end
end

local function close_depot()
	restore_sort()
	local prev = get_prev() or os.getenv("HOME")
	if prev then
		ya.emit("cd", { prev, raw = true })
	end
end

-- Build (or reuse) a repo's shadow tree and go into it, with a loading toast.
local function load_repo(cfg, nwo, force)
	-- The toast is for the first time a repo is entered (or a forced refresh),
	-- not for every later change of directory inside it.
	local announce = force or first_visit(nwo)
	if announce then
		notify("info", "Loading //" .. nwo .. " ...", 4)
	end
	local start = os.time()
	local root, err = capture(cfg, { "open", nwo, force and "force" or nil })
	if not root then
		return notify("error", err)
	end
	local secs = os.difftime(os.time(), start)
	if announce and secs >= 2 then
		notify("info", string.format("Loaded //%s (%ds)", nwo, secs), 2)
	end
	ya.emit("cd", { trim(root), raw = true })
	return true
end

-- Re-fetch a repo's tree (local changes are re-applied) and stay where you were.
local function refresh_keep(cfg, nwo, cwd)
	local _, err = capture(cfg, { "open", nwo, "force" })
	if err then
		return notify("error", err)
	end
	ya.emit("cd", { cwd, raw = true })
end

-- Show a built history directory (center pane), newest commit first.
-- Entries are named "IDX id ..." with a larger IDX for newer commits, so
-- natural descending order puts the newest at the top. Force it for the list
-- and put the user's sort back afterwards.
local function enter_history_dir(dir)
	if not get_saved() then
		set_saved(read_sort())
	end
	ya.emit("sort", { "natural", reverse = "yes", dir_first = "no" })
	ya.emit("escape", { select = true }) -- start with no marks
	ya.emit("cd", { dir, raw = true })
end

-- Go into a git file's history list.
local function open_history(cfg, nwo, rel)
	notify("info", "Loading history of " .. rel .. " ...", 3)
	local dir, err = capture(cfg, { "histdir", nwo, rel })
	if not dir then
		return notify("error", err)
	end
	enter_history_dir(trim(dir))
end

-- View one version or diff two, from marked entries (else the hovered one).
-- The newer version (larger index) is the left side of the diff.
local function act_on_versions(cfg, nwo, file_rel, url, selected)
	local targets = #selected > 0 and selected or { url }

	if #targets > 2 then
		return notify("error", string.format("Diff 2 versions at a time (%d marked)", #targets))
	end

	local vs = {}
	for _, t in ipairs(targets) do
		local v = version(t)
		if not v then
			return notify("warn", "Pick commits from the history list")
		end
		vs[#vs + 1] = v
	end

	local err
	if #vs == 1 then
		err = interactive(cfg, { "read", nwo, file_rel, vs[1].sha, tostring(vs[1].idx) })
	else
		local left, right = vs[1], vs[2]
		if left.idx < right.idx then
			left, right = right, left
		end
		err = interactive(cfg, {
			"diffv", nwo, file_rel,
			left.sha, tostring(left.idx), right.sha, tostring(right.idx),
		})
	end
	if err then
		notify("error", err)
	end
end

-- --------------------------------------------------------- local edit flow
local function pr_info(cfg, nwo)
	local out, err = capture(cfg, { "pr-info", nwo })
	if not out then
		notify("error", err)
		return nil
	end
	local info = {}
	for l in out:gmatch("[^\n]+") do
		local k, v = l:match("^([^\t]+)\t?(.*)$")
		if k then
			info[k] = v
		end
	end
	info.branch = info.branch or ""
	info.pr = info.pr or ""
	info.prstate = info.prstate or ""
	return info
end

-- The repo's review branch, ready for another change. Asks for a name
-- (popup) when there is none yet. Returns nil (after an error popup) when the
-- repo's one commit is still waiting for its pull request to resolve.
local function ensure_branch(cfg, nwo)
	local info = pr_info(cfg, nwo)
	if not info then
		return nil
	end
	local old = info.branch
	if old ~= "" then
		if tonumber(info.ahead) == 0 then
			return old
		end
		if info.pr == "" then
			notify("error", "You've committed " .. old .. " but haven't opened a pull request yet.\nOpen it first (e p) before changing anything else.", 10)
			return nil
		elseif info.prstate == "OPEN" then
			notify("error", "Pull request " .. info.pr .. " is still open.\nWait until it is merged or closed before making more changes.", 10)
			return nil
		end
		notify("info", "The previous pull request is " .. info.prstate:lower() .. "; starting a new branch.", 4)
	end

	local default = (os.getenv("USER") or "user") .. os.date("%Y%m%d")
	if default == old then
		default = default .. "-2"
	end
	local name = input("New branch name for " .. nwo .. ":", default)
	if not name then
		return nil
	end
	if name == old then
		notify("error", "Pick a new name; " .. old .. " already has a commit.", 6)
		return nil
	end
	local plan, perr = capture(cfg, { "plan-branch", nwo, name })
	if not plan then
		notify("error", perr, 8)
		return nil
	end
	local dir, state = plan:match("^(.-)\t(%a+)")
	local label = dir and dir:match("([^/]+)$") or name
	if state == "new" then
		notify("info", "Cloning into " .. label .. " ...", 20)
	else
		notify("info", "Switching to " .. label .. " ...", 4)
	end
	local out, err = capture(cfg, { "start-branch", nwo, name })
	if not out then
		notify("error", err, 8)
		return nil
	end
	if state == "new" then
		notify("info", "Cloned into " .. label, 4)
	end
	-- The previous branch's PR is done: its clone is no longer needed.
	if old ~= "" and info.dir and info.dir ~= "" and not info.dir:find(label, 1, true) then
		capture(cfg, { "clean-clone", info.dir })
	end
	return trim(out)
end

-- Files for d / O / r: marked depot entries of one repo, else the hovered one.
-- Returns nwo, rels or nil, message.
local function view_targets(url, selected)
	local urls = #selected > 0 and selected or { url }
	local nwo, rels = nil, {}
	for _, u in ipairs(urls) do
		local s = split(u)
		if not s or s.kind ~= "view" or not s.repo or s.rel == "" then
			return nil, "Select files inside a repo"
		end
		if nwo and nwo ~= s.nwo then
			return nil, "Marked files are in different repos"
		end
		nwo = s.nwo
		rels[#rels + 1] = s.rel
	end
	return nwo, rels
end

local function do_edit(cfg, nwo, rels)
	if not ensure_branch(cfg, nwo) then
		return
	end
	local args = { "edit", nwo }
	for _, r in ipairs(rels) do
		args[#args + 1] = r
	end
	-- opens with the first opener yazi.toml's rules pick (else $EDITOR)
	local err, code = interactive(with_opener(cfg), args)
	if err then
		notify("error", err)
	elseif code and code ~= 0 then
		notify("error", "Opening the file failed (exit code " .. tostring(code) .. "). The message was shown in the terminal.", 8)
	end
end

local function do_delete(cfg, nwo, rels)
	local shown = "//" .. nwo .. "/" .. rels[1] .. (#rels > 1 and string.format("  (+%d more)", #rels - 1) or "")
	if not confirm("Delete from the repo?", shown .. "\n\nThis removes it on your review branch.") then
		return
	end
	if not ensure_branch(cfg, nwo) then
		return
	end
	for _, r in ipairs(rels) do
		local _, err = capture(cfg, { "rm", nwo, r })
		if err then
			return notify("error", err)
		end
	end
	notify("info", string.format("Deleted %d item(s). Commit with e c.", #rels), 4)
end

local function do_add(cfg, nwo, dir_rel)
	local where = "//" .. nwo .. (dir_rel ~= "" and ("/" .. dir_rel) or "") .. "/"
	local name = input("New file in " .. where, "")
	if not name then
		return
	end
	if not ensure_branch(cfg, nwo) then
		return
	end
	local rel = (dir_rel ~= "" and (dir_rel .. "/") or "") .. name
	local _, err = capture(cfg, { "add", nwo, rel })
	if err then
		return notify("error", err)
	end
	do_edit(cfg, nwo, { rel })
end

local function do_rename(cfg, nwo, rel)
	local dir, base = rel:match("^(.*)/([^/]+)$")
	if not dir then
		dir, base = "", rel
	end
	local name = input("Rename " .. base .. " to:", base)
	if not name or name == base then
		return
	end
	if name:find("/", 1, true) then
		return notify("error", "Enter a new name, not a path.", 6)
	end
	if not ensure_branch(cfg, nwo) then
		return
	end
	local new = (dir ~= "" and (dir .. "/") or "") .. name
	local _, err = capture(cfg, { "mv", nwo, rel, new })
	if err then
		return notify("error", err, 6)
	end
	notify("info", "Renamed " .. base .. " to " .. name .. ". Commit with e c.", 4)
end

local function do_commit(cfg, nwo)
	local info = pr_info(cfg, nwo)
	if not info then
		return
	end
	if info.branch == "" then
		return notify("error", "No changes yet. Edit, add, delete or rename a file first.", 6)
	end
	if tonumber(info.ahead) > 0 then
		return notify("error", "Already committed on " .. info.branch .. ". Open the pull request (e p).", 8)
	end
	if tonumber(info.dirty) == 0 then
		return notify("error", "Nothing to commit on " .. info.branch, 6)
	end
	local msg = input(string.format("Commit message (%s, %s change(s)):", info.branch, info.dirty), "")
	if not msg then
		return
	end
	local out, err = capture(cfg, { "commit", nwo, msg })
	if not out then
		return notify("error", err, 6)
	end
	notify("info", trim(out), 5)
end

local function do_pr(cfg, nwo)
	local info = pr_info(cfg, nwo)
	if not info then
		return
	end
	if info.branch == "" then
		return notify("error", "No changes yet. Edit, add, delete or rename a file first.", 6)
	end
	if tonumber(info.ahead) == 0 then
		return notify("error", "You haven't committed yet. Commit first (e c).", 6)
	end
	if info.pr ~= "" and info.prstate ~= "OPEN" then
		return notify("error", "Pull request " .. info.pr .. " is " .. info.prstate:lower() .. ".\nMake another change to start a new branch.", 8)
	end
	if tonumber(info.dirty) > 0 then
		local ok = confirm(
			"Uncommitted changes",
			string.format("%s change(s) are not committed and will NOT be in the pull request.\n\nContinue anyway?", info.dirty)
		)
		if not ok then
			return
		end
	end

	local title, body = info.subject, ""
	if info.pr == "" then
		title = input("Pull request title (" .. info.branch .. "):", info.subject)
		if not title then
			return
		end
		body = input("Pull request description (optional):", "", true)
		if not body then
			return
		end
	end

	notify("info", "Rebasing if needed and pushing " .. info.branch .. " ...", 10)
	local out, err = capture(cfg, { "pr", nwo, title, body })
	if not out then
		return notify("error", err, 20)
	end
	local url = trim(out)
	ya.clipboard(url)
	notify("info", "Pull request: " .. url .. "  (copied)", 10)
end

local function do_discard(cfg, nwo)
	local info = pr_info(cfg, nwo)
	if not info then
		return
	end
	if info.branch == "" then
		return notify("warn", "No local branch to discard.")
	end
	local ok = confirm(
		"Discard local branch?",
		string.format(
			"Deletes local branch %s and all its changes (%s committed, %s uncommitted).\nA pushed copy on GitHub is not touched.",
			info.branch, info.ahead or "0", info.dirty or "0"
		)
	)
	if not ok then
		return
	end
	local out, err = capture(cfg, { "discard", nwo })
	if not out then
		return notify("error", err, 6)
	end
	notify("info", trim(out), 4)
	restore_sort()
	load_repo(cfg, nwo, true)
end

-- ------------------------------------------------------ changed-files popup
-- The popup is yazi's own spot popup (the one <Tab> opens on a file), drawn by
-- M:spot from the data below. Its rows are: header, hint, then one per changed
-- file; yazi moves the selection, and the [spot] keys in keymap.toml tell us
-- (spot-up / spot-down) so we know which row Enter and d refer to.
local function parse_changes(out)
	local s = { committed = false, header = "", rows = {} }
	for l in out:gmatch("[^\n]+") do
		local kind, a, b, c = l:match("^([^\t]*)\t([^\t]*)\t?([^\t]*)\t?(.*)$")
		if kind == "H" then
			s.committed = a == "1"
			s.header = b .. (c ~= "" and ("\t" .. c) or "")
		elseif kind and kind ~= "" then
			s.rows[#s.rows + 1] = { m = kind, p = a, old = b ~= "" and b or nil }
		end
	end
	return s
end

local function changes_total(s)
	return 2 + math.max(#s.rows, 1)
end

-- Fetch the data and open the popup on the hovered entry.
local function show_changes(cfg, kind, id, cwd, dir_dp)
	local url = hovered()
	if not url then
		return notify("warn", "Hover a file or folder first")
	end
	local out, err = capture(cfg, { kind == "p4" and "p4-status-data" or "status-data", id })
	if not out then
		return notify("error", err)
	end
	local s = parse_changes(out)
	s.active, s.pending, s.kind, s.id, s.cwd, s.dir_dp, s.cursor = true, true, kind, id, cwd, dir_dp, 3
	set_status(s)
	ya.emit("spot", { force = true })
end

-- Re-read the data after a change and redraw the popup.
local function reload_changes(cfg, s)
	local out = capture(cfg, { s.kind == "p4" and "p4-status-data" or "status-data", s.id })
	if out then
		local n = parse_changes(out)
		s.committed, s.header, s.rows = n.committed, n.header, n.rows
	end
	s.cursor = math.max(1, math.min(changes_total(s), s.cursor))
	s.pending = true
	set_status(s)
	ya.emit("spot", { force = true })
end

-- Keys of the spot layer while the popup is open (see keymap.toml).
local function spot_action(cfg, action)
	local s = get_status()
	if action == "spot-closed" then
		set_status(nil)
		if s and s.dirty then
			-- something was discarded: re-list the folder (local adds/deletes changed)
			if s.kind == "p4" then
				P4.refresh(cfg, s.dir_dp, s.cwd)
			else
				refresh_keep(cfg, s.id, s.cwd)
			end
		end
		return
	end
	if not s or not s.active then
		return
	end
	if action == "spot-up" or action == "spot-down" then
		s.cursor = math.max(1, math.min(changes_total(s), s.cursor + (action == "spot-up" and -1 or 1)))
		return set_status(s)
	end

	local e = s.rows[s.cursor - 2]
	if not e then
		return
	end
	if action == "spot-enter" then
		local err
		if s.kind == "p4" then
			err = interactive(cfg, { "p4-status-diff", s.id, e.m, e.p })
		else
			err = interactive(cfg, { "status-diff", s.id, e.m, e.p, e.old or "" })
		end
		return err and notify("error", err)
	elseif action == "spot-d" then
		if s.committed then
			return notify("warn", "Already committed: discard works on uncommitted changes only", 5)
		end
		local verb = s.kind == "p4" and "Revert" or "Discard"
		if not confirm(verb .. "?", verb .. " your change to\n" .. e.p) then
			return
		end
		local out, err
		if s.kind == "p4" then
			out, err = capture(cfg, { "p4-revert-file", s.id, e.p })
		else
			out, err = capture(cfg, { "discard-file", s.id, e.m, e.p, e.old or "" })
		end
		if not out then
			return notify("error", err, 8)
		end
		-- redraw the popup now; the folder listing is refreshed when it closes
		s.dirty = true
		reload_changes(cfg, s)
	end
end

-- Popup listing the files changed on the review branch.
local function do_status(cfg, nwo, cwd)
	local info = pr_info(cfg, nwo)
	if not info then
		return
	end
	if info.branch == "" or (tonumber(info.dirty) == 0 and tonumber(info.ahead) == 0) then
		return notify("info", "Working tree clean", 4)
	end
	show_changes(cfg, "git", nwo, cwd)
end

-- ------------------------------------------------------------ pinned files
-- Rebuild the pinned list on disk and remember each entry's saved path (for
-- the header). Returns the directory.
local function build_pins(cfg)
	local out, err = capture(cfg, { "pin-build" })
	if not out then
		notify("error", err)
		return nil
	end
	local dir
	local pins = {}
	for l in out:gmatch("[^\n]+") do
		if not dir then
			dir = l
		else
			local name, kind, target, saved = l:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
			if name then
				pins[name] = { kind = kind, target = target, saved = saved }
			end
		end
	end
	set_pins(pins)
	return dir, next(pins) == nil
end

local function open_pins(cfg)
	local _, _, cwd = hovered()
	if not split(cwd) then
		set_prev(cwd)
	end
	notify("info", "Loading pinned files ...", 4)
	local dir, empty = build_pins(cfg)
	if not dir then
		return
	end
	if empty then
		notify("info", "No pinned files yet. Press E on a file to pin it.", 6)
	end
	ya.emit("cd", { dir, raw = true })
end

-- E: pin the hovered / marked files, or unpin them if already pinned.
-- Depot files (git or p4) are pinned as "view the current version"; local
-- files as a symlink. In the pinned list it unpins the hovered entry.
local function do_pin(cfg, url, is_dir, selected, cwd_disp, here, d, in_hist)
	local items = {} -- { kind=, target=, saved= }

	if here and here.kind == "pinned" then
		local rec = d and d.name and get_pins()[d.name]
		if not rec then
			return notify("warn", "Hover a pinned file to unpin it")
		end
		items[1] = rec
	elseif in_hist then
		if vendor_of(cfg, here.owner) == "p4" then
			items[1] = {
				kind = "p4",
				target = "//" .. here.rest,
				saved = "//" .. (here.rest:match("^(.*)/[^/]+$") or here.rest),
			}
		else
			local dir = here.rel:match("^(.*)/[^/]+$") or ""
			items[1] = {
				kind = "depot",
				target = here.nwo .. ":" .. here.rel,
				saved = "//" .. here.nwo .. (dir ~= "" and ("/" .. dir) or ""),
			}
		end
	elseif #selected == 0 and (not url or is_dir) then
		return notify("warn", "Hover a file to pin it")
	else
		for _, u in ipairs(#selected > 0 and selected or { url }) do
			local s = split(u)
			if s and s.kind == "view" and s.owner and vendor_of(cfg, s.owner) == "p4" then
				if s.rest and s.rest:find("/", 1, true) then
					items[#items + 1] = { kind = "p4", target = "//" .. s.rest, saved = cwd_disp }
				end
			elseif s and s.kind == "view" and s.repo and s.rel ~= "" then
				items[#items + 1] = { kind = "depot", target = s.nwo .. ":" .. s.rel, saved = cwd_disp }
			elseif not s then
				items[#items + 1] = { kind = "local", target = u, saved = cwd_disp }
			end
		end
		if #items == 0 then
			return notify("warn", "Select files to pin")
		end
	end

	local pinned, unpinned = 0, 0
	for _, it in ipairs(items) do
		local out, err = capture(cfg, { "pin-toggle", it.kind, it.target, it.saved })
		if not out then
			return notify("error", err)
		end
		if trim(out) == "pinned" then
			pinned = pinned + 1
		else
			unpinned = unpinned + 1
		end
	end

	local parts = {}
	if pinned > 0 then
		parts[#parts + 1] = string.format("Pinned %d file(s)", pinned)
	end
	if unpinned > 0 then
		parts[#parts + 1] = string.format("Unpinned %d file(s)", unpinned)
	end
	notify("info", table.concat(parts, ", "), 3)

	if here and here.kind == "pinned" then
		local dir = build_pins(cfg)
		if dir then
			ya.emit("cd", { dir, raw = true })
		end
	end
end

-- The `e` menu. Does nothing outside the depot view.
local function menu(cfg, here, d, cwd)
	local vend = here.owner and vendor_of(cfg, here.owner)
	if vend == "p4" then
		-- the folder (or file) we are in, as a depot path
		local dp = "//" .. here.rest
		local dir_dp = here.kind == "commits" and (dp:match("^(.*)/[^/]+$") or dp) or dp
		local dir_cwd = here.kind == "commits" and (cwd:gsub("/gitp4v/commits/", "/gitp4v/view/", 1):match("^(.*)/[^/]+$") or cwd) or cwd
		return P4.menu(cfg, dp, dir_dp, dir_cwd)
	end
	local nwo = (here and here.nwo) or (d and d.nwo)
	local cands, acts = {}, {}
	local function add(on, desc, act)
		cands[#cands + 1] = { on = on, desc = desc }
		acts[#acts + 1] = act
	end
	if nwo then
		add("c", "Commit changes", "commit")
		add("p", "Open pull request", "pr")
		add("s", "Show changed files", "status")
		add("x", "Discard local branch and changes", "discard")
		add("l", "Refresh this repo", "refresh")
	end
	add("q", "Leave the depot view", "close")

	local idx = ya.which { cands = cands }
	local act = idx and acts[idx]
	if act == "commit" then
		do_commit(cfg, nwo)
	elseif act == "pr" then
		do_pr(cfg, nwo)
	elseif act == "status" then
		do_status(cfg, nwo, cwd)
	elseif act == "discard" then
		do_discard(cfg, nwo)
	elseif act == "refresh" then
		restore_sort()
		load_repo(cfg, nwo, true)
	elseif act == "close" then
		close_depot()
	end
end

P4 = require("gitp4v.p4").new {
	trim = trim,
	notify = notify,
	fail = function(_, msg, timeout) return notify("error", msg, timeout) end,
	capture = capture,
	interactive = interactive,
	show_changes = show_changes,
	with_opener = with_opener,
	first_visit = first_visit,
	input = input,
	confirm = confirm,
	version = version,
	enter_history_dir = enter_history_dir,
	close_depot = close_depot,
}

function M:entry(job)
	local action = job.args[1]
	local cfg = get_cfg()

	if action:sub(1, 5) == "spot-" then
		return spot_action(cfg, action)
	end

	if action == "depot" then
		return open_depot(cfg)
	elseif action == "pins" then
		return open_pins(cfg)
	end

	local url, is_dir, cwd, selected, cwd_disp = hovered()
	local here = split(cwd)
	local d = split(url or cwd)

	-- git or p4 (decided by the depot-view root entry we are under / hovering)
	local tree_owner = (here and (here.kind == "view" or here.kind == "commits") and here.owner)
		or (d and d.kind == "view" and d.owner)
	local vend = tree_owner and vendor_of(cfg, tree_owner) or nil

	local in_hist = here and here.kind == "commits" and here.rest ~= nil
	local in_repo = here and here.kind == "view" and here.repo ~= nil
	local on_depot_file = d and d.kind == "view" and d.repo and d.rel ~= "" and url and not is_dir
	local on_repo_root = d and d.kind == "view" and d.repo and d.rel == "" and url and is_dir

	-- Inside a history list the file is the cwd's path.
	local nwo = in_hist and here.nwo or (d and d.nwo)
	local file_rel = in_hist and here.rel or (d and d.rel)

	if action == "pin" then
		return do_pin(cfg, url, is_dir, selected, cwd_disp, here, d, in_hist)
	end

	-- In the pinned list: depot pins are view-only, local pins open normally.
	local in_pinned = here and here.kind == "pinned"
	if in_pinned then
		local rec = d and d.name and get_pins()[d.name]
		local is_depot = rec and (rec.kind == "depot" or rec.kind == "p4")
		if action == "o" then
			if not is_depot then
				return ya.emit("open", {})
			end
			local err
			if rec.kind == "p4" then
				err = interactive(cfg, { "p4-print", rec.target })
			else
				local pnwo, prel = rec.target:match("^([^:]+):(.+)$")
				err = interactive(cfg, { "read", pnwo, prel })
			end
			return err and notify("error", err)
		elseif action == "O" then
			if is_depot then
				return notify("warn", "Pinned depot files are view-only. Open the file in its depot to edit it.", 6)
			end
			return ya.emit("open", { interactive = true })
		elseif action == "h" then
			return close_depot()
		elseif action == "a" or action == "d" or action == "r" then
			return notify("warn", "This is the pinned list: press E to unpin the hovered file")
		end
	end

	-- Perforce depots: browsing is lazy per folder, editing uses p4 workspaces.
	-- (`e` and `h` are shared with git and handled below.)
	if vend == "p4" and action ~= "e" and action ~= "h" and action ~= "pin" then
		local p4_hist = here and here.kind == "commits"
		local hov_dp = (d and d.kind == "view" and d.rest) and ("//" .. d.rest) or nil
		local cwd_dp = (here and here.rest) and ("//" .. here.rest) or nil

		-- marked (else hovered) depot paths of files and folders under a depot
		local function marked_paths()
			local dps = {}
			for _, u in ipairs(#selected > 0 and selected or { url }) do
				local s = split(u)
				if s and s.kind == "view" and s.rest and s.rest:find("/", 1, true) then
					dps[#dps + 1] = "//" .. s.rest
				end
			end
			return dps
		end

		if action == "l" or action == "o" then
			if p4_hist then
				if action == "o" then
					return P4.versions(cfg, cwd_dp, url, selected)
				end
				return ya.emit("enter", {})
			elseif not hov_dp or not url then
				return ya.emit(action == "l" and "enter" or "open", {})
			elseif is_dir then
				return P4.load_dir(cfg, hov_dp)
			elseif action == "l" then
				return P4.open_history(cfg, hov_dp)
			end
			return P4.read(cfg, hov_dp)

		elseif action == "O" then
			if p4_hist then
				return P4.edit(cfg, { cwd_dp })
			elseif not url or is_dir then
				return ya.emit("open", { interactive = true })
			end
			local dps = marked_paths()
			if #dps == 0 then
				return notify("warn", "Select files inside a depot folder")
			end
			return P4.edit(cfg, dps)

		elseif action == "a" then
			if p4_hist or not cwd_dp then
				return notify("warn", "Open a depot folder first to add a file")
			end
			return P4.add(cfg, cwd_dp)

		elseif action == "d" then
			if p4_hist then
				return notify("warn", "Go back to the file list to delete files (h)")
			end
			local dps = marked_paths()
			if #dps == 0 then
				return notify("warn", "Select files or folders inside a depot folder")
			end
			return P4.delete(cfg, dps)

		elseif action == "r" then
			if p4_hist then
				return notify("warn", "Go back to the file list to rename files (h)")
			end
			local dps = marked_paths()
			if #dps ~= 1 then
				return notify("warn", "Rename one file or folder at a time")
			end
			return P4.rename(cfg, dps[1])
		end
	end

	if action == "e" then
		if not here then
			return -- nothing outside the plugin
		end
		return menu(cfg, here, d, cwd)

	elseif action == "l" then
		if on_repo_root then
			return load_repo(cfg, d.nwo)
		elseif on_depot_file then
			return open_history(cfg, d.nwo, d.rel)
		end
		return ya.emit("enter", {})

	elseif action == "h" then
		if in_hist then
			restore_sort()
			ya.emit("escape", { select = true }) -- drop the version marks
			local viewurl = cwd:gsub("/gitp4v/commits/", "/gitp4v/view/", 1)
			return ya.emit("reveal", { viewurl, raw = true })
		end
		return ya.emit("leave", {})

	elseif action == "o" then
		if in_hist then
			return act_on_versions(cfg, nwo, file_rel, url, selected)
		elseif on_repo_root then
			return load_repo(cfg, d.nwo)
		elseif not on_depot_file then
			return ya.emit("open", {})
		end
		local err = interactive(cfg, { "read", d.nwo, d.rel })
		return err and notify("error", err)

	elseif action == "O" then
		if in_hist then
			return do_edit(cfg, nwo, { file_rel })
		elseif not on_depot_file then
			return ya.emit("open", { interactive = true })
		end
		local tnwo, rels = view_targets(url, selected)
		if not tnwo then
			return notify("warn", rels)
		end
		return do_edit(cfg, tnwo, rels)

	elseif action == "a" then
		if not here then
			return ya.emit("create", {})
		elseif not in_repo then
			return notify("warn", "Open a repo first to add a file")
		end
		return do_add(cfg, here.nwo, here.rel)

	elseif action == "d" then
		if not here then
			return ya.emit("remove", {})
		elseif in_hist then
			return notify("warn", "Go back to the file list to delete files (h)")
		elseif not in_repo then
			return notify("warn", "Open a repo first to delete files")
		end
		local tnwo, rels = view_targets(url, selected)
		if not tnwo then
			return notify("warn", rels)
		end
		return do_delete(cfg, tnwo, rels)

	elseif action == "r" then
		if not here then
			return ya.emit("rename", { cursor = "before_ext" })
		elseif in_hist then
			return notify("warn", "Go back to the file list to rename files (h)")
		elseif not in_repo then
			return notify("warn", "Open a repo first to rename files")
		end
		local tnwo, rels = view_targets(url, selected)
		if not tnwo then
			return notify("warn", rels)
		elseif #rels > 1 then
			return notify("warn", "Rename one file at a time")
		end
		return do_rename(cfg, tnwo, rels[1])
	end

	notify("warn", "Unknown gitp4v action: " .. tostring(action))
end

return M
