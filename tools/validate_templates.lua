vim.opt.runtimepath:prepend(vim.fn.getcwd())
local path = arg[1] or (vim.env.TEMPLATES ~= "" and vim.env.TEMPLATES or nil)
local ok, result = pcall(function()
  local templates, source = require("structured_prompt.catalog").load(path)
  local render = require("structured_prompt.render")
  for _, template in ipairs(templates) do
    local values = {}
    for _, field in ipairs(template.fields) do
      values[field.id] = "Sample " .. field.id .. "\nSecond line"
    end
    assert(#render.missing(template, values) == 0, template.id .. ": sample is incomplete")
    local output = render.render(template, values)
    for _, field in ipairs(template.fields) do
      assert(output:find(values[field.id], 1, true), template.id .. ": field omitted: " .. field.id)
    end
    if template.instructions and vim.trim(template.instructions) ~= "" then
      assert(output:sub(1, #template.instructions) == template.instructions, template.id .. ": instructions omitted")
    end
    print("PASS " .. template.id .. " (" .. #template.fields .. " fields)")
  end
  return "Validated " .. #templates .. " templates from " .. source
end)
if not ok then
  io.stderr:write(tostring(result) .. "\n")
  vim.cmd("cquit 1")
end
print(result)
vim.cmd("qa!")
