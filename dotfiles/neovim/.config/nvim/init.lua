-- Keep Vimscript preferences editable alongside this file. Resolve it relative
-- to init.lua because the Home Manager wrapper selects this file with `-u`.
local config_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
vim.cmd.source(config_dir .. "/init.vim")

-- Enable Treesitter highlighting for the parsers installed through Nix.
vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "javascript",
    "javascriptreact",
    "json",
    "markdown",
    "typescript",
    "typescriptreact",
  },
  callback = function()
    vim.treesitter.start()
  end,
})

-- Extend nvim-lspconfig's TypeScript configuration with inferred-type hints.
vim.lsp.config("ts_ls", {
  init_options = {
    preferences = {
      includeInlayVariableTypeHints = true,
      includeInlayVariableTypeHintsWhenTypeMatchesName = false,
      includeInlayFunctionLikeReturnTypeHints = true,
      includeInlayFunctionParameterTypeHints = true,
      includeInlayPropertyDeclarationTypeHints = true,
      includeInlayParameterNameHints = "literals",
    },
  },
})

vim.lsp.enable("ts_ls")

-- Use Neovim's built-in completion UI rather than a completion plugin.
vim.opt.completeopt = { "menuone", "noselect", "popup" }

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("user-lsp", { clear = true }),
  callback = function(event)
    local client = assert(vim.lsp.get_client_by_id(event.data.client_id))

    if client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
    end

    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, event.buf, {
        autotrigger = true,
      })
    end
  end,
})

-- Request completion with Ctrl-Space and accept an item with Ctrl-Y.
vim.keymap.set("i", "<C-Space>", function()
  vim.lsp.completion.get()
end, { desc = "LSP completion" })
