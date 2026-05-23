---
name: screenshot-grid
description: Multi-viewport Playwright screenshots of a list of routes — desktop/laptop/mobile defaults, DPR 2x, network-idle wait, output PNGs to a target dir. Use when the user says "take screenshots with playwright", "multi-viewport screenshot", "capture full page screenshots", or "screenshot grid for these routes". Also runs as `/screenshot-grid`. Accepts --base-url, --routes, --out, --viewports, --full-page, --dpr, --reduced-motion, --wait-for, --timeout-ms flags (or env equivalents).
---

# screenshot-grid — multi-viewport Playwright screenshots

Capture structured PNGs of an existing site across configurable viewports. Built for visual comparison workflows: run before and after a design change, or feed the output into an ensemble review.

## When to trigger

**Explicit:** `/screenshot-grid`

**Auto-trigger phrases:**
- "take screenshots with playwright"
- "multi-viewport screenshot"
- "capture full page screenshots"
- "screenshot grid for these routes"

## Protocol

1. Check if the user supplied a `--base-url` or `SCREENSHOT_BASE_URL`. Default is `http://localhost:3000`.
2. Resolve the script path: `~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh`.
3. Forward all user-supplied flags verbatim to the script.
4. After capture: report the output directory and list the files created (grouped by viewport).

## Script invocation

```bash
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh \
  --base-url <url> \
  --routes <comma-sep-routes> \
  --out <output-dir> \
  --viewports <mobile,laptop,desktop> \
  [additional flags...]
```

## Flags

| Flag | Env | Default | Description |
|---|---|---|---|
| `--base-url` | `SCREENSHOT_BASE_URL` | `http://localhost:3000` | Base URL to screenshot |
| `--routes` | `SCREENSHOT_ROUTES` | `/` | Comma-separated route list |
| `--out` | `SCREENSHOT_OUT` | `./screenshots/<timestamp>` | Output directory |
| `--viewports` | `SCREENSHOT_VIEWPORTS` | `mobile,laptop,desktop` | Built-in presets or `WxH` custom |
| `--full-page` | `SCREENSHOT_FULL_PAGE` | `true` | Full page vs viewport-only |
| `--dpr` | `SCREENSHOT_DPR` | `2` | deviceScaleFactor |
| `--reduced-motion` | `SCREENSHOT_REDUCED_MOTION` | `true` | Sets `reducedMotion: 'reduce'` |
| `--wait-for` | `SCREENSHOT_WAIT_FOR` | `networkidle` | Playwright waitUntil value |
| `--timeout-ms` | `SCREENSHOT_TIMEOUT_MS` | `30000` | Per-page timeout (ms) |

## Built-in viewport presets

| Name | Width × Height |
|---|---|
| `mobile` | 390 × 844 |
| `laptop` | 1024 × 768 |
| `desktop` | 1440 × 900 |
| `2k` | 2560 × 1440 |

Custom viewports: `--viewports 800x600,1280x800`

## Output structure

```
<out>/
  mobile/
    index.png          # route /  → slug "index"
    about.png          # route /about → slug "about"
    pricing.png
  laptop/
    index.png
    ...
  desktop/
    ...
```

## Install

```bash
# from the agent-skills repo root
./install.sh screenshot-grid
```
