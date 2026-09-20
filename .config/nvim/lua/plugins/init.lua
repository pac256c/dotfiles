return {
  -----------------------------------------------
  --- Example
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
  --- Language Grammar
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
      },
    },
  },

  -------------------------
  --- Markdown Rendering
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

  -- {
  -- "willothy/flatten.nvim",
  --   lazy = false,
  --   priority = 1001,
  --   opts = {
  --     window = {
  --       -- Forces flatten to look for your main editing window above/beside the terminal
  --       open = "alternate"
  --     },
  --     hooks = {
  --       -- Runs safely AFTER the file is cleanly routed to your main buffer window
  --       post_open = function(context)
  --         local status, nvterm = pcall(require, "nvterm.terminal")
  --         if status then
  --           nvterm.toggle("horizontal")
  --         end
  --
  --         if context and context.winnr then
  --           vim.schedule(function ()
  --           pcall(vim.api.nvim_set_current_win, context.winnr)
  --           end)
  --         end
  --       end,
  --     }
  --   }
  -- },


  {
    "willothy/flatten.nvim",
    lazy = false,
    priority = 1001,
    opts = function()
      -- Create a persistent variable within the plugin scope to track terminal type
      local active_term_type = "horizontal"

      return {
        window = {
          open = "alternate"
        },
        hooks = {
          pre_open = function()
            -- Grab the terminal window you are currently typing inside of
            local current_win = vim.api.nvim_get_current_win()
            local win_config = vim.api.nvim_win_get_config(current_win)

            if win_config.relative ~= "" then
              -- The window is relative to the editor grid, meaning it's a float
              active_term_type = "float"
            else
              -- If it's a standard tile split, check its dimension bounds
              local win_width = vim.api.nvim_win_get_width(current_win)
              local total_width = vim.o.columns

              -- If it spans most of the screen width, it's a horizontal split
              if win_width >= (total_width - 2) then
                active_term_type = "horizontal"
              else
                active_term_type = "vertical"
              end
            end
          end,

          post_open = function(context)
            local status, nvterm = pcall(require, "nvterm.terminal")
            if status then
              -- Dynamically toggle the exact terminal variant that triggered the file open
              nvterm.toggle(active_term_type)
            end

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

}
