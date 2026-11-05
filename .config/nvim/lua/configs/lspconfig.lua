local mason_packages = {
  "html-lsp",
  "css-lsp",
  "typescript-language-server",
  "lua-language-server",
  "pyright",
  "json-lsp",
  "hdl-checker",
  "verible",
}

local mason_to_lsp = {
  ["html-lsp"] = "html",
  ["css-lsp"] = "cssls",
  ["typescript-language-server"] = "ts_ls",
  ["lua-language-server"] = "lua_ls",
  ["json-lsp"] = "jsonls",
  ["hdl-checker"] = "hdl_checker",
}

require("nvchad.configs.lspconfig").defaults()

local mason_pkgs = require("nvconfig").mason.pkgs

for _, package in ipairs(mason_packages) do
  vim.lsp.enable(mason_to_lsp[package] or package)

  if not vim.tbl_contains(mason_pkgs, package) then
    table.insert(mason_pkgs, package)
  end
end
