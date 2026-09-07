#!/usr/bin/env python3
"""Render a real, isolated Neovim UI session to a captioned MP4.

Dependencies: Neovim, ffmpeg, Pillow, msgpack. No desktop capture or user config.
Protocol: https://neovim.io/doc/user/api-ui-events/
Run from the project root: python tools/record_demo.py
"""

import json
import os
from pathlib import Path
import select
import subprocess
import time
from textwrap import indent

import msgpack
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts" / "demo"
FRAMES = OUT / "frames"
FRAMES.mkdir(parents=True, exist_ok=True)
COLS, ROWS = 124, 28
CW, CH = 14, 29
X, Y = 92, 113
WIDTH, HEIGHT = 1920, 1080


class Neovim:
    def __init__(self):
        self.proc = subprocess.Popen(
            ["nvim", "--embed", "-u", "tests/minimal_init.lua", "-i", "NONE", "-n"],
            cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.unpacker = msgpack.Unpacker(raw=False, strict_map_key=False)
        self.ident = 0
        self.responses = {}
        self.grid = [[(" ", 0)] * COLS for _ in range(ROWS)]
        self.hl = {}
        self.fg, self.bg = 0xE0E2EA, 0x14161B
        self.cursor = (0, 0)
        self.mode = "normal"
        self.call("nvim_ui_attach", COLS, ROWS, {"rgb": True, "ext_linegrid": True})
        self.pump(0.12)
        self.call("nvim_exec_lua", """
          vim.o.background = 'dark'
          vim.o.showtabline = 0
          vim.o.ruler = true
          vim.o.showmode = true
          vim.o.laststatus = 3
          vim.o.fillchars = 'eob: '
          vim.o.statusline = '  NEOVIM  |  structured-prompt.nvim %=%l:%c  '
          vim.o.clipboard = ''
          vim.o.autoindent = false
          vim.o.smartindent = false
          vim.o.linebreak = true
          vim.o.shortmess = vim.o.shortmess .. 'I'
          vim.cmd('syntax enable')
          vim.cmd('redraw!')
        """, [])
        self.pump(0.05)

    def events(self, batches):
        for batch in batches:
            name = batch[0]
            for args in batch[1:]:
                if name == "grid_resize" and args[0] == 1:
                    self.grid = [[(" ", 0)] * args[1] for _ in range(args[2])]
                elif name == "default_colors_set":
                    self.fg, self.bg = args[:2]
                elif name == "hl_attr_define":
                    self.hl[args[0]] = args[1]
                elif name == "grid_clear" and args[0] == 1:
                    self.grid = [[(" ", 0)] * len(self.grid[0]) for _ in self.grid]
                elif name == "grid_line" and args[0] == 1:
                    _, row, col, cells = args[:4]
                    highlight = 0
                    for cell in cells:
                        if len(cell) > 1:
                            highlight = cell[1]
                        repeat = cell[2] if len(cell) > 2 else 1
                        for _ in range(repeat):
                            self.grid[row][col] = (cell[0], highlight)
                            col += 1
                elif name == "grid_scroll" and args[0] == 1:
                    _, top, bottom, left, right, rows, cols = args
                    old = [line[:] for line in self.grid]
                    for row in range(top, bottom):
                        for col in range(left, right):
                            sr, sc = row + rows, col + cols
                            if top <= sr < bottom and left <= sc < right:
                                self.grid[row][col] = old[sr][sc]
                elif name == "grid_cursor_goto" and args[0] == 1:
                    self.cursor = tuple(args[1:3])
                elif name == "mode_change":
                    self.mode = args[0]

    def pump(self, seconds=0.02):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            ready, _, _ = select.select([self.proc.stdout], [], [], max(0, end - time.monotonic()))
            if not ready:
                break
            data = os.read(self.proc.stdout.fileno(), 65536)
            if not data:
                raise RuntimeError("Neovim exited: " + self.proc.stderr.read().decode())
            self.unpacker.feed(data)
            for message in self.unpacker:
                if message[0] == 1:
                    self.responses[message[1]] = (message[2], message[3])
                elif message[0] == 2 and message[1] == "redraw":
                    self.events(message[2])

    def call(self, method, *args):
        self.ident += 1
        ident = self.ident
        self.proc.stdin.write(msgpack.packb([0, ident, method, args], use_bin_type=True))
        self.proc.stdin.flush()
        deadline = time.monotonic() + 10
        while ident not in self.responses:
            if time.monotonic() > deadline:
                raise TimeoutError(method)
            self.pump(0.02)
        error, result = self.responses.pop(ident)
        if error:
            raise RuntimeError(f"{method}: {error}")
        return result

    def keys(self, value):
        self.call("nvim_input", value)
        self.pump(0.025)

    def screen_text(self):
        return "\n".join("".join(cell[0] for cell in line) for line in self.grid)


def rgb(value):
    return ((value >> 16) & 255, (value >> 8) & 255, value & 255)


mono_path = os.environ.get("DEMO_MONO_FONT", "/System/Library/Fonts/Menlo.ttc")
sans_path = os.environ.get("DEMO_SANS_FONT", "/System/Library/Fonts/Supplemental/Arial.ttf")
mono = ImageFont.truetype(mono_path, 22)
sans = ImageFont.truetype(sans_path, 28)
small = ImageFont.truetype(sans_path, 22)
heading = ImageFont.truetype(sans_path, 34)


class Recording:
    def __init__(self, nvim, label="Live Neovim session  /  scripted keystrokes", output=OUT,
                 filename="structured-prompt-demo.mp4"):
        self.nvim = nvim
        self.label = label
        self.output = Path(output)
        self.frame_dir = self.output / "frames"
        self.frame_dir.mkdir(parents=True, exist_ok=True)
        self.filename = filename
        self.frames = []
        self.chapters = []
        self.elapsed = 0
        self.title, self.caption, self.key = "", "", ""

    def section(self, title, caption, key=""):
        self.title, self.caption, self.key = title, caption, key
        self.chapters.append({"time": round(self.elapsed, 2), "title": title})
        print(f"{self.elapsed:5.1f}s  {title}", flush=True)

    def frame(self, duration=0.12, still=None):
        image = Image.new("RGB", (WIDTH, HEIGHT), "#0b101b")
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((72, 98, 1848, 940), radius=14, fill="#1c2333", outline="#344159", width=2)
        draw.text((92, 29), "STRUCTURED PROMPT WIZARD", font=heading, fill="#e6edf7")
        label = self.label
        draw.text((1828 - draw.textlength(label, font=small), 40), label, font=small, fill="#91a2bc")
        for row, line in enumerate(self.nvim.grid):
            for col, (text, attr_id) in enumerate(line):
                attr = self.nvim.hl.get(attr_id, {})
                fg = rgb(attr.get("foreground", self.nvim.fg))
                bg = rgb(attr.get("background", self.nvim.bg))
                if attr.get("reverse"):
                    fg, bg = bg, fg
                x, y = X + col * CW, Y + row * CH
                draw.rectangle((x, y, x + CW - 1, y + CH - 1), fill=bg)
                if text.strip():
                    draw.text((x, y + 2), text, font=mono, fill=fg, stroke_width=0)
                if attr.get("underline"):
                    draw.line((x, y + CH - 3, x + CW, y + CH - 3), fill=fg)
        row, col = self.nvim.cursor
        x, y = X + col * CW, Y + row * CH
        if not getattr(self.nvim, "cursor_visible", True):
            pass
        elif self.nvim.mode.startswith("insert"):
            draw.rectangle((x, y + 2, x + 2, y + CH - 2), fill="#7fe0c2")
        else:
            draw.rectangle((x, y + 1, x + CW - 1, y + CH - 2), outline="#7fe0c2", width=2)
        draw.text((92, 960), self.title, font=sans, fill="#7fe0c2")
        draw.text((92, 1004), self.caption, font=small, fill="#c8d3e5")
        if self.key:
            kw = draw.textlength(self.key, font=mono) + 40
            draw.rounded_rectangle((1828 - kw, 955, 1828, 996), radius=8, fill="#213e43")
            draw.text((1848 - kw, 962), self.key, font=mono, fill="#a9f5da")
        path = self.frame_dir / f"{len(self.frames):04d}.png"
        image.save(path)
        self.frames.append((path, duration))
        self.elapsed += duration
        if still:
            image.save(self.output / f"{still}.png")

    def keys(self, value, duration=0.5):
        self.nvim.keys(value)
        self.frame(duration)

    def type(self, value, pace=0.09):
        for char in value:
            self.nvim.keys("<CR>" if char == "\n" else "<lt>" if char == "<" else char)
            self.frame(pace)

    def encode(self):
        manifest = self.output / "frames.ffconcat"
        with manifest.open("w") as file:
            file.write("ffconcat version 1.0\n")
            for path, duration in self.frames:
                file.write(f"file '{path}'\nduration {duration:.3f}\n")
            file.write(f"file '{self.frames[-1][0]}'\n")
        (self.output / "chapters.json").write_text(json.dumps(self.chapters, indent=2) + "\n")
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", "-safe", "0",
            "-i", str(manifest), "-r", "30", "-c:v", "libx264", "-crf", "18",
            "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            str(self.output / self.filename),
        ], check=True)
        print(f"Saved {self.elapsed:.1f}s demo to {self.output / self.filename}", flush=True)

    def paste(self, value, duration=2):
        """Use Neovim's paste API for longer example text and JSON blocks."""
        self.nvim.call("nvim_paste", value, False, -1)
        self.nvim.pump(0.04)
        self.frame(duration)

    def command(self, command, duration=2):
        self.type(":" + command, 0.045)
        self.keys("<CR>", duration)


def main():
    catalog_path = OUT / "catalog.json"
    catalog = json.loads((ROOT / "templates/prompts.json").read_text())
    catalog["$schema"] = "../../templates/schema.json"
    catalog_path.write_text(json.dumps(catalog, indent=2) + "\n")
    (OUT / "config.lua").write_text(
        '-- Demo copy; a personal catalog can use vim.fn.stdpath("config").\n'
        'require("structured_prompt").setup({\n'
        '  templates_file = "artifacts/demo/catalog.json",\n'
        '  sidebar_width = 34,\n'
        '  preview = false,\n'
        '})\n\n'
        '-- With LazyVim / lazy.nvim, put these options in the plugin spec opts.\n'
    )
    nvim = Neovim()
    nvim.call("nvim_command", "luafile artifacts/demo/config.lua")
    recording = Recording(nvim)
    try:
        recording.section("01  Twelve templates, ready to fill", "Writing, coding, research, evidence, extraction, and decisions in one sidebar.", ":StructuredPrompt")
        recording.frame(1)
        recording.command("StructuredPrompt", 4)
        assert "STRUCTURED PROMPT" in nvim.screen_text()
        assert "Research a topic" in nvim.screen_text()
        recording.frame(2, "01-templates")

        recording.section("02  Write a CO-STAR brief", "Context, objective, style, tone, audience, response. Enter selects the template.", "j / k  |  Enter")
        recording.keys("3j", 2)
        recording.keys("<CR>", 2.2)
        recording.keys("i", 0.4)
        recording.type("We built a structured prompt wizard for Neovim.\nIt now loads twelve templates from JSON.", 0.045)
        recording.keys("<Esc>", 1.8)

        recording.section("03  Multiline answers, familiar Vim keys", "Each field has its own buffer. ]f moves forward; [f goes back.", "]f  /  [f")
        recording.keys("]f", 1.7)
        recording.keys("i", 0.2)
        recording.type("Write a launch announcement that helps readers try it.", 0.045)
        recording.section("Keep typing across fields", "Ctrl-g then Ctrl-n moves to the next field without leaving insert mode.", "Ctrl-g  Ctrl-n")
        for answer in [
            "A practical developer announcement.",
            "Friendly and concise; no hype.",
            "Neovim and LazyVim users who write prompts regularly.",
            "A title, three benefits, and a quick-start checklist.",
        ]:
            recording.keys("<C-g><C-n>", 0.8)
            recording.type(answer, 0.035)
        recording.keys("<Esc>", 1.6)
        values = nvim.call("nvim_exec_lua", "return require('structured_prompt').get_values()", [])
        assert values["context"].startswith("We built a structured prompt wizard")
        assert values["audience"].startswith("Neovim and LazyVim")
        assert values["response"].startswith("A title, three benefits")

        recording.section("04  Preview instructions and answers", "Reusable template instructions appear before the populated field sections.", ",p")
        recording.keys(",p", 4)
        recording.frame(2, "02-preview")

        recording.section("05  Explore prompts for different tasks", "Answer from sources asks for supplied evidence, references, and explicit uncertainty.", "grounded_answer")
        recording.command("StructuredPrompt grounded_answer", 2)
        recording.keys("i", 0.2)
        recording.paste("How do I add a template without changing Lua?", 2)
        recording.keys("<C-g><C-n>", 1)
        recording.paste("[S1] Templates are stored in a versioned JSON catalog.\n[S2] Save the JSON and run :StructuredPromptReload.\n[S3] Stable template and field IDs preserve session drafts.", 4)
        recording.keys("<Esc>", 1)
        recording.frame(2, "03-sources")

        recording.section("A focused debugging brief", "Capture expected vs actual behavior, a reproduction, evidence, and fix constraints.", "debug_diagnosis")
        recording.command("StructuredPrompt debug_diagnosis", 3)
        recording.section("Research with explicit scope", "Define perspectives, a source policy, and an evidence-led output.", "research_brief")
        recording.command("StructuredPrompt research_brief", 3)

        recording.section("06  Point to your own JSON catalog", "Use templates_file in setup(), or the same option in your LazyVim plugin's opts.", "templates_file")
        recording.command("tabnew artifacts/demo/config.lua", 4)
        recording.frame(2, "04-config")
        recording.command("edit artifacts/demo/catalog.json", 1)
        recording.type('/"id": "response"', 0.045)
        recording.keys("<CR>", 1)
        recording.keys("zz", 2)

        recording.section("07  Add an input field in JSON", "Append a field with an ID, label, and hint. Array order controls navigation.", "Edit JSON  |  :write")
        recording.keys("4jA,<Esc>o<C-u>", 1)
        new_field = {"id": "success", "label": "Success criteria", "hint": "What must the final answer include?"}
        recording.paste(indent(json.dumps(new_field, indent=2), "        "), 4)
        recording.keys("<Esc>", 0.5)
        recording.command("write", 1)
        updated = json.loads(catalog_path.read_text())
        co_star = next(item for item in updated["templates"] if item["id"] == "co_star")
        assert co_star["fields"][-1] == new_field
        recording.frame(2, "05-json-field")

        recording.section("08  Reload and keep your draft", "The wizard rereads the catalog. Matching IDs preserve all six answers.", ":StructuredPromptReload")
        recording.command("StructuredPrompt co_star", 1)
        recording.command("StructuredPromptReload", 2)
        restored = nvim.call("nvim_exec_lua", "return require('structured_prompt').get_values()", [])
        assert all(restored[key] == value for key, value in values.items())
        assert restored["success"] == ""
        for _ in range(6):
            recording.keys("]f", 0.35)
        recording.keys("i", 0.2)
        recording.paste("Readers can install, select a template, and export a prompt.", 3)
        recording.keys("<Esc>", 1)
        recording.frame(2, "06-reload")

        recording.section("09  Add a template the same way", "Each template has reusable instructions and its own ordered fields.", "Append to templates")
        recording.command("tabnext", 0.7)
        recording.keys("G2kA,<Esc>o<C-u>", 1)
        release_notes = json.loads((ROOT / "examples/release-notes.json").read_text())["templates"][0]
        recording.paste(indent(json.dumps(release_notes, indent=2), "    "), 2)
        recording.keys("<Esc>", 0.5)
        recording.type('/"id": "release_notes"', 0.045)
        recording.keys("<CR>zt", 4)
        recording.command("write", 1)
        assert json.loads(catalog_path.read_text())["templates"][-1] == release_notes
        recording.command("StructuredPromptReload", 1)
        recording.command("StructuredPrompt release_notes", 3)
        recording.frame(2, "07-new-template")
        assert nvim.call("nvim_exec_lua", "return require('structured_prompt').template_ids()", [])[-1] == "release_notes"

        recording.section("10  Copy or export the finished prompt", "The CO-STAR draft includes the extra field. Export opens ordinary Markdown.", ",y  /  ,e")
        recording.command("StructuredPrompt co_star", 1.5)
        recording.keys(",y", 2)
        copied = nvim.call("nvim_eval", "getreg('\"')")
        assert "## Success criteria" in copied and values["context"] in copied
        recording.keys(",e", 1.2)
        recording.keys("<C-w>_", 2)
        exported = nvim.call("nvim_buf_get_lines", 0, 0, -1, False)
        assert "## Success criteria" in exported
        (OUT / "example-prompt.md").write_text("\n".join(exported) + "\n")
        recording.frame(2, "08-export")
        recording.keys("G", 3)

        recording.section("Make the catalog your own", "Editable JSON  |  Draft-preserving reload  |  LazyVim or plain Neovim", "README: config examples")
        recording.command("StructuredPrompt", 1.5)
        recording.frame(5, "09-finish")
        recording.encode()
    finally:
        nvim.proc.terminate()
        nvim.proc.wait(timeout=5)


if __name__ == "__main__":
    main()
