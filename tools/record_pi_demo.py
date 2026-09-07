#!/usr/bin/env python3
"""Record an actual pi -> Neovim -> pi round trip through an isolated tmux TTY.

Requires pi, tmux, nvim, ffmpeg and requirements-demo.txt. Uses the existing pi
login, sends one benign prompt to the selected model, and saves no pi session.
The captured terminal cells are rendered by Pillow; this is not a desktop capture.
Set DEMO_PROVIDER / DEMO_MODEL to choose an authenticated provider and model.
"""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import uuid

import pyte

from record_demo import COLS, ROWS, ROOT, Recording

OUT = ROOT / "artifacts" / "pi-demo"
TASK = "Write a short welcome for a structured prompt wizard.\nExplain how it helps Neovim users turn an idea into a clear request."
CONSTRAINTS = "Address Neovim and LazyVim users.\nStay under 90 words. Do not use tools or edit files."
OUTPUT = "Three concise bullets: choose a template, fill the fields, submit the prompt."
EXPECTED = f"## Task definition\n\n{TASK}\n\n## Constraints\n\n{CONSTRAINTS}\n\n## Expected output\n\n{OUTPUT}"


class Terminal:
    def __init__(self, directory, editor):
        self.directory = directory
        self.socket = "structured-prompt-demo-" + uuid.uuid4().hex[:12]
        self.tmux_config = directory / "tmux.conf"
        self.tmux_config.write_text("set -g status off\nset -g extended-keys on\nset -g extended-keys-format csi-u\n")
        self.target = "demo:0.0"
        self.fg, self.bg = 0xE0E2EA, 0x14161B
        self.cursor, self.mode, self.cursor_visible = (0, 0), "insert", True
        self.grid, self.hl = [], {}
        config = directory / "agent"
        config.mkdir(mode=0o700)
        auth = Path(os.environ.get("PI_CODING_AGENT_DIR", Path.home() / ".pi/agent")) / "auth.json"
        if auth.exists():
            # Keep normal OAuth refresh ownership; never copy or print credentials.
            (config / "auth.json").symlink_to(auth.resolve())
        (config / "settings.json").write_text(json.dumps({
            "externalEditor": str(editor),
            "lastChangelogVersion": subprocess.check_output(["pi", "--version"], text=True).strip(),
            "quietStartup": False,
            "hideThinkingBlock": True,
            "enableInstallTelemetry": False,
            "enableAnalytics": False,
            "retry": {"enabled": False, "provider": {"timeoutMs": 60000, "maxRetries": 0}},
        }))
        work = directory / "prompt-demo"
        work.mkdir()
        command = [
            "env", f"PI_CODING_AGENT_DIR={config}", "PI_TELEMETRY=0",
            "PATH=" + str(auth.parent / "bin") + os.pathsep + os.environ["PATH"],
            shutil.which("pi"), "--provider", os.environ.get("DEMO_PROVIDER", "openai-codex"),
            "--model", os.environ.get("DEMO_MODEL", "gpt-5.6-terra"), "--thinking", "low",
            "--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates",
            "--no-themes", "--no-context-files", "--no-approve", "--offline",
            "--system-prompt", "You help write concise prose. Follow the supplied writing brief. Do not use tools.",
        ]
        self.run("new-session", "-d", "-s", "demo", "-x", str(COLS), "-y", str(ROWS),
                 "-c", str(work), shlex.join(command))
        self.run("set-option", "-g", "status", "off")
        self.run("set-option", "-g", "remain-on-exit", "on")

    def run(self, *args):
        return subprocess.check_output(["tmux", "-L", self.socket, "-f", str(self.tmux_config), *args], text=True)

    def capture(self):
        raw = self.run("capture-pane", "-p", "-e", "-N", "-t", self.target)
        screen = pyte.Screen(COLS, ROWS)
        # capture-pane emits LF, but terminal rows must also reset the column.
        pyte.Stream(screen).feed("\r\n".join(raw.splitlines()))
        attrs = {}
        self.hl, self.grid = {}, []
        colors = {
            "black": 0x14161B, "red": 0xEF7D7D, "green": 0xA8D6A0,
            "brown": 0xDAB774, "blue": 0x86ACEC, "magenta": 0xCF9CE8,
            "cyan": 0x83D6CB, "white": 0xE0E2EA,
            "brightblack": 0x737A91, "brightred": 0xFF9999, "brightgreen": 0xB5EBAC,
            "brightbrown": 0xF3D398, "brightblue": 0xABC8FF, "brightmagenta": 0xEAB4FF,
            "brightcyan": 0xA1F2E5, "brightwhite": 0xFFFFFF,
        }
        def color(value, fallback):
            if value == "default":
                return fallback
            return colors[value] if value in colors else int(value, 16)
        for row in range(ROWS):
            line = []
            for col in range(COLS):
                cell = screen.buffer[row][col]
                key = (cell.fg, cell.bg, cell.reverse, cell.underscore)
                if key not in attrs:
                    ident = len(attrs) + 1
                    attrs[key] = ident
                    self.hl[ident] = {
                        "foreground": color(cell.fg, self.fg), "background": color(cell.bg, self.bg),
                        "reverse": cell.reverse, "underline": cell.underscore,
                    }
                line.append((cell.data, attrs[key]))
            self.grid.append(line)
        x, y, visible = self.run("display-message", "-p", "-t", self.target,
                                  "#{cursor_x} #{cursor_y} #{cursor_flag}").strip().split()
        self.cursor = (int(y), int(x))
        self.cursor_visible = visible == "1"

    def screen_text(self):
        self.capture()
        return "\n".join("".join(cell[0] for cell in row).rstrip() for row in self.grid)

    def keys(self, value):
        special = {"<CR>": "Enter", "<Esc>": "Escape", "<C-g>": "C-g", "<C-n>": "C-n", "<C-p>": "C-p",
                   "<PageUp>": "PPage", "<PageDown>": "NPage"}
        for token in re.split(r"(<CR>|<Esc>|<C-g>|<C-n>|<C-p>|<PageUp>|<PageDown>)", value):
            if token:
                self.run("send-keys", "-t", self.target, *([special[token]] if token in special else ["-l", token]))
        time.sleep(0.06)

    def wait_for(self, text, timeout=25):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if text in self.screen_text():
                return
            time.sleep(0.2)
        raise RuntimeError(f"Timed out waiting for {text!r}. Screen:\n{self.screen_text()}")

    def close(self):
        self.run("kill-server")


class TerminalRecording(Recording):
    def __init__(self, terminal):
        super().__init__(terminal, "Actual pi + Neovim TTY  /  scripted keys", OUT, "structured-prompt-pi-demo.mp4")

    def frame(self, duration=0.12, still=None):
        self.nvim.capture()
        super().frame(duration, still)

    def type(self, value, pace=0.09):
        # Small literal chunks keep the recording legible without hundreds of PNGs.
        for line_index, line in enumerate(value.split("\n")):
            if line_index:
                self.keys("<CR>", 0.35)
            for i in range(0, len(line), 4):
                self.nvim.keys(line[i:i + 4])
                self.frame(pace * min(4, len(line) - i))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="structured-prompt-pi-", dir="/tmp") as path:
        directory = Path(path)
        init = directory / "init.lua"
        init.write_text("\n".join([
            f"vim.opt.runtimepath:prepend({json.dumps(str(ROOT))})",
            'vim.g.mapleader = " "', 'vim.g.maplocalleader = ","',
            'vim.o.termguicolors = true', 'vim.o.hidden = true', 'vim.o.background = "dark"',
            'vim.o.showtabline = 0', 'vim.o.laststatus = 3', 'vim.o.showmode = true',
            'vim.o.fillchars = "eob: "', 'vim.o.shortmess = vim.o.shortmess .. "I"',
            'vim.o.statusline = "  NEOVIM  |  %t %=%l:%c  "',
            'vim.o.autoindent = false', 'vim.o.smartindent = false', 'vim.o.clipboard = ""',
            'vim.o.linebreak = true', 'vim.cmd("syntax enable")',
            'require("structured_prompt").setup({ sidebar_width = 34, preview = false })',
        ]) + "\n")
        editor = directory / "editor"
        # Keep a copy of this demo's output for an independent round-trip assertion.
        editor.write_text("#!/bin/sh\n" + shlex.join([shutil.which("nvim"), "-u", str(init), "-i", "NONE", "-n"]) +
                          ' "$@"\nstatus=$?\nif [ "$status" -eq 0 ]; then\n  cp "$1" ' +
                          shlex.quote(str(directory / "completed-prompt.md")) + '\nfi\nexit "$status"\n')
        editor.chmod(0o700)
        terminal = Terminal(directory, editor)
        recording = TerminalRecording(terminal)
        try:
            terminal.wait_for("pi v")
            recording.section("01  Start in pi", "Ctrl+G opens pi's current prompt in your configured external editor.", "Ctrl+G")
            recording.frame(4, "01-pi")
            recording.keys("<C-g>", 1)
            terminal.wait_for("NEOVIM")
            terminal.mode = "normal"
            recording.frame(3, "02-editor")

            recording.section("02  Build a prompt for this buffer", "The wizard remembers pi's editor file as the destination.", ":StructuredPromptBuffer")
            recording.command("StructuredPromptBuffer", 3)
            terminal.wait_for("General task")
            assert "Research a topic" in terminal.screen_text()
            recording.frame(2, "03-templates")
            recording.keys("<CR>", 1)
            terminal.wait_for("Change template")
            assert "Research a topic" not in terminal.screen_text()
            recording.section("03  Choose once, then focus on the fields", "The template catalog is hidden. Each answer has its own multiline Vim buffer.", "i")
            recording.frame(4, "04-fields")
            terminal.mode = "insert"
            recording.keys("i", 0.4)
            recording.type(TASK, 0.065)
            recording.frame(2)

            recording.section("04  Move between fields without leaving Insert", "Ctrl+G, Ctrl+N advances to the next answer; regular Vim editing still works.", "Ctrl+G  Ctrl+N")
            recording.keys("<C-g><C-n>", 1.2)
            recording.type(CONSTRAINTS, 0.065)
            recording.frame(2)
            recording.keys("<C-g><C-n>", 1.2)
            recording.type(OUTPUT, 0.065)
            recording.keys("<Esc>", 1)
            terminal.mode = "normal"
            recording.keys(",p", 3)
            recording.frame(3, "05-preview")

            recording.section("05  Apply the complete prompt to pi's file", "Comma is this demo's LocalLeader. Apply replaces the original buffer and returns to it.", ",a")
            recording.keys(",a", 4)
            assert "## Task definition" in terminal.screen_text()
            assert "Change template" not in terminal.screen_text()
            recording.frame(3, "06-applied")
            recording.section("06  Save and return to pi", ":wq saves the editor file. pi restores the full text to its input, ready for review.", ":wq")
            recording.command("wq", 2)
            terminal.wait_for(os.environ.get("DEMO_MODEL", "gpt-5.6-terra"))
            terminal.mode = "insert"
            completed = (directory / "completed-prompt.md").read_text().rstrip("\n")
            assert completed == EXPECTED, (completed, EXPECTED)
            (OUT / "example-prompt.md").write_text(completed + "\n")
            assert "Three concise bullets" in terminal.screen_text()
            recording.frame(3, "07-pi-prompt")
            recording.key = "Page Up / Page Down"
            recording.caption = "The full multiline prompt is back in pi. Page Up and Page Down let you review it."
            recording.keys("<PageUp><PageUp>", 3)
            assert "## Task definition" in terminal.screen_text()
            recording.keys("<PageDown><PageDown>", 2)

            recording.section("07  Submit the prompt", "Enter sends the assembled text to the model. This is a real pi response.", "Enter")
            recording.keys("<CR>", 1)
            deadline, last, stable = time.monotonic() + 90, "", 0
            while time.monotonic() < deadline:
                current = terminal.screen_text()
                if "Error:" in current or "failed" in current.lower():
                    raise RuntimeError("pi submission failed:\n" + current)
                stable = stable + 1 if current == last else 0
                last = current
                recording.frame(0.5)
                # Completed generations have no active abort/working indicator.
                bullets = len(re.findall(r"^\s*[•*\-]\s", current, re.MULTILINE))
                if stable >= 6 and bullets >= 3 and "esc to abort" not in current.lower() and "working" not in current.lower():
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError("Model response did not finish within 90 seconds")
            (OUT / "response-terminal.txt").write_text(terminal.screen_text().rstrip() + "\n")
            recording.section("08  One round trip, ready to repeat", "pi → Ctrl+G → wizard → apply → :wq → Enter. Templates and fields are configurable JSON.", "Complete")
            recording.frame(8, "08-response")
            recording.encode()
        finally:
            terminal.close()


if __name__ == "__main__":
    main()
