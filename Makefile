NVIM ?= nvim
export TEMPLATES

.PHONY: test demo validate-templates
test:
	$(NVIM) --headless -u NONE -l tests/run.lua

demo:
	$(NVIM) -u tests/minimal_init.lua -c StructuredPrompt

validate-templates:
	$(NVIM) --headless -u NONE -l tools/validate_templates.lua
