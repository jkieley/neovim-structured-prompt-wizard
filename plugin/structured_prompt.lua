if vim.g.loaded_structured_prompt then
  return
end
vim.g.loaded_structured_prompt = true

local function complete_template(lead)
  return vim.tbl_filter(function(id)
    return id:sub(1, #lead) == lead
  end, require("structured_prompt").template_ids())
end

vim.api.nvim_create_user_command("StructuredPrompt", function(args)
  require("structured_prompt").open(args.args ~= "" and args.args or nil)
end, {
  nargs = "?",
  desc = "Open the structured prompt wizard",
  complete = complete_template,
})

vim.api.nvim_create_user_command("StructuredPromptBuffer", function(args)
  require("structured_prompt").open_buffer(args.args ~= "" and args.args or nil)
end, {
  nargs = "?",
  desc = "Build a prompt to replace the current text buffer when applied",
  complete = complete_template,
})

vim.api.nvim_create_user_command("StructuredPromptApply", function()
  require("structured_prompt").apply()
end, { desc = "Apply the prompt to its originating text buffer and close the wizard" })

vim.api.nvim_create_user_command("StructuredPromptToggle", function()
  require("structured_prompt").toggle()
end, { desc = "Toggle the structured prompt wizard" })

vim.api.nvim_create_user_command("StructuredPromptReload", function()
  require("structured_prompt").reload()
end, { desc = "Reload prompt templates from the configured JSON file" })
