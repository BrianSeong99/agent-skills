# screenshot-grid

Multi-viewport Playwright screenshots of a list of routes. Captures PNGs across configurable viewports with DPR 2x, reduced motion, and network-idle wait by default.

## Install

```bash
# from the agent-skills repo root
./install.sh screenshot-grid
```

This symlinks `skills/screenshot-grid/` into `~/.claude/skills/screenshot-grid/`.

Playwright is **auto-bootstrapped** the first time you run the script — no manual install needed.

## Usage

```bash
# Basic — screenshots / on localhost:3000 at mobile/laptop/desktop
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh

# Custom routes and base URL
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh \
  --base-url http://localhost:4000 \
  --routes /,/about,/pricing,/docs

# Custom output dir and viewports
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh \
  --out ./screenshots/before \
  --viewports mobile,desktop,2k

# Viewport-only (not full page)
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh \
  --full-page false

# Print help
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh --help
```

## Options

| Flag | Env var | Default | Description |
|---|---|---|---|
| `--base-url` | `SCREENSHOT_BASE_URL` | `http://localhost:3000` | Base URL to screenshot |
| `--routes` | `SCREENSHOT_ROUTES` | `/` | Comma-separated list of routes |
| `--out` | `SCREENSHOT_OUT` | `./screenshots/<timestamp>` | Output directory |
| `--viewports` | `SCREENSHOT_VIEWPORTS` | `mobile,laptop,desktop` | Comma-separated presets or `WxH` |
| `--full-page` | `SCREENSHOT_FULL_PAGE` | `true` | Capture full scrollable page |
| `--dpr` | `SCREENSHOT_DPR` | `2` | deviceScaleFactor (retina) |
| `--reduced-motion` | `SCREENSHOT_REDUCED_MOTION` | `true` | Disable animations |
| `--wait-for` | `SCREENSHOT_WAIT_FOR` | `networkidle` | Playwright `waitUntil` value |
| `--timeout-ms` | `SCREENSHOT_TIMEOUT_MS` | `30000` | Per-page timeout (ms) |

### Built-in viewport presets

| Preset | Width × Height |
|---|---|
| `mobile` | 390 × 844 |
| `laptop` | 1024 × 768 |
| `desktop` | 1440 × 900 |
| `2k` | 2560 × 1440 |

Custom sizes accepted: `--viewports 800x600,1280x800`

## Output structure

```
<out>/
  mobile/
    index.png         # / → "index"
    about.png         # /about → "about"
    docs-getting-started.png  # /docs/getting-started → slug
  laptop/
    index.png
    ...
  desktop/
    ...
```

Route slugs: leading `/` stripped, remaining `/` replaced with `-`, empty becomes `index`.

## Exit behavior

Exits non-zero if any page fails to load or screenshot. Partial output may exist in `--out` for completed pages.

## Requirements

- Node.js 18+
- Internet access for first-run Playwright/Chromium download (~170 MB)
