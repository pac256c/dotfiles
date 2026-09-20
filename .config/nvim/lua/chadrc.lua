-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
        theme = "onedark",

        -- hl_override = {
        --      Comment = { italic = true },
        --      ["@comment"] = { italic = true },
        -- },
}

-- M.nvdash = { load_on_startup = true }

M.ui = {
  -- This disables the top buffer bar entirely if you haven't already
  -- tabufline = { enabled = false },

  statusline = {
    -- Override the modules within NvChad's default statusline setup
    order = { "mode", "file", "git", "%=", "lsp_msg", "%=", "diagnostics", "lsp", "cwd", "cursor" },
    modules = {
      file = function()
        local fn = vim.fn
        local filename = fn.expand "%:t"

        -- Default text if buffer is empty
        if filename == "" then
          filename = "No Name"
        end

        -- Add your modified status indicator (e.g., a small dot symbol  or a clear text indicator)
        local modified = vim.bo.modified and " " or ""

        -- Get the web-devicon if available
        local icon = "    "
        local devicons_present, devicons = pcall(require, "nvim-web-devicons")
        if devicons_present then
          local ft_icon, ft_color = devicons.get_icon(filename)
          if ft_icon then
            icon = " " .. ft_icon .. " "
          end
        end

        -- Return the formatted text block utilizing NvChad's default file highlights
        return "%#St_file_bg#" .. icon .. "%#St_file_txt#" .. filename .. "%#St_file_msg#" .. modified .. " "
      end
    }
  }
}

return M
