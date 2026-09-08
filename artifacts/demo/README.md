# Video walkthrough

[Watch the updated video on YouTube](https://youtu.be/2tpgUYRdvzc) — unlisted, uploaded to the
James Kieley channel on September 7, 2026.

`structured-prompt-demo.mp4` is the local copy: 1920×1080, H.264, 30 fps,
2 minutes 19 seconds, with on-screen instructions and no narration. The video renders
the actual UI events from an isolated Neovim 0.12.2 process, driven by scripted
keystrokes and pastes. No desktop or personal files were recorded.

The recording demonstrates the twelve bundled templates, a complete CO-STAR
brief, source-grounded answers, debugging and research prompts, and personal
JSON configuration. It adds a seventh CO-STAR field and a release-notes template,
reloads without losing answers, and copies/exports the completed prompt.

| Time | Demonstration |
| --- | --- |
| 0:00 | Choose from twelve templates |
| 0:18 | Fill a CO-STAR brief with Vim navigation |
| 0:39 | Evidence, debugging, and research prompts |
| 1:02 | Configure a personal JSON catalog |
| 1:16 | Add a field and reload without losing drafts |
| 1:38 | Add a release-notes template |
| 1:57 | Copy and export Markdown |

[example-prompt.md](example-prompt.md) contains the exported output.
[catalog.json](catalog.json) is the final demo catalog, with thirteen templates;
the bundled catalog still has twelve. [config.lua](config.lua) points Neovim to
this separate demo copy. The README's ready-to-copy configurations live in
[examples/](../../examples/). [youtube-description.txt](youtube-description.txt)
records the published description and chapter timestamps.

To regenerate on macOS, from the repository root:

```sh
python3 -m venv /tmp/structured-prompt-video-venv
/tmp/structured-prompt-video-venv/bin/pip install -r tools/requirements-demo.txt
/tmp/structured-prompt-video-venv/bin/python tools/record_demo.py
```

Neovim and ffmpeg must be on PATH. The renderer defaults to macOS Menlo and
Arial fonts; override `DEMO_MONO_FONT` and `DEMO_SANS_FONT` on other systems.
The shared renderer now generates native 3840×2160 video at 30 fps. The published
JSON walkthrough above is the earlier 1080p recording; the
[pi round-trip walkthrough](../pi-demo/README.md) is available in 4K.
Regeneration resets the demo catalog from the bundled catalog and reapplies the
scripted additions. It does not change the bundled catalog or the YouTube upload.

The [original walkthrough](https://youtu.be/VZCgaEoYbIY) remains available.
