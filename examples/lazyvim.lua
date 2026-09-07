-- Save as ~/.config/nvim/lua/plugins/structured-prompt.lua.
-- Uses the bundled JSON catalog. To customize it, copy templates/prompts.json
-- and templates/schema.json to ~/.config/nvim/structured-prompt/, then enable
-- templates_file below. Set maplocalleader in lua/config/options.lua if desired.
return {
  "jkieley/neovim-structured-prompt-wizard",
  name = "structured-prompt.nvim",
  main = "structured_prompt",
  cmd = {
    "StructuredPrompt",
    "StructuredPromptBuffer",
    "StructuredPromptApply",
    "StructuredPromptToggle",
    "StructuredPromptReload",
  },
  keys = {
    { "<leader>ap", "<cmd>StructuredPrompt<cr>", desc = "Structured prompt" },
    { "<leader>aB", "<cmd>StructuredPromptBuffer<cr>", desc = "Build prompt for buffer" },
    { "<leader>aP", "<cmd>StructuredPromptReload<cr>", desc = "Reload prompt templates" },
  },
  opts = {
    -- templates_file = vim.fn.stdpath("config") .. "/structured-prompt/prompts.json",
    sidebar_width = 38,
    preview = true,
  },
}
