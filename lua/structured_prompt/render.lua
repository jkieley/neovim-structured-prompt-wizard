local M = {}

function M.missing(template, values)
  local missing = {}
  for _, field in ipairs(template.fields) do
    if field.required and vim.trim(values[field.id] or "") == "" then
      missing[#missing + 1] = field.label
    end
  end
  return missing
end

function M.render(template, values)
  if template.render then
    local result = template.render(vim.deepcopy(values), vim.deepcopy(template))
    assert(type(result) == "string", "template.render must return a string")
    return result
  end
  local sections = {}
  if template.instructions and vim.trim(template.instructions) ~= "" then
    sections[#sections + 1] = template.instructions
  end
  for _, field in ipairs(template.fields) do
    local value = values[field.id] or ""
    if vim.trim(value) ~= "" then
      sections[#sections + 1] = "## " .. field.label .. "\n\n" .. value
    end
  end
  return table.concat(sections, "\n\n")
end

return M
