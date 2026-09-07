vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.swapfile = false
vim.o.hidden = false -- Field switching must work without relying on user settings.
vim.g.maplocalleader = ","
vim.cmd("runtime plugin/structured_prompt.lua")

local api = vim.api
local prompt = require("structured_prompt")
local ui = require("structured_prompt.ui")
local render = require("structured_prompt.render")
local count = 0
local notifications = {}
vim.notify = function(message)
  notifications[#notifications + 1] = message
end
local clipboard = {}
vim.g.clipboard = {
  name = "test",
  copy = {
    ["+"] = function(lines)
      clipboard = lines
    end,
    ["*"] = function() end,
  },
  paste = {
    ["+"] = function()
      return { clipboard, "v" }
    end,
    ["*"] = function()
      return { {}, "v" }
    end,
  },
}

local function eq(actual, expected, message)
  assert(
    vim.deep_equal(actual, expected),
    (message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
  )
end

local function drain()
  vim.wait(20, function()
    return false
  end)
end

local function keys(input)
  api.nvim_feedkeys(api.nvim_replace_termcodes(input, true, false, true), "xt", false)
  drain()
end

local function text(value)
  api.nvim_buf_set_lines(0, 0, -1, false, vim.split(value, "\n", { plain = true }))
  drain()
end

local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  prompt.close()
  if not ok then
    io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
    vim.cmd("cquit 1")
  end
  count = count + 1
  print("PASS " .. name)
end

test("configuration replaces template lists and rejects invalid schemas", function()
  local config = require("structured_prompt.config")
  local custom = { { id = "one", name = "One", fields = { { id = "body", label = "Body" } } } }
  eq(#config.resolve({ templates = custom }).templates, 1)
  eq(#config.resolve({ templates = custom }).templates[1].fields, 1)
  eq(config.resolve({ keymaps = { next_field = false } }).keymaps.next_field, false)
  for _, opts in ipairs({
    { templates = {} },
    { sidebar_width = 2 },
    { preview = "yes" },
    { templates = { custom[1], custom[1] } },
    { templates = { { id = "x", name = "X", fields = {} } } },
    { templates = { { id = "x", name = "X", fields = { { id = "a", label = "A", required = "yes" } } } } },
    { keymaps = { next_field = 42 } },
  }) do
    eq(pcall(config.resolve, opts), false, "invalid options should fail")
  end
end)

test("renderer preserves multiline content, omits blanks, validates required fields", function()
  local template = require("structured_prompt.config").defaults.templates[1]
  local values = { task = "Build it\n\n```lua\nprint('hi')\n```", constraints = " \n", output = "Markdown" }
  eq(render.render(template, values), "## Task definition\n\n" .. values.task .. "\n\n## Expected output\n\nMarkdown")
  eq(render.missing(template, values), {})
  eq(render.missing(template, { task = " \n" }), { "Task definition", "Expected output" })
  eq(
    render.render({
      fields = {},
      render = function(v)
        v.x = "changed"
        return "custom"
      end,
    }, values),
    "custom"
  )
  eq(values.x, nil, "custom renderer must not mutate draft")
end)

test("command starts at template sidebar and Enter opens a field", function()
  prompt.setup()
  local origin = api.nvim_get_current_win()
  local tabs = #api.nvim_list_tabpages()
  vim.cmd("StructuredPrompt")
  eq(#api.nvim_list_tabpages(), tabs + 1)
  eq(vim.bo.filetype, "structured_prompt")
  eq(api.nvim_win_get_cursor(0)[1], 4)
  keys("<CR>")
  eq(vim.bo.filetype, "markdown")
  eq(vim.bo.buftype, "nofile")
  eq(prompt.get_values().task, "")
  local hints = api.nvim_buf_get_extmarks(0, api.nvim_create_namespace("structured_prompt"), 0, -1, { details = true })
  eq(hints[1][4].virt_text[1][1], "What should be accomplished?")
  local wizard_tab = api.nvim_get_current_tabpage()
  prompt.open()
  eq(api.nvim_get_current_tabpage(), wizard_tab, "reopening should focus existing wizard")
  prompt.close()
  eq(#api.nvim_list_tabpages(), tabs)
  eq(api.nvim_get_current_win(), origin)
end)

test("field mappings preserve buffers, cursor, multiline text, and independent undo", function()
  prompt.setup()
  prompt.open("general")
  keys("iFirst line<CR>Second line<Esc>")
  eq(
    api.nvim_buf_get_extmarks(0, api.nvim_create_namespace("structured_prompt"), 0, -1, {}),
    {},
    "hint disappears after typing"
  )
  local first = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  keys("]f")
  local second = api.nvim_get_current_buf()
  assert(first ~= second)
  keys("iConstraint<Esc>")
  keys("[f")
  eq(api.nvim_get_current_buf(), first)
  eq(api.nvim_win_get_cursor(0), cursor)
  eq(prompt.get_values().task, "First line\nSecond line")
  keys("u")
  eq(prompt.get_values().task, "")
  eq(prompt.get_values().constraints, "Constraint")
  keys("<C-r>")
  eq(prompt.get_values().task, "First line\nSecond line")
  keys("A<C-g><C-n> more<Esc>")
  eq(api.nvim_get_current_buf(), second)
  assert(prompt.get_values().constraints:find("more", 1, true))
end)

test("template switching and close/reopen retain separate drafts", function()
  prompt.open("general")
  text("General draft")
  prompt.open("code")
  text("Code draft")
  prompt.open("general")
  eq(prompt.get_values().task, "General draft")
  prompt.close()
  prompt.open("code")
  eq(prompt.get_values().task, "Code draft")
  prompt.close()
  prompt.open("general")
  eq(prompt.get_values().task, "General draft")
end)

test("preview follows edits and copy/export enforce required fields", function()
  prompt.open("general")
  ui.select_field(1)
  text("Task")
  ui.select_field(3)
  text("")
  ui.export()
  eq(ui.is_open(), true)
  assert(notifications[#notifications]:find("Expected output", 1, true))
  ui.copy()
  assert(notifications[#notifications]:find("Expected output", 1, true))
  text("Deliverable")
  ui.select_field(2)
  text("")
  ui.toggle_preview()
  local preview
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.wo[win].winbar == " Prompt preview" then
      preview = api.nvim_win_get_buf(win)
    end
  end
  assert(preview)
  eq(vim.bo[preview].modifiable, false)
  local expected = "## Task definition\n\nTask\n\n## Expected output\n\nDeliverable"
  eq(table.concat(api.nvim_buf_get_lines(preview, 0, -1, false), "\n"), expected)
  ui.copy()
  eq(vim.fn.getreg('"'), expected)
  eq(table.concat(clipboard, "\n"), expected)
  ui.export()
  eq(ui.is_open(), false)
  eq(vim.bo.buftype, "")
  eq(vim.bo.filetype, "markdown")
  eq(table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n"), expected)
  vim.cmd("bwipeout!")
end)

test("custom defaults, renderer, and disabled mappings work", function()
  prompt.setup({
    preview = true,
    keymaps = { next_field = false },
    templates = {
      {
        id = "custom",
        name = "Custom",
        fields = { { id = "body", label = "Body", default = "Default\ntext" } },
        render = function(values)
          return "<prompt>" .. values.body .. "</prompt>"
        end,
      },
    },
  })
  prompt.open("custom")
  eq(prompt.get_values().body, "Default\ntext")
  eq(vim.fn.maparg("]f", "n"), "")
  ui.copy()
  eq(vim.fn.getreg('"'), "<prompt>Default\ntext</prompt>")
end)

test("bad custom renderer reports errors without closing wizard", function()
  prompt.setup({
    templates = {
      {
        id = "bad",
        name = "Bad",
        fields = { { id = "x", label = "X" } },
        render = function()
          error("render failure")
        end,
      },
    },
  })
  prompt.open("bad")
  ui.toggle_preview()
  ui.export()
  eq(ui.is_open(), true)
  assert(notifications[#notifications]:find("render failure", 1, true))
end)

test("unknown template does not open a tab", function()
  local tabs = #api.nvim_list_tabpages()
  prompt.open("does-not-exist")
  eq(#api.nvim_list_tabpages(), tabs)
  eq(ui.is_open(), false)
end)

test("manually closing tab or a core window cleans up and retains drafts", function()
  prompt.setup()
  prompt.open("general")
  text("Retain after tabclose")
  local field = api.nvim_get_current_buf()
  vim.cmd("tabclose")
  drain()
  eq(ui.is_open(), false)
  eq(api.nvim_buf_is_valid(field), false)
  prompt.open("general")
  eq(prompt.get_values().task, "Retain after tabclose")
  vim.cmd("close")
  drain()
  eq(ui.is_open(), false)
  prompt.open("general")
  eq(prompt.get_values().task, "Retain after tabclose")
end)

test("closing wizard preserves unrelated modified buffers inside its tab", function()
  prompt.open("general")
  vim.cmd("new")
  local unrelated = api.nvim_get_current_buf()
  text("User work")
  prompt.close()
  eq(api.nvim_buf_is_valid(unrelated), true)
  eq(api.nvim_buf_get_lines(unrelated, 0, -1, false), { "User work" })
  assert(#vim.fn.win_findbuf(unrelated) > 0)
  vim.cmd("tabnext")
  vim.cmd("bwipeout! " .. unrelated)
end)

test("closing wizard as the last tab leaves a usable window", function()
  prompt.open("general")
  vim.cmd("tabonly!")
  prompt.close()
  eq(ui.is_open(), false)
  eq(#api.nvim_list_tabpages(), 1)
  eq(#api.nvim_tabpage_list_wins(0), 1)
  eq(vim.bo.buftype, "")
end)

local function fixture(templates)
  local path = vim.fn.tempname() .. " prompts.json"
  vim.fn.writefile({ vim.json.encode({ version = 1, templates = templates }) }, path)
  return path
end

local function rewrite(path, templates)
  vim.fn.writefile({ vim.json.encode({ version = 1, templates = templates }) }, path)
end

local function sample_template(id)
  return {
    id = id or "file_test",
    name = "From JSON",
    instructions = "Use only supplied facts.\nWrite clearly.",
    fields = {
      { id = "task", label = "Task", hint = "EDITOR HINT", required = true },
      { id = "output", label = "Output", default = "Markdown\n日本語" },
    },
    sources = { { title = "SOURCE METADATA", url = "https://example.com/source" } },
  }
end

test("JSON file config preserves instructions, Unicode defaults, and metadata boundaries", function()
  local template = sample_template()
  local path = fixture({ template })
  prompt.setup({ templates_file = path })
  eq(prompt.template_ids(), { "file_test" })
  prompt.open("file_test")
  eq(prompt.get_values(), { task = "", output = "Markdown\n日本語" })
  text("Write a guide.\nInclude examples.")
  ui.copy()
  local output = vim.fn.getreg('"')
  eq(
    output,
    "Use only supplied facts.\nWrite clearly.\n\n## Task\n\nWrite a guide.\nInclude examples.\n\n## Output\n\nMarkdown\n日本語"
  )
  eq(output:find("EDITOR HINT", 1, true), nil)
  eq(output:find("SOURCE METADATA", 1, true), nil)
  eq(output:find("https://example.com/source", 1, true), nil)
  vim.fn.delete(path)
end)

test("JSON errors identify the file and offending property", function()
  local path = fixture({ sample_template() })
  local catalog = require("structured_prompt.catalog")
  local cases = {
    { "{broken", "Invalid JSON" },
    { "null", "catalog must be an object" },
    { "[]", "catalog must be an object" },
    { '{"version":2,"templates":[]}', "catalog.version" },
    { '{"version":1,"templates":[]}', "templates must be a nonempty array" },
    { '{"version":1,"templates":null}', "templates must be a nonempty array" },
  }
  for _, case in ipairs(cases) do
    vim.fn.writefile({ case[1] }, path)
    local ok, err = pcall(catalog.load, path)
    eq(ok, false)
    assert(err:find(path, 1, true) and err:find(case[2], 1, true), err)
  end
  local mutations = {
    {
      function(t)
        t.fields[1].required = "yes"
      end,
      "fields[1].required",
    },
    {
      function(t)
        t.fields[2].id = "task"
      end,
      "duplicate field id",
    },
    {
      function(t)
        t.fields[1].default = vim.NIL
      end,
      "fields[1].default",
    },
    {
      function(t)
        t.fields[1].hints = "typo"
      end,
      "unknown property 'hints'",
    },
    {
      function(t)
        t.instructions = {}
      end,
      ".instructions",
    },
    {
      function(t)
        t.render = "return os.execute('echo bad')"
      end,
      "unknown property 'render'",
    },
    {
      function(t)
        t.sources[1].url = "file:///etc/passwd"
      end,
      ".sources[1].url",
    },
    {
      function(t)
        t.fields[1].id = "two words"
      end,
      "lowercase snake_case",
    },
  }
  for _, case in ipairs(mutations) do
    local template = sample_template()
    case[1](template)
    rewrite(path, { template })
    local ok, err = pcall(catalog.load, path)
    eq(ok, false)
    assert(err:find(path, 1, true) and err:find(case[2], 1, true), err)
  end
  rewrite(path, { sample_template(), sample_template() })
  local ok, err = pcall(catalog.load, path)
  eq(ok, false)
  assert(err:find("duplicate template id", 1, true))
  eq(pcall(catalog.load, false), false)
  vim.fn.delete(path)
  ok, err = pcall(catalog.load, path)
  eq(ok, false)
  assert(err:find("Cannot read prompt catalog " .. path, 1, true))
end)

test("bundled catalog resolves independently of current directory", function()
  local cwd = vim.fn.getcwd()
  vim.api.nvim_set_current_dir(vim.fn.fnamemodify(vim.fn.tempname(), ":h"))
  local templates = require("structured_prompt.catalog").load()
  eq(templates[1].id, "general")
  assert(#templates > 3)
  vim.api.nvim_set_current_dir(cwd)
end)

test("relative JSON paths stay anchored across directory changes and reloads", function()
  local cwd = vim.fn.getcwd()
  local path = fixture({ sample_template("relative_file") })
  api.nvim_set_current_dir(vim.fn.fnamemodify(path, ":h"))
  prompt.setup({ templates_file = vim.fn.fnamemodify(path, ":t") })
  api.nvim_set_current_dir(cwd)
  rewrite(path, { sample_template("relative_updated") })
  eq(prompt.reload(), true)
  eq(prompt.template_ids(), { "relative_updated" })
  eq(ui.is_open(), false)
  vim.fn.delete(path)
end)

test("reload updates reordered fields and templates while retaining the active draft", function()
  local template = sample_template("reload_file")
  local path = fixture({ template })
  prompt.setup({ templates_file = path })
  prompt.open("reload_file")
  text("Keep this task")
  ui.select_field(2)
  text("Keep this output")
  ui.toggle_preview()
  template.name = "Renamed template"
  template.instructions = "New instructions"
  template.fields = {
    { id = "output", label = "Changed label", default = "Must not overwrite draft" },
    { id = "new_field", label = "New field", default = "New default" },
    { id = "task", label = "Task", required = true },
  }
  rewrite(path, { sample_template("new_template"), template })
  vim.cmd("StructuredPromptReload")
  eq(prompt.template_ids(), { "new_template", "reload_file" })
  eq(ui.is_open(), true)
  eq(prompt.get_values(), { output = "Keep this output", new_field = "New default", task = "Keep this task" })
  assert(vim.wo.winbar:find("Changed label", 1, true), vim.wo.winbar)
  eq(api.nvim_buf_get_lines(0, 0, -1, false), { "Keep this output" })
  eq(#api.nvim_tabpage_list_wins(0), 3, "preview remains open")
  local completion = vim.fn.getcompletion("StructuredPrompt new_", "cmdline")
  eq(completion, { "new_template" })
  vim.fn.delete(path)
end)

test("failed reload and conflicting setup preserve the existing wizard", function()
  local path = fixture({ sample_template("safe_reload") })
  prompt.setup({ templates_file = path })
  prompt.open("safe_reload")
  text("Do not lose this")
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  vim.fn.writefile({ "{" }, path)
  local ok, err = prompt.reload()
  eq(ok, false)
  assert(err:find(path, 1, true))
  eq(api.nvim_get_current_buf(), buf)
  eq(api.nvim_get_current_win(), win)
  eq(prompt.get_values().task, "Do not lose this")
  eq(prompt.template_ids(), { "safe_reload" })
  eq(pcall(prompt.setup, { templates_file = path, templates = { sample_template() } }), false)
  eq(api.nvim_get_current_buf(), buf)
  vim.fn.delete(path)
end)

test("removed and re-added fields retain drafts and do not leak into output", function()
  local template = sample_template("removed_fields")
  local path = fixture({ template })
  prompt.setup({ templates_file = path })
  prompt.open("removed_fields")
  text("Retained value")
  ui.select_field(2)
  text("Temporarily hidden")
  local original = vim.deepcopy(template)
  table.remove(template.fields, 2)
  rewrite(path, { template })
  eq(prompt.reload(), true)
  eq(prompt.get_values(), { task = "Retained value" })
  ui.copy()
  eq(vim.fn.getreg('"'):find("Temporarily hidden", 1, true), nil)
  rewrite(path, { original })
  eq(prompt.reload(), true)
  eq(prompt.get_values().output, "Temporarily hidden")
  rewrite(path, { sample_template("replacement") })
  eq(prompt.reload(), true)
  eq(prompt.get_values(), nil, "removed selection returns to template picker")
  eq(vim.bo.filetype, "structured_prompt")
  vim.fn.delete(path)
end)

test("large catalogs keep the selected field visible and allow returning to templates", function()
  local templates = {}
  for index = 1, 40 do
    templates[index] = sample_template("many_" .. index)
  end
  prompt.setup({ templates = templates })
  prompt.open("many_40")
  local sidebar
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.wo[win].winbar == " Prompt fields" then
      sidebar = win
    end
  end
  assert(sidebar)
  eq(api.nvim_win_get_cursor(sidebar)[1], 7)
  local lines = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(sidebar), 0, -1, false), "\n")
  eq(lines:find("Templates", 1, true), nil, "template list is hidden after selection")
  ui.select_field(2)
  eq(api.nvim_win_get_cursor(sidebar)[1], 8)
  ui.focus_sidebar()
  eq(api.nvim_win_get_cursor(sidebar)[1], 8)
  keys(",t")
  eq(vim.wo.winbar, " Templates")
  eq(api.nvim_win_get_cursor(sidebar)[1], 43)
  keys("<CR>")
  eq(vim.bo.filetype, "markdown")
  ui.focus_sidebar()
  api.nvim_win_set_cursor(sidebar, { 4, 0 })
  keys("<CR>")
  eq(vim.wo.winbar, " Templates", "Change template row is selectable")
  keys("<CR>")
  eq(vim.bo.filetype, "markdown")
end)

local function buffer_template(id)
  return {
    id = id,
    name = "Buffer prompt",
    instructions = "Use the supplied facts.",
    fields = { { id = "body", label = "Task", required = true } },
  }
end

local function origin_buffer(value)
  local buf = api.nvim_create_buf(true, false)
  vim.cmd("hide buffer " .. buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(value, "\n", { plain = true }))
  return buf, api.nvim_get_current_win()
end

test("buffer mode applies once to the same file, does not save, and supports undo and redo", function()
  local path = vim.fn.tempname()
  vim.fn.writefile({ "Existing prompt", "Second line" }, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local tabs = #api.nvim_list_tabpages()
  prompt.setup({ templates = { buffer_template("buffer_file") } })
  eq(vim.fn.getcompletion("StructuredPromptBuffer buffer_", "cmdline"), { "buffer_file" })
  vim.cmd("StructuredPromptBuffer buffer_file")
  text("Build the feature.\nInclude tests.")
  local expected = { "Use the supplied facts.", "", "## Task", "", "Build the feature.", "Include tests." }
  keys(",a")
  eq(ui.is_open(), false)
  eq(#api.nvim_list_tabpages(), tabs)
  eq(api.nvim_get_current_buf(), buf)
  eq(api.nvim_get_current_win(), win)
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), expected)
  eq(vim.fn.readfile(path), { "Existing prompt", "Second line" }, "apply must not write the file")
  eq(vim.bo[buf].modified, true)
  keys("u")
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Existing prompt", "Second line" })
  keys("<C-r>")
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), expected)
  vim.cmd("bwipeout!")
  vim.fn.delete(path)
end)

test("apply validates required fields and renderers, and cancel leaves the source intact", function()
  local template = buffer_template("buffer_validation")
  prompt.setup({ templates = { template } })
  local buf = origin_buffer("Do not replace yet")
  local tick = api.nvim_buf_get_changedtick(buf)
  prompt.open_buffer("buffer_validation")
  eq(prompt.apply(), false)
  assert(notifications[#notifications]:find("Complete required fields", 1, true))
  eq(ui.is_open(), true)
  text("Draft")
  keys(",q")
  eq(api.nvim_get_current_buf(), buf)
  eq(api.nvim_buf_get_changedtick(buf), tick)
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Do not replace yet" })
  template.render = function()
    error("Cannot render this template")
  end
  prompt.setup({ templates = { template } })
  prompt.open_buffer("buffer_validation")
  eq(prompt.get_values().body, "Draft")
  eq(prompt.apply(), false)
  eq(ui.is_open(), true)
  eq(api.nvim_buf_get_changedtick(buf), tick)
  prompt.close()
  api.nvim_buf_delete(buf, { force = true })
end)

test("ordinary mode cannot apply or silently retarget an already open wizard", function()
  prompt.setup({ templates = { buffer_template("buffer_explicit") } })
  local buf = origin_buffer("Original")
  prompt.open("buffer_explicit")
  text("Draft")
  eq(vim.fn.maparg(",a", "n"), "", "apply is only mapped in buffer mode")
  eq(prompt.apply(), false)
  assert(notifications[#notifications]:find(":StructuredPromptBuffer", 1, true))
  eq(prompt.open_buffer(), false)
  eq(ui.is_open(), true)
  prompt.close()
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Original" })
  prompt.open_buffer("buffer_explicit")
  local wizard = api.nvim_get_current_win()
  vim.cmd("tabprevious")
  local other = origin_buffer("Other prompt")
  eq(prompt.open_buffer(), false)
  api.nvim_set_current_win(wizard)
  eq(prompt.apply(), true)
  eq(api.nvim_get_current_buf(), buf)
  eq(api.nvim_buf_get_lines(other, 0, -1, false), { "Other prompt" })
  api.nvim_buf_delete(buf, { force = true })
  api.nvim_buf_delete(other, { force = true })
end)

test("reload preserves the exact source buffer even if its original window is reused", function()
  local template = buffer_template("buffer_reload")
  local path = fixture({ template })
  prompt.setup({ templates_file = path })
  local buf, win = origin_buffer("Earlier prompt")
  prompt.open_buffer("buffer_reload")
  text("New prompt")
  local wizard = api.nvim_get_current_win()
  api.nvim_set_current_win(win)
  local other = origin_buffer("Unrelated work")
  api.nvim_set_current_win(wizard)
  template.instructions = "Reloaded instructions."
  rewrite(path, { template })
  eq(prompt.reload(), true)
  eq(prompt.get_values().body, "New prompt")
  vim.cmd("StructuredPromptApply")
  eq(ui.is_open(), false)
  eq(api.nvim_get_current_buf(), buf)
  eq(api.nvim_win_get_buf(win), other, "reused origin window keeps its other buffer")
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Reloaded instructions.", "", "## Task", "", "New prompt" })
  eq(api.nvim_buf_get_lines(other, 0, -1, false), { "Unrelated work" })
  keys("u")
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Earlier prompt" })
  api.nvim_buf_delete(buf, { force = true })
  api.nvim_buf_delete(other, { force = true })
  vim.fn.delete(path)
end)

test("source changes remain protected across reload and export can recover the draft", function()
  local template = buffer_template("buffer_conflict")
  local path = fixture({ template })
  prompt.setup({ templates_file = path })
  local buf = origin_buffer("Original content")
  prompt.open_buffer("buffer_conflict")
  text("Wizard draft")
  api.nvim_buf_set_lines(buf, 0, -1, false, { "Concurrent edit" })
  eq(prompt.reload(), true)
  eq(prompt.apply(), false)
  assert(notifications[#notifications]:find("changed after", 1, true))
  eq(ui.is_open(), true)
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Concurrent edit" })
  ui.export()
  local exported = api.nvim_get_current_buf()
  assert(exported ~= buf)
  assert(table.concat(api.nvim_buf_get_lines(exported, 0, -1, false), "\n"):find("Wizard draft", 1, true))
  eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Concurrent edit" })
  api.nvim_buf_delete(exported, { force = true })
  api.nvim_buf_delete(buf, { force = true })
  vim.fn.delete(path)
end)

test("buffer mode rejects unsuitable targets and refuses deleted or locked sources", function()
  prompt.setup({ templates = { buffer_template("buffer_target") } })
  for _, option in ipairs({ "readonly", "modifiable", "buftype" }) do
    local buf = origin_buffer("Target")
    local value = option == "readonly" and true or (option == "buftype" and "nofile" or false)
    local previous = vim.bo[buf][option]
    vim.bo[buf][option] = value
    eq(prompt.open_buffer("buffer_target"), false)
    eq(ui.is_open(), false)
    vim.bo[buf][option] = previous
    prompt.open_buffer("buffer_target")
    text("Ready")
    vim.bo[buf][option] = value
    eq(prompt.apply(), false)
    eq(ui.is_open(), true)
    eq(api.nvim_buf_get_lines(buf, 0, -1, false), { "Target" })
    vim.bo[buf][option] = previous
    prompt.close()
    api.nvim_buf_delete(buf, { force = true })
  end
  local buf = origin_buffer("Deleted target")
  prompt.open_buffer("buffer_target")
  text("Recover me")
  api.nvim_buf_delete(buf, { force = true })
  eq(prompt.apply(), false)
  assert(notifications[#notifications]:find("deleted or unloaded", 1, true))
  eq(ui.is_open(), true)
  eq(prompt.get_values().body, "Recover me")
end)

test("curated catalog is complete and Lua renderers retain full control", function()
  local templates = require("structured_prompt.catalog").load()
  local researched = {
    co_star = true,
    few_shot = true,
    grounded_answer = true,
    structured_extraction = true,
    decision_matrix = true,
    debug_diagnosis = true,
    implementation_plan = true,
    critique_revision = true,
    research_brief = true,
  }
  for _, template in ipairs(templates) do
    if researched[template.id] then
      assert(template.instructions and #template.instructions > 0, template.id)
      assert(template.sources and #template.sources > 0, template.id)
      researched[template.id] = nil
    end
    local values = {}
    for _, field in ipairs(template.fields) do
      values[field.id] = "Answer for " .. field.id
    end
    eq(render.missing(template, values), {})
    local output = render.render(template, values)
    for _, field in ipairs(template.fields) do
      assert(output:find(values[field.id], 1, true), template.id)
    end
  end
  eq(next(researched), nil, "all researched starter templates are present")
  eq(
    render.render({
      instructions = "Automatic prefix",
      fields = {},
      render = function()
        return "Custom output"
      end,
    }, {}),
    "Custom output"
  )
end)

print(("\n%d tests passed"):format(count))
vim.cmd("qa!")
