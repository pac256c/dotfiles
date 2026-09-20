require "nvchad.autocmds"

-------------------------------------------------------------
--- Automatically set name to "snippet".md in new file
-------------------------------------------------------------
-- local is_updating_name = false
-- local tabufline_updater = vim.api.nvim_create_augroup("TabuflineTitleFix", { clear = true })
-- vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
--   group = tabufline_updater,
--   pattern = "*",
--   callback = function(ev)
--     -- 1. Prevent the infinite loop
--     if is_updating_name then return end
--
--     -- Only target normal, unsaved buffers
--     local current_title = vim.api.nvim_buf_get_name(ev.buf)
--     local unsaved = (current_title == "") or (vim.uv.fs_stat(current_title) == nil)
--
--     if vim.bo[ev.buf].buftype == "" and unsaved then
--       -- 2. Safely get the first line without triggering indexing errors
--       local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, 1, false)
--       local title = (lines and lines[1]) or ""
--
--       -- Apply fallback if currently empty
--       if #title == 0 then
--         title = "Untitled"
--       end
--
--       -- Clean up all special characters and trim whitespace
--       local preview = title:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%c%s]+", " ")
--
--       -- Truncate to a reasonable preview length
--       if #preview > 15 then
--         preview = string.sub(preview, 1, 15)
--       end
--
--       -- Append an extension or unique buffer ID to prevent duplicate name errors
--       preview = preview .. "_" .. ev.buf .. ".md"
--
--       -- Only rename if the title actually changed to reduce unnecessary overhead
--       if current_title ~= preview and #preview > 0 then
--         is_updating_name = true
--         pcall(vim.api.nvim_buf_set_name, ev.buf, preview)
--         is_updating_name = false
--       end
--
--       vim.schedule(function()
--         vim.cmd("redrawtabline")
--       end)
--     end
--   end,
-- })

-------------------------------------------------------------
--- Auto-save session
-------------------------------------------------------------
local auto_session_group = vim.api.nvim_create_augroup("AutoSessionSaveOnEdit", { clear = true })
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  group = auto_session_group,
  pattern = "*",
  callback = function()
    -- Auto Save
    require("auto-session").save_session()
  end,
})


--------------------------------------------------------------
--- Force updating git status
--------------------------------------------------------------
-- Automatically check for changes when focus is gained or buffers are entered
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "TermClose" }, {
  pattern = "*",
  callback = function()
    if package.loaded["nvim-tree"] then
      require("nvim-tree.api").tree.reload()
    end
  end,
})
