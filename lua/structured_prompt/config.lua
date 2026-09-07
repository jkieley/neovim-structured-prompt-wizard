local M = {}
local catalog = require("structured_prompt.catalog")

M.defaults = {
  sidebar_width = 34,
  preview = false,
  field_filetype = "markdown",
  templates = catalog.load(),
  keymaps = {
    next_field = "]f",
    prev_field = "[f",
    next_field_insert = "<C-g><C-n>",
    prev_field_insert = "<C-g><C-p>",
    sidebar = "<localleader>s",
    templates = "<localleader>t",
    preview = "<localleader>p",
    copy = "<localleader>y",
    export = "<localleader>e",
    apply = "<localleader>a",
    close = "<localleader>q",
  },
}

function M.resolve(opts)
  assert(vim.fn.has("nvim-0.10") == 1, "structured-prompt.nvim requires Neovim 0.10 or newer")
  opts = opts or {}
  assert(type(opts) == "table", "options must be a table")
  assert(not (opts.templates ~= nil and opts.templates_file ~= nil), "Use either templates or templates_file, not both")
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  if opts.templates ~= nil then
    config.templates = catalog.validate(vim.deepcopy(opts.templates))
  else
    config.templates, config.templates_file = catalog.load(opts.templates_file)
  end
  assert(type(config.sidebar_width) == "number" and config.sidebar_width >= 20, "sidebar_width must be at least 20")
  assert(type(config.preview) == "boolean", "preview must be a boolean")
  assert(type(config.field_filetype) == "string", "field_filetype must be a string")
  assert(type(config.keymaps) == "table", "keymaps must be a table")
  for action, key in pairs(config.keymaps) do
    assert(M.defaults.keymaps[action] ~= nil, "unknown keymap action: " .. action)
    assert(key == false or (type(key) == "string" and key ~= ""), "keymap must be a nonempty string or false")
  end
  return config
end

return M
