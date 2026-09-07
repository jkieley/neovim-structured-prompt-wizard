local M = {}

local module_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(module_path, ":p"))))
M.bundled_path = root .. "/templates/prompts.json"

local function check(condition, message)
  if not condition then
    error(message, 0)
  end
end

local function object(value, path)
  check(type(value) == "table" and not vim.islist(value), path .. " must be an object")
end

local function nonempty(value, path)
  check(
    type(value) == "string" and vim.trim(value) ~= "" and not value:find("[\r\n]"),
    path .. " must be nonempty, single-line text"
  )
end

local function optional_string(value, path)
  check(value == nil or type(value) == "string", path .. " must be a string")
end

local function allowed_keys(value, allowed, path)
  for key in pairs(value) do
    check(allowed[key], path .. ": unknown property '" .. tostring(key) .. "'")
  end
end

function M.validate(templates, json)
  check(type(templates) == "table" and vim.islist(templates) and #templates > 0, "templates must be a nonempty array")
  local ids = {}
  for index, template in ipairs(templates) do
    local path = "templates[" .. index .. "]"
    object(template, path)
    if json then
      allowed_keys(
        template,
        { id = true, name = true, description = true, instructions = true, fields = true, sources = true },
        path
      )
    end
    nonempty(template.id, path .. ".id")
    nonempty(template.name, path .. ".name")
    if json then
      check(template.id:match("^[a-z][a-z0-9_]*$"), path .. ".id must use lowercase snake_case")
    end
    check(not ids[template.id], path .. ": duplicate template id '" .. template.id .. "'")
    ids[template.id] = true
    optional_string(template.description, path .. ".description")
    optional_string(template.instructions, path .. ".instructions")
    check(template.render == nil or type(template.render) == "function", path .. ".render must be a function")
    check(
      type(template.fields) == "table" and vim.islist(template.fields) and #template.fields > 0,
      path .. ".fields must be a nonempty array"
    )
    local fields = {}
    for field_index, field in ipairs(template.fields) do
      local field_path = path .. ".fields[" .. field_index .. "]"
      object(field, field_path)
      if json then
        allowed_keys(field, { id = true, label = true, hint = true, default = true, required = true }, field_path)
      end
      nonempty(field.id, field_path .. ".id")
      nonempty(field.label, field_path .. ".label")
      if json then
        check(field.id:match("^[a-z][a-z0-9_]*$"), field_path .. ".id must use lowercase snake_case")
      end
      check(not fields[field.id], field_path .. ": duplicate field id '" .. field.id .. "'")
      fields[field.id] = true
      optional_string(field.hint, field_path .. ".hint")
      optional_string(field.default, field_path .. ".default")
      check(field.required == nil or type(field.required) == "boolean", field_path .. ".required must be a boolean")
    end
    if template.sources ~= nil then
      check(type(template.sources) == "table" and vim.islist(template.sources), path .. ".sources must be an array")
      for source_index, source in ipairs(template.sources) do
        local source_path = path .. ".sources[" .. source_index .. "]"
        object(source, source_path)
        if json then
          allowed_keys(source, { title = true, url = true }, source_path)
        end
        nonempty(source.title, source_path .. ".title")
        nonempty(source.url, source_path .. ".url")
        check(source.url:match("^https?://%S+$"), source_path .. ".url must be an http(s) URL")
      end
    end
  end
  return templates
end

function M.load(path)
  if path == nil then
    path = M.bundled_path
  end
  nonempty(path, "templates_file")
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  local file, reason = io.open(path, "rb")
  check(file ~= nil, "Cannot read prompt catalog " .. path .. ": " .. tostring(reason))
  local content = file:read("*a")
  file:close()
  local ok, document = pcall(vim.json.decode, content)
  check(ok, "Invalid JSON in " .. path .. ": " .. tostring(document))
  local valid, result = pcall(function()
    object(document, "catalog")
    allowed_keys(document, { ["$schema"] = true, version = true, templates = true }, "catalog")
    optional_string(document["$schema"], "catalog.$schema")
    check(document.version == 1, "catalog.version must be 1")
    return M.validate(document.templates, true)
  end)
  check(valid, "Invalid prompt catalog " .. path .. ": " .. tostring(result))
  return result, path
end

return M
