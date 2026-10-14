require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

local function open_chat_term()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf)
      and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t") == "chat" then
      if vim.b[buf].terminal_job_id then
        vim.api.nvim_set_current_buf(buf)
        vim.cmd "startinsert"
        return
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].buflisted = true
  vim.bo[buf].bufhidden = "hide"
  vim.fn.termopen(vim.o.shell)
  vim.api.nvim_buf_set_name(buf, "chat")
  vim.api.nvim_chan_send(vim.bo[buf].channel, "chat\n")
  vim.cmd "startinsert"
end

map("n", "<leader>cc", open_chat_term, { desc = "open/focus 'chat' terminal" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
