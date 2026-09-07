vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
vim.g.maplocalleader = ","
vim.o.termguicolors = true
vim.o.hidden = true
vim.o.laststatus = 3
require("structured_prompt").setup()
