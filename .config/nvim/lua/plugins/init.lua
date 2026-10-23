return {
  -----------------------------------------------
  --- example
  -----------------------------------------------
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -------------------------
  --- language grammar
  -------------------------
  {
    "nvim-treesitter/nvim-treesitter",
      opts = {
      ensure_installed = {
        "vim",
        "lua",
        "vimdoc",
        "html",
        "css",
        "markdown",
        "markdown_inline",
        "latex",
        "yaml",
        "verilog",
        "systemverilog",
        "ruby",
      },
    },
  },

  --------------------------------
  --- set fzf to search dotfiles
  --------------------------------
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      pickers = {
        find_files = {
          hidden = true,
          find_command = { "rg", "--files", "--hidden", "--glob", "!.git/*" },
        },
      },
    },
  },

  -------------------------
  --- markdown rendering
  -------------------------
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" }, --loads only for markdown files
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim" },
    opts = {},
  },

  ----------------------------
  --- show modified in nvtree
  ----------------------------
  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      modified = {
        enable = true,
        show_on_dirs = true,
      },
    },
  },

  ------------------------
  --- auto-save sessions
  ------------------------
  {
    "rmagatti/auto-session",
    lazy = false,
    ---enables autocomplete for opts
    ---@module "auto-session"
    ---@type AutoSession.Config
    opts = {
      suppressed_dirs = { },
      -- log_level = 'debug',
    },
  },

  -------------------------------------------------------
  --- use "vi" in integrated terminal to open files above
  -------------------------------------------------------
  {
    "willothy/flatten.nvim",
    lazy = false,
    priority = 1001,
    opts = function()
      return {
        window = {
          open = "alternate"
        },
        hooks = {
          post_open = function(context)
            if context and context.winnr then
              vim.schedule(function()
                pcall(vim.api.nvim_set_current_win, context.winnr)
              end)
            end
          end,
        }
      }
    end
  },

  {
    "yaocccc/visual-multi.nvim",
    lazy = false,
    opts = {
      -- Rebuild the multicursor bar with NvChad's onedark highlight groups so
      -- it matches the native statusline (mode pill, powerline separators).
      statusline = function(info)
        local roles = {
          NORMAL = "Normal",
          INSERT = "Insert",
          EXTEND = "Visual",
        }
        local role = roles[info.mode] or "Normal"
        local label = info.mode .. "-MULTI"

        local mode = ("%%#St_%sMode# \u{E7C5} %s %%#St_%sModeSep#\u{E0BC}")
          :format(role, label, role)
        local count = ("%%#St_file# %d/%d "):format(info.current, info.total)

        local text = info.text or info.pattern or ""
        text = vim.fn.strcharpart(text, 0, 24):gsub("%%", "%%%%"):gsub("\n", "\u{21B5}")
        local extra = text ~= "" and ("%%#St_gitIcons# %s "):format(text) or ""

        return mode .. count .. extra .. "%*"
      end,
      highlights = {
        selection = "Visual",
        selection_active = { bg = "#81A1C1", fg = "#1e222a" },
        cursor = { bg = "#a3b8ef", fg = "#1e222a" },
        cursor_active = { bg = "#81A1C1", fg = "#1e222a" },
        insert = { bg = "#3e4451" },
        insert_active = { bg = "#c882e7", fg = "#1e222a" },
      },
    },
    config = function(_, opts)
      local vm = require "visual-multi"
      vm.setup(opts)

      -- Make <C-x> toggle: remove the region under the selector if one exists,
      -- otherwise add a cursor at the current position.
      local Session = require "visual-multi.session"
      local add_cursor = Session.add_cursor_at_current
      Session.add_cursor_at_current = function(self)
        if self:_region_index_at_cursor() then
          self:remove_current()
        else
          add_cursor(self)
        end
      end
    end,
  },

}
