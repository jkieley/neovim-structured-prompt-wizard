-- Demo copy; a personal catalog can use vim.fn.stdpath("config").
require("structured_prompt").setup({
  templates_file = "artifacts/demo/catalog.json",
  sidebar_width = 34,
  preview = false,
})

-- With LazyVim / lazy.nvim, put these options in the plugin spec opts.
