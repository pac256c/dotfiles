require "nvchad.autocmds"

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

--------------------------------------------------------------
--- Forward bells out
--------------------------------------------------------------
vim.api.nvim_create_autocmd("TermClose", {
  desc =  "pass terminal bell from embedded terminal out to tmux",
  callback = function()
    -- check if the request contains ascii bell (\x07)
    vim.fn.system("printf '\007' > /dev/pts/1 2>&1 | tail -1")
    -- if vim.env.TMUX then
    --  vim.fn.system("tmux set-window-option alert-activity on 2>/dev/null || tmux refresh-client -S")
    -- end
  end,
})

