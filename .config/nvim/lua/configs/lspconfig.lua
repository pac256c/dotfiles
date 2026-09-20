require("nvchad.configs.lspconfig").defaults()

-- language servers we want
local servers = {
  "html",
  "cssls",
  "typescript-language-server",
  "lua-language-server",
  "pyright",
}

vim.lsp.enable(servers)
