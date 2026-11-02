-- Perforce half of the gitp4v plugin. Loaded by main.lua as
--   local P4 = require("gitp4v.p4").new(ctx)
-- ctx carries the shared helpers (capture, interactive, notify, fail, input,
-- confirm, ...) so the plugin state (ya.sync) stays in main.lua.
--
-- Wording follows Perforce: workspace, CL#, default changelist, pending (not
-- submitted), shelved, submit, revert.
--
-- Depot paths: the shadow tree view/<depot>/<dirs...> maps to //<depot>/<dirs...>.

local function new(ctx)
	local P = {}
	local trim, notify, fail, capture, interactive = ctx.trim, ctx.notify, ctx.fail, ctx.capture, ctx.interactive

	local function dirname(p)
		return p:match("^(.*)/[^/]+$") or p
	end

	-- key<TAB>value lines from p4-info
	local function info_of(cfg, dp)
		local out, err = capture(cfg, { "p4-info", dp })
		if not out then
			fail(cfg, err)
			return nil
		end
		local info = {}
		for l in out:gmatch("[^\n]+") do
			local k, v = l:match("^([^\t]+)\t?(.*)$")
			if k then
				info[k] = v
			end
		end
		info.root = info.root or ""
		info.cl = info.cl or ""
		info.default = tonumber(info.default or "0") or 0
		return info
	end
	P.info = info_of

	-- The workspace covering a path; asks (popup) for a workspace root the first time.
	local function ensure_ws(cfg, dp, dir_default)
		local info = info_of(cfg, dp)
		if not info then
			return nil
		end
		if info.root ~= "" then
			return info
		end
		local root = ctx.input("Workspace root (depot folder) for " .. dp .. ":", dir_default)
		if not root then
			return nil
		end
		root = root:gsub("/+$", "")
		if not root:match("^//[^/]+") then
			notify("error", "The workspace root must be a depot path like //depot/folder", 8)
			return nil
		end
		if not (dp == root or dp:sub(1, #root + 1) == root .. "/") then
			notify("error", root .. " does not contain " .. dp, 8)
			return nil
		end
		notify("info", "Creating workspace for " .. root .. " ...", 8)
		local out, err = capture(cfg, { "p4-ws-create", root })
		if not out then
			fail(cfg, err, 10)
			return nil
		end
		local client, lr = out:match("^([^\t\n]+)\t([^\n]*)")
		notify("info", "Workspace " .. (client or "") .. " ready in " .. (lr or ""), 6)
		return info_of(cfg, dp)
	end

	-- One pending numbered CL at a time.
	local function ensure_free(info)
		if info.cl ~= "" then
			notify("error", "CL " .. info.cl .. " is pending (not submitted).\nSubmit it (e p) or revert it (e x) before changing more files.", 10)
			return false
		end
		return true
	end

	-- ------------------------------------------------------------ browsing
	function P.load_dir(cfg, dp, force)
		-- Announce only the first entry into a depot (or a forced refresh), not
		-- every folder change inside it.
		if force or (dp:match("^//[^/]+$") and ctx.first_visit(dp)) then
			notify("info", "Loading " .. dp .. " ...", 4)
		end
		local root, err = capture(cfg, { "p4-list", dp, force and "force" or nil })
		if not root then
			return fail(cfg, err)
		end
		ya.emit("cd", { trim(root), raw = true })
		return true
	end

	function P.open_history(cfg, dp)
		notify("info", "Loading history of " .. dp:match("([^/]+)$") .. " ...", 3)
		local dir, err = capture(cfg, { "p4-histdir", dp })
		if not dir then
			return fail(cfg, err)
		end
		ctx.enter_history_dir(trim(dir))
	end

	function P.read(cfg, dp)
		local err = interactive(cfg, { "p4-print", dp })
		return err and fail(cfg, err)
	end

	-- View one revision or diff two; the newer (larger rev) is the left side.
	function P.versions(cfg, dp, url, selected)
		local targets = #selected > 0 and selected or { url }
		if #targets > 2 then
			return notify("error", string.format("Diff 2 revisions at a time (%d marked)", #targets))
		end
		local vs = {}
		for _, t in ipairs(targets) do
			local v = ctx.version(t)
			if not v then
				return notify("warn", "Pick revisions from the history list")
			end
			vs[#vs + 1] = v
		end
		local err
		if #vs == 1 then
			err = interactive(cfg, { "p4-print", dp, tostring(vs[1].idx) })
		else
			local left, right = vs[1], vs[2]
			if left.idx < right.idx then
				left, right = right, left
			end
			err = interactive(cfg, { "p4-diffv", dp, tostring(left.idx), tostring(right.idx) })
		end
		if err then
			fail(cfg, err)
		end
	end

	-- ------------------------------------------------------- change files
	function P.edit(cfg, dps)
		local info = ensure_ws(cfg, dps[1], dirname(dps[1]))
		if not info or not ensure_free(info) then
			return
		end
		local args = { "p4-checkout" }
		for _, d in ipairs(dps) do
			args[#args + 1] = d
		end
		local out, err = capture(cfg, args)
		if not out then
			return fail(cfg, err, 12)
		end
		local eargs = { "p4-editor" }
		for l in out:gmatch("[^\n]+") do
			eargs[#eargs + 1] = l
		end
		local e2 = interactive(ctx.with_opener(cfg), eargs)
		if e2 then
			fail(cfg, e2)
		end
	end

	function P.add(cfg, dir_dp)
		local name = ctx.input("New file in " .. dir_dp .. "/", "")
		if not name then
			return
		end
		local dp = dir_dp .. "/" .. name
		local info = ensure_ws(cfg, dp, dir_dp)
		if not info or not ensure_free(info) then
			return
		end
		local out, err = capture(cfg, { "p4-add", dp })
		if not out then
			return fail(cfg, err, 10)
		end
		notify("info", "Added " .. name .. " (default changelist)", 3)
		local e2 = interactive(ctx.with_opener(cfg), { "p4-editor", trim(out) })
		if e2 then
			fail(cfg, e2)
		end
	end

	function P.delete(cfg, dps)
		local shown = dps[1] .. (#dps > 1 and string.format("  (+%d more)", #dps - 1) or "")
		if not ctx.confirm("Delete from the depot?", shown .. "\n\nThis opens it for delete in your workspace (nothing is submitted).") then
			return
		end
		local info = ensure_ws(cfg, dps[1], dirname(dps[1]))
		if not info or not ensure_free(info) then
			return
		end
		for _, d in ipairs(dps) do
			local _, err = capture(cfg, { "p4-rm", d })
			if err then
				return fail(cfg, err, 10)
			end
		end
		notify("info", string.format("Opened %d item(s) for delete. Create a CL with e c.", #dps), 4)
	end

	function P.rename(cfg, dp)
		local base = dp:match("([^/]+)$")
		local name = ctx.input("Rename " .. base .. " to:", base)
		if not name or name == base then
			return
		end
		if name:find("/", 1, true) then
			return notify("error", "Enter a new name, not a path.", 6)
		end
		local info = ensure_ws(cfg, dp, dirname(dp))
		if not info or not ensure_free(info) then
			return
		end
		local _, err = capture(cfg, { "p4-mv", dp, dirname(dp) .. "/" .. name })
		if err then
			return fail(cfg, err, 10)
		end
		notify("info", "Renamed " .. base .. " to " .. name .. " (default changelist)", 4)
	end

	-- ---------------------------------------------------------- changelists
	local refresh -- defined below (re-lists a folder); used by submit_cl

	local function no_ws(info)
		if info.root == "" then
			notify("error", "No workspace here yet. Edit, add or delete a file first (or press e w).", 6)
			return true
		end
	end

	local function create_cl(cfg, dp)
		local info = info_of(cfg, dp)
		if not info or no_ws(info) then
			return
		end
		if info.cl ~= "" then
			return notify("error", "CL " .. info.cl .. " already exists (not submitted). Submit it (e p).", 8)
		end
		if info.default == 0 then
			return notify("error", "No files are opened in the default changelist.", 6)
		end
		local desc = ctx.input(string.format("CL description (%d file(s) from the default changelist):", info.default), "")
		if not desc then
			return
		end
		local out, err = capture(cfg, { "p4-cl-create", dp, desc })
		if not out then
			return fail(cfg, err, 10)
		end
		notify("info", trim(out) .. " (pending, not submitted)", 6)
	end

	local function submit_cl(cfg, dp, dir_dp, cwd)
		local info = info_of(cfg, dp)
		if not info or no_ws(info) then
			return
		end
		if info.cl == "" then
			return notify("error", "You haven't created a changelist yet. Press e c first.", 6)
		end
		local ok = ctx.confirm(
			"Submit CL " .. info.cl .. "?",
			string.format("%s\n\n%s file(s). Submitting sends them to the depot and cannot be undone here.", info.cldesc or "", info.clfiles or "?")
		)
		if not ok then
			return
		end
		notify("info", "Submitting CL " .. info.cl .. " ...", 20)
		local out, err = capture(cfg, { "p4-submit", dp })
		if not out then
			return fail(cfg, err, 25)
		end
		notify("info", trim(out) .. " (workspace deleted)", 8)
		refresh(cfg, dir_dp, cwd)
	end

	local function shelve_cl(cfg, dp)
		local info = info_of(cfg, dp)
		if not info or no_ws(info) then
			return
		end
		if info.cl == "" then
			return notify("error", "You haven't created a changelist yet. Press e c first.", 6)
		end
		notify("info", "Shelving CL " .. info.cl .. " ...", 10)
		local out, err = capture(cfg, { "p4-shelve", dp })
		if not out then
			return fail(cfg, err, 12)
		end
		notify("info", trim(out), 6)
	end

	-- Re-list the current directory and stay in it.
	function refresh(cfg, dir_dp, cwd)
		local _, err = capture(cfg, { "p4-list", dir_dp, "force" })
		if err then
			return fail(cfg, err)
		end
		ya.emit("cd", { cwd, raw = true })
	end

	local function show_opened(cfg, dp, dir_dp, cwd)
		local info = info_of(cfg, dp)
		if not info then
			return
		end
		if info.root == "" or (info.default == 0 and info.cl == "") then
			return notify("info", "No opened files", 4)
		end
		-- yazi's own popup (the <Tab> one), drawn by main.lua
		ctx.show_changes(cfg, "p4", info.root, cwd, dir_dp)
	end

	local function revert_all(cfg, dp, dir_dp, cwd)
		local info = info_of(cfg, dp)
		if not info or no_ws(info) then
			return
		end
		local what = info.cl ~= "" and ("CL " .. info.cl .. " and all its files") or "all files in the default changelist"
		local ok = ctx.confirm("Revert?", "Reverts " .. what .. ", deletes the pending CL and deletes this workspace\n(its client and local folder). Your local edits are discarded.")
		if not ok then
			return
		end
		local out, err = capture(cfg, { "p4-discard", dp })
		if not out then
			return fail(cfg, err, 10)
		end
		notify("info", trim(out), 5)
		refresh(cfg, dir_dp, cwd)
	end

	-- Delete the workspace (client and its local files) once you are done with it.
	local function delete_workspace(cfg, dp, dir_dp, cwd)
		local info = info_of(cfg, dp)
		if not info or no_ws(info) then
			return
		end
		local ok = ctx.confirm(
			"Delete workspace?",
			"Deletes the workspace " .. info.client .. " and all its local files in\n" .. (info["local"] or "") ..
				"\n\nIt must have no opened files or pending CL."
		)
		if not ok then
			return
		end
		local out, err = capture(cfg, { "p4-ws-delete", dp })
		if not out then
			return fail(cfg, err, 10)
		end
		notify("info", trim(out), 5)
		refresh(cfg, dir_dp, cwd)
	end

	local function make_workspace(cfg, dir_dp)
		local info = info_of(cfg, dir_dp)
		if not info then
			return
		end
		if info.root ~= "" then
			return notify("info", "A workspace already covers this folder: " .. info.root, 6)
		end
		ensure_ws(cfg, dir_dp, dir_dp)
	end

	-- The `e` menu inside a p4 depot. dp: depot path of the current folder
	-- (or of the file whose history is open); dir_dp: the folder to refresh.
	function P.menu(cfg, dp, dir_dp, cwd)
		local cands = {
			{ on = "c", desc = "Create changelist (from default)" },
			{ on = "p", desc = "Submit changelist" },
			{ on = "v", desc = "Shelve changelist" },
			{ on = "s", desc = "Show opened files" },
			{ on = "x", desc = "Revert all (discard changelist)" },
			{ on = "w", desc = "Make this folder a workspace root" },
			{ on = "D", desc = "Delete this workspace (client + local files)" },
			{ on = "l", desc = "Refresh this folder" },
			{ on = "q", desc = "Leave the depot view" },
		}
		local idx = ya.which { cands = cands }
		if idx == 1 then
			create_cl(cfg, dp)
		elseif idx == 2 then
			submit_cl(cfg, dp, dir_dp, cwd)
		elseif idx == 3 then
			shelve_cl(cfg, dp)
		elseif idx == 4 then
			show_opened(cfg, dp, dir_dp, cwd)
		elseif idx == 5 then
			revert_all(cfg, dp, dir_dp, cwd)
		elseif idx == 6 then
			make_workspace(cfg, dir_dp)
		elseif idx == 7 then
			delete_workspace(cfg, dp, dir_dp, cwd)
		elseif idx == 8 then
			refresh(cfg, dir_dp, cwd)
		elseif idx == 9 then
			ctx.close_depot()
		end
	end

	P.refresh = refresh

	return P
end

return { new = new }
