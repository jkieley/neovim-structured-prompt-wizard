local M = {}
local config
local options = {}

function M.setup(opts)
  local resolved = require("structured_prompt.config").resolve(opts)
  require("structured_prompt.ui").close()
  config = resolved
  options = vim.deepcopy(opts or {})
  if config.templates_file then
    options.templates_file = config.templates_file
  end
end

function M.open(template_id)
  if not config then
    M.setup()
  end
  require("structured_prompt.ui").open(config, template_id)
end

function M.open_buffer(template_id)
  if not config then
    M.setup()
  end
  return require("structured_prompt.ui").open(config, template_id, { buffer_mode = true })
end

function M.apply()
  return require("structured_prompt.ui").apply()
end

function M.close()
  require("structured_prompt.ui").close()
end

function M.toggle()
  if require("structured_prompt.ui").is_open() then
    M.close()
  else
    M.open()
  end
end

function M.template_ids()
  if not config then
    M.setup()
  end
  return vim.tbl_map(function(template)
    return template.id
  end, config.templates)
end

function M.get_values()
  return require("structured_prompt.ui").get_values()
end

function M.reload()
  -- Fully validate before touching the active wizard or its drafts.
  local ok, resolved = pcall(function()
    return require("structured_prompt.config").resolve(options)
  end)
  if not ok then
    vim.notify(tostring(resolved), vim.log.levels.ERROR, { title = "Structured Prompt" })
    return false, tostring(resolved)
  end
  local ui = require("structured_prompt.ui")
  ui.reconfigure(resolved)
  config = resolved
  if config.templates_file then
    options.templates_file = config.templates_file
  end
  vim.notify(
    "Reloaded " .. #config.templates .. " prompt templates.",
    vim.log.levels.INFO,
    { title = "Structured Prompt" }
  )
  return true
end

return M
