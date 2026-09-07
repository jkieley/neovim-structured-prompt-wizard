local api = vim.api
local M = {}
local state
local drafts = {}
local ns = api.nvim_create_namespace("structured_prompt")
local renderer = require("structured_prompt.render")

local function valid_win(win)
  return win and api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and api.nvim_buf_is_valid(buf)
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Structured Prompt" })
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function buffer(s, filetype)
  local buf = api.nvim_create_buf(false, true)
  s.buffers[buf] = true
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = filetype
  -- LazyVim honors this for scratch editors; ordinary Neovim simply ignores it.
  vim.b[buf].autoformat = false
  return buf
end

local function escape(text)
  return text:gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end

local function values_for(s, template)
  local values = {}
  local draft = drafts[template.id] or {}
  for _, field in ipairs(template.fields) do
    local buf = s.fields[template.id] and s.fields[template.id][field.id]
    if valid_buf(buf) then
      values[field.id] = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    else
      values[field.id] = draft[field.id] or field.default or ""
    end
  end
  return values
end

local function save(s)
  for _, template in ipairs(s.config.templates) do
    drafts[template.id] = vim.tbl_extend("force", drafts[template.id] or {}, values_for(s, template))
  end
end

local function current_template(s)
  return s.selected and s.config.templates[s.selected]
end

local function highlights()
  for group, link in pairs({
    StructuredPromptTitle = "Title",
    StructuredPromptSelected = "Special",
    StructuredPromptMuted = "Comment",
    StructuredPromptComplete = "DiagnosticOk",
    StructuredPromptRequired = "DiagnosticWarn",
  }) do
    api.nvim_set_hl(0, group, { default = true, link = link })
  end
end

local function draw_sidebar(s)
  if not valid_buf(s.sidebar_buf) then
    return
  end
  local template = current_template(s)
  local picker = s.picker or not template
  local lines = { "  STRUCTURED PROMPT", "", picker and "  Templates" or "  " .. template.name }
  local marks = { { 1, "StructuredPromptTitle" }, { 3, "StructuredPromptMuted" } }
  s.rows = {}
  if picker then
    for index, candidate in ipairs(s.config.templates) do
      lines[#lines + 1] = (s.selected == index and "  > " or "    ") .. candidate.name
      s.rows[#lines] = { template = index }
      if s.selected == index then
        marks[#marks + 1] = { #lines, "StructuredPromptSelected" }
      end
    end
  else
    lines[#lines + 1] = "  < Change template"
    s.rows[#lines] = { change_template = true }
    marks[#marks + 1] = { #lines, "StructuredPromptSelected" }
    local values = values_for(s, template)
    local filled = 0
    for _, field in ipairs(template.fields) do
      if vim.trim(values[field.id]) ~= "" then
        filled = filled + 1
      end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("  Fields %d/%d filled  * required"):format(filled, #template.fields)
    marks[#marks + 1] = { #lines, "StructuredPromptMuted" }
    for index, field in ipairs(template.fields) do
      local complete = vim.trim(values[field.id]) ~= ""
      lines[#lines + 1] = (s.field == index and "  > " or "    ")
        .. (complete and "[x] " or "[ ] ")
        .. field.label
        .. (field.required and " *" or "")
      s.rows[#lines] = { field = index }
      marks[#marks + 1] = {
        #lines,
        complete and "StructuredPromptComplete"
          or (field.required and "StructuredPromptRequired" or "StructuredPromptMuted"),
      }
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  <CR> select / edit"
  local keys = s.config.keymaps
  for _, item in ipairs({
    { "next_field", "next field" },
    { "prev_field", "previous field" },
    { "sidebar", "focus sidebar" },
    { "templates", "change template" },
    { "preview", "toggle preview" },
    { "copy", "copy prompt" },
    { "export", "export to buffer" },
    { "apply", "apply to original buffer" },
    { "close", "close wizard" },
  }) do
    if keys[item[1]] and (item[1] ~= "apply" or s.target) then
      local key = keys[item[1]]:gsub("<localleader>", vim.g.maplocalleader or "\\")
      lines[#lines + 1] = "  " .. key .. "  " .. item[2]
    end
  end
  set_lines(s.sidebar_buf, lines)
  if valid_win(s.sidebar_win) then
    vim.wo[s.sidebar_win].winbar = picker and " Templates" or " Prompt fields"
  end
  api.nvim_buf_clear_namespace(s.sidebar_buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    api.nvim_buf_set_extmark(s.sidebar_buf, ns, mark[1] - 1, 0, {
      end_row = mark[1] - 1,
      end_col = #lines[mark[1]],
      hl_group = mark[2],
    })
  end
end

local function draw_preview(s)
  if not valid_buf(s.preview_buf) then
    return
  end
  local template = current_template(s)
  local ok, result = true, "Select a template to preview its prompt."
  if template then
    ok, result = pcall(renderer.render, template, values_for(s, template))
  end
  if not ok then
    result = "Preview error: " .. tostring(result)
  elseif result == "" then
    result = "Fill a field to see your assembled prompt here."
  end
  set_lines(s.preview_buf, vim.split(result, "\n", { plain = true }))
end

local function refresh(s)
  if state == s then
    draw_sidebar(s)
    draw_preview(s)
    local template = current_template(s)
    if template and valid_buf(s.active_buf) then
      local field = template.fields[s.field]
      api.nvim_buf_clear_namespace(s.active_buf, ns, 0, -1)
      if field.hint and vim.trim(values_for(s, template)[field.id]) == "" then
        api.nvim_buf_set_extmark(s.active_buf, ns, 0, 0, {
          virt_text = { { field.hint:gsub("[\r\n]", " "), "StructuredPromptMuted" } },
          virt_text_pos = "overlay",
        })
      end
    end
  end
end

local function window_style(win, editor)
  vim.wo[win].number = editor
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].foldenable = false
  vim.wo[win].wrap = editor
  vim.wo[win].linebreak = editor
  vim.wo[win].spell = false
  vim.wo[win].list = false
end

local function map(buf, mode, key, fn, description)
  if key then
    vim.keymap.set(mode, key, fn, { buffer = buf, silent = true, desc = "Prompt: " .. description })
  end
end

local function common_maps(s, buf, editor)
  local keys = s.config.keymaps
  map(buf, "n", keys.next_field, function()
    M.move_field(1)
  end, "Next field")
  map(buf, "n", keys.prev_field, function()
    M.move_field(-1)
  end, "Previous field")
  map(buf, "n", keys.sidebar, function()
    M.focus_sidebar()
  end, "Focus sidebar")
  map(buf, "n", keys.templates, function()
    M.show_templates()
  end, "Change template")
  map(buf, "n", keys.preview, function()
    M.toggle_preview()
  end, "Toggle preview")
  map(buf, "n", keys.copy, function()
    M.copy()
  end, "Copy prompt")
  map(buf, "n", keys.export, function()
    M.export()
  end, "Export prompt to buffer")
  if s.target then
    map(buf, "n", keys.apply, function()
      M.apply()
    end, "Apply prompt to original buffer")
  end
  map(buf, "n", keys.close, function()
    M.close()
  end, "Close wizard")
  if editor then
    map(buf, "i", keys.next_field_insert, function()
      M.move_field(1)
    end, "Next field")
    map(buf, "i", keys.prev_field_insert, function()
      M.move_field(-1)
    end, "Previous field")
  else
    map(buf, "n", "q", function()
      M.close()
    end, "Close wizard")
  end
end

function M.select_field(index)
  local s = state
  local template = s and current_template(s)
  if not template or not valid_win(s.editor_win) then
    return
  end
  s.picker = false
  s.field = math.max(1, math.min(index, #template.fields))
  local field = template.fields[s.field]
  s.fields[template.id] = s.fields[template.id] or {}
  local buf = s.fields[template.id][field.id]
  if not valid_buf(buf) then
    local value = values_for(s, template)[field.id]
    buf = buffer(s, s.config.field_filetype)
    s.fields[template.id][field.id] = buf
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(value, "\n", { plain = true }))
    vim.bo[buf].undolevels = vim.o.undolevels
    common_maps(s, buf, true)
    api.nvim_buf_attach(buf, false, {
      on_lines = function()
        if state == s and not s.refresh_pending then
          s.refresh_pending = true
          vim.schedule(function()
            s.refresh_pending = false
            refresh(s)
          end)
        end
      end,
    })
  end
  if s.active_buf and valid_win(s.editor_win) then
    s.cursors[s.active_buf] = api.nvim_win_get_cursor(s.editor_win)
  end
  api.nvim_win_set_buf(s.editor_win, buf)
  s.active_buf = buf
  window_style(s.editor_win, true)
  vim.wo[s.editor_win].winbar = " "
    .. escape(template.name)
    .. " / "
    .. escape(field.label)
    .. (field.required and " *" or "")
    .. "  %="
    .. s.field
    .. "/"
    .. #template.fields
    .. " "
  if s.cursors[buf] then
    pcall(api.nvim_win_set_cursor, s.editor_win, s.cursors[buf])
  end
  api.nvim_set_current_win(s.editor_win)
  refresh(s)
  -- Keep fields reachable when a large catalog scrolls beyond the window.
  if valid_win(s.sidebar_win) then
    for row, entry in pairs(s.rows) do
      if entry.field == s.field then
        api.nvim_win_set_cursor(s.sidebar_win, { row, 0 })
        break
      end
    end
  end
end

function M.select_template(index)
  if not state or not state.config.templates[index] then
    return
  end
  state.selected = index
  M.select_field(1)
end

function M.move_field(delta)
  local s = state
  if s and current_template(s) then
    M.select_field((s.field or 1) + delta)
  end
end

function M.focus_sidebar()
  local s = state
  if s and valid_win(s.sidebar_win) then
    api.nvim_set_current_win(s.sidebar_win)
    for row, entry in pairs(s.rows) do
      if (s.picker and entry.template == (s.selected or 1)) or (not s.picker and entry.field == s.field) then
        api.nvim_win_set_cursor(s.sidebar_win, { row, 0 })
        break
      end
    end
  end
end

function M.show_templates()
  if state then
    state.picker = true
    draw_sidebar(state)
    M.focus_sidebar()
  end
end

function M.toggle_preview()
  local s = state
  if not s or not valid_win(s.editor_win) then
    return
  end
  if valid_win(s.preview_win) then
    api.nvim_win_close(s.preview_win, true)
    s.preview_win = nil
    return
  end
  local previous = api.nvim_get_current_win()
  api.nvim_set_current_win(s.editor_win)
  vim.cmd("belowright split")
  s.preview_win = api.nvim_get_current_win()
  if not valid_buf(s.preview_buf) then
    s.preview_buf = buffer(s, "markdown")
    common_maps(s, s.preview_buf, false)
  end
  api.nvim_win_set_buf(s.preview_win, s.preview_buf)
  window_style(s.preview_win, false)
  vim.wo[s.preview_win].wrap = true
  vim.wo[s.preview_win].winbar = " Prompt preview"
  draw_preview(s)
  api.nvim_set_current_win(previous)
end

local function output()
  local s = state
  local template = s and current_template(s)
  if not template then
    notify("Select a template first.", vim.log.levels.WARN)
    return
  end
  local values = values_for(s, template)
  local missing = renderer.missing(template, values)
  if #missing > 0 then
    notify("Complete required fields: " .. table.concat(missing, ", "), vim.log.levels.WARN)
    return
  end
  local ok, result = pcall(renderer.render, template, values)
  if not ok then
    notify("Cannot render prompt: " .. tostring(result), vim.log.levels.ERROR)
    return
  end
  return result
end

function M.copy()
  local result = output()
  if result == nil then
    return
  end
  vim.fn.setreg('"', result, "v")
  if vim.fn.has("clipboard") == 1 then
    local ok = pcall(vim.fn.setreg, "+", result, "v")
    if ok then
      notify("Prompt copied to the clipboard and unnamed register.")
      return
    end
  end
  notify("Prompt copied to the unnamed register (system clipboard unavailable).")
end

function M.export()
  local result = output()
  if result == nil then
    return
  end
  M.close()
  vim.cmd("botright new")
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, "\n", { plain = true }))
  vim.bo[buf].filetype = "markdown"
  notify("Prompt exported. Use :write path.md to save it.")
end

local function target_error(target)
  local buf = target.buf
  if not valid_buf(buf) or not api.nvim_buf_is_loaded(buf) then
    return "The original buffer was deleted or unloaded. Export the prompt to a new buffer instead."
  end
  if vim.bo[buf].buftype ~= "" then
    return "The original buffer must be a normal text buffer. Export the prompt to a new buffer instead."
  end
  if vim.bo[buf].readonly or not vim.bo[buf].modifiable then
    return "The original buffer is readonly or not modifiable. Make it writable before applying."
  end
  if target.changedtick and api.nvim_buf_get_changedtick(buf) ~= target.changedtick then
    return "The original buffer changed after the wizard opened. Export the prompt to a new buffer to keep both edits."
  end
end

function M.apply()
  local s = state
  if not s or not s.target then
    local message = "Open the wizard with :StructuredPromptBuffer to apply a prompt to the current text buffer."
    notify(message, vim.log.levels.WARN)
    return false, message
  end
  local result = output()
  if result == nil then
    return false
  end
  -- Check after rendering: even a custom renderer must not invalidate the target.
  local err = target_error(s.target)
  if err then
    notify(err, vim.log.levels.WARN)
    return false, err
  end
  local buf = s.target.buf
  local ok, edit_error = pcall(function()
    -- Setting the local option to itself closes the preceding undo block.
    -- Preserve the user's option value and do not merge with earlier edits.
    vim.bo[buf].undolevels = vim.bo[buf].undolevels
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, "\n", { plain = true }))
    vim.bo[buf].undolevels = vim.bo[buf].undolevels
  end)
  if not ok then
    notify("Cannot apply prompt: " .. tostring(edit_error), vim.log.levels.ERROR)
    return false, tostring(edit_error)
  end
  local origin = s.origin
  M.close()
  if valid_win(origin) and api.nvim_win_get_buf(origin) == buf then
    api.nvim_set_current_win(origin)
  else
    local wins = vim.fn.win_findbuf(buf)
    if #wins > 0 then
      api.nvim_set_current_win(wins[1])
    else
      -- A reused origin window may contain unrelated work. Give the target its
      -- own window rather than replacing that window's current buffer.
      vim.cmd("botright split")
      api.nvim_win_set_buf(0, buf)
    end
  end
  api.nvim_win_set_cursor(0, { 1, 0 })
  notify("Prompt applied to the original buffer. Use :write to save, or :wq to return to your terminal app.")
  return true
end

function M.get_values()
  local s = state
  local template = s and current_template(s)
  return template and values_for(s, template) or nil
end

function M.is_open()
  return state ~= nil and api.nvim_tabpage_is_valid(state.tab)
end

function M.reconfigure(config)
  local s = state
  if not s then
    return
  end
  local template = current_template(s)
  local id = template and template.id
  local field_id = template and template.fields[s.field].id
  local focus_sidebar = api.nvim_get_current_win() == s.sidebar_win
  local preview = valid_win(s.preview_win) == true
  local current_window = api.nvim_get_current_win()
  local in_wizard = api.nvim_get_current_tabpage() == s.tab
  local picker = s.picker
  local origin = s.origin
  local target = s.target
  local selected, selected_field
  for _, candidate in ipairs(config.templates) do
    if candidate.id == id then
      selected = id
      for index, field in ipairs(candidate.fields) do
        if field.id == field_id then
          selected_field = index
        end
      end
    end
  end
  M.close()
  local view_config = vim.deepcopy(config)
  view_config.preview = preview
  M.open(view_config, selected, { target = target, origin = origin })
  if selected_field then
    M.select_field(selected_field)
  end
  if focus_sidebar or not selected then
    M.focus_sidebar()
  end
  if picker then
    M.show_templates()
  end
  if not in_wizard and valid_win(current_window) then
    api.nvim_set_current_win(current_window)
  end
end

function M.close()
  local s = state
  if not s then
    return
  end
  save(s)
  state = nil
  api.nvim_del_augroup_by_id(s.group)
  if api.nvim_tabpage_is_valid(s.tab) then
    local wins = api.nvim_tabpage_list_wins(s.tab)
    local all_owned = true
    for _, win in ipairs(wins) do
      all_owned = all_owned and s.buffers[api.nvim_win_get_buf(win)] == true
    end
    if all_owned and #api.nvim_list_tabpages() > 1 then
      vim.cmd("tabclose " .. api.nvim_tabpage_get_number(s.tab))
    else
      for _, win in ipairs(wins) do
        if valid_win(win) and s.buffers[api.nvim_win_get_buf(win)] then
          local ok = pcall(api.nvim_win_close, win, true)
          if not ok then
            api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))
            vim.wo[win].winbar = ""
          end
        end
      end
    end
  end
  for buf in pairs(s.buffers) do
    if valid_buf(buf) then
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
  end
  if valid_win(s.origin) then
    api.nvim_set_current_win(s.origin)
  end
end

function M.open(config, template_id, opts)
  opts = opts or {}
  local index
  if template_id then
    for i, template in ipairs(config.templates) do
      if template.id == template_id then
        index = i
      end
    end
    if not index then
      local message = "Unknown template: " .. template_id
      notify(message, vim.log.levels.ERROR)
      return false, message
    end
  end
  if M.is_open() then
    if opts.buffer_mode then
      if not state.target then
        local message = "Close the current wizard, then run :StructuredPromptBuffer from the text buffer to replace."
        notify(message, vim.log.levels.WARN)
        return false, message
      end
      if api.nvim_get_current_tabpage() ~= state.tab and api.nvim_get_current_buf() ~= state.target.buf then
        local message = "This wizard already targets another buffer. Close it before starting from a different buffer."
        notify(message, vim.log.levels.WARN)
        return false, message
      end
    end
    api.nvim_set_current_tabpage(state.tab)
    if index then
      M.select_template(index)
    else
      M.focus_sidebar()
    end
    return true
  end
  local target = opts.target
  if opts.buffer_mode then
    target = { buf = api.nvim_get_current_buf() }
    local err = target_error(target)
    if err then
      notify(err, vim.log.levels.WARN)
      return false, err
    end
    target.changedtick = api.nvim_buf_get_changedtick(target.buf)
  end
  local s = {
    config = config,
    buffers = {},
    fields = {},
    cursors = {},
    origin = opts.origin or api.nvim_get_current_win(),
    target = target,
    picker = true,
  }
  state = s
  highlights()
  vim.cmd("tabnew")
  s.tab = api.nvim_get_current_tabpage()
  s.editor_win = api.nvim_get_current_win()
  s.welcome_buf = buffer(s, "structured_prompt")
  api.nvim_win_set_buf(s.editor_win, s.welcome_buf)
  window_style(s.editor_win, false)
  vim.wo[s.editor_win].wrap = true
  vim.wo[s.editor_win].linebreak = true
  vim.wo[s.editor_win].winbar = " Structured Prompt"
  set_lines(s.welcome_buf, {
    "",
    "  Build a clearer prompt",
    "",
    "  1. Choose a template on the left and press <Enter>.",
    "  2. Edit each field with normal Vim motions and insert mode.",
    target and "  3. Apply the assembled prompt to your original text buffer."
      or "  3. Copy the assembled prompt or export it to a Markdown buffer.",
    "",
    "  Each field has its own multiline buffer and undo history.",
    "  Drafts remain available for this Neovim session.",
    "",
    "  Use <C-w>h / <C-w>l to move between windows.",
  })
  common_maps(s, s.welcome_buf, false)
  vim.cmd("topleft vsplit")
  s.sidebar_win = api.nvim_get_current_win()
  s.sidebar_buf = buffer(s, "structured_prompt")
  api.nvim_win_set_buf(s.sidebar_win, s.sidebar_buf)
  window_style(s.sidebar_win, false)
  vim.wo[s.sidebar_win].cursorline = true
  vim.wo[s.sidebar_win].winfixwidth = true
  vim.wo[s.sidebar_win].winbar = " Templates"
  api.nvim_win_set_width(s.sidebar_win, math.min(config.sidebar_width, math.floor(vim.o.columns * 0.45)))
  common_maps(s, s.sidebar_buf, false)
  map(s.sidebar_buf, "n", "<CR>", function()
    local entry = s.rows[api.nvim_win_get_cursor(s.sidebar_win)[1]]
    if entry and entry.template then
      M.select_template(entry.template)
    elseif entry and entry.field then
      M.select_field(entry.field)
    elseif entry and entry.change_template then
      M.show_templates()
    end
  end, "Select template or edit field")
  s.group = api.nvim_create_augroup("StructuredPromptSession", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = s.group, callback = highlights })
  api.nvim_create_autocmd({ "TabClosed", "WinClosed" }, {
    group = s.group,
    callback = function()
      vim.schedule(function()
        if
          state == s
          and (not api.nvim_tabpage_is_valid(s.tab) or not valid_win(s.editor_win) or not valid_win(s.sidebar_win))
        then
          M.close()
        end
      end)
    end,
  })
  refresh(s)
  if config.preview then
    M.toggle_preview()
  end
  if index then
    M.select_template(index)
  else
    M.focus_sidebar()
  end
  return true
end

return M
