-- After installing the plugin, put this in your init.lua.
-- Uses the bundled JSON catalog. To customize it, copy templates/prompts.json
-- and templates/schema.json into ~/.config/nvim/structured-prompt/, then enable
-- templates_file below.
vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("structured_prompt").setup({
  -- templates_file = vim.fn.stdpath("config") .. "/structured-prompt/prompts.json",
  sidebar_width = 38,
  preview = true,
})

vim.keymap.set("n", "<leader>ap", "<cmd>StructuredPrompt<cr>", {
  desc = "Structured prompt",
})
vim.keymap.set("n", "<leader>aB", "<cmd>StructuredPromptBuffer<cr>", {
  desc = "Build prompt for buffer",
})
vim.keymap.set("n", "<leader>aP", "<cmd>StructuredPromptReload<cr>", {
  desc = "Reload prompt templates",
})
