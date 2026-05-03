# screenshot-grid

Generate per-viewport Playwright screenshots of a list of routes. Captures mobile, laptop, desktop, and 2K viewports in one shot, waits for network idle, and writes PNGs to a timestamped output directory.

## Why

Inline Playwright HEREDOCs accumulate fast — the same `viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, reducedMotion: 'reduce'` block re-typed in every repo. This skill replaces all of that with a single parameterised command.

## Usage

Auto-trigger (Claude picks it up automatically):
- "take screenshots with playwright"
- "multi-viewport screenshot"
- "capture full page screenshots"
- "screenshot grid for these routes"
- "snap mobile/desktop/laptop"

Explicit invocation:
```
/screenshot-grid --base-url http://localhost:3000 --routes /,/about,/pricing
```

Or run the script directly:
```bash
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh \
  --base-url http://localhost:3000 \
  --routes /,/about,/pricing \
  --viewports mobile,laptop,desktop,2k
```

## Options

| Flag | Env var | Default | Effect |
|---|---|---|---|
| `--base-url` | `SCREENSHOT_BASE_URL` | `http://localhost:3000` | Base URL |
| `--routes` | `SCREENSHOT_ROUTES` | `/` | Comma-separated route list |
| `--out` | `SCREENSHOT_OUT` | `./screenshots/<timestamp>` | Output directory |
| `--viewports` | `SCREENSHOT_VIEWPORTS` | `mobile,laptop,desktop` | Which viewports to capture |
| `--full-page` | `SCREENSHOT_FULL_PAGE` | `true` | Full page vs viewport-only |
| `--dpr` | `SCREENSHOT_DPR` | `2` | deviceScaleFactor |
| `--reduced-motion` | `SCREENSHOT_REDUCED_MOTION` | `true` | `reducedMotion: 'reduce'` |
| `--wait-for` | `SCREENSHOT_WAIT_FOR` | `networkidle` | Playwright wait condition |
| `--timeout-ms` | `SCREENSHOT_TIMEOUT_MS` | `30000` | Per-page timeout |

Built-in viewports:

| Name | Width × Height |
|---|---|
| `mobile` | 390 × 844 |
| `laptop` | 1024 × 768 |
| `desktop` | 1440 × 900 |
| `2k` | 2560 × 1440 |

## Output

```
./screenshots/20240501-143022/
├── mobile/
│   ├── root.png
│   ├── about.png
│   └── pricing.png
├── laptop/
│   ├── root.png
│   ├── about.png
│   └── pricing.png
└── desktop/
    ├── root.png
    ├── about.png
    └── pricing.png
```

Route slugs: `/` → `root`, `/about` → `about`, `/some/deep/route` → `some-deep-route`.

## Prerequisites

The target dev server must be running before you invoke this skill. The script does not start servers — it only captures.

`playwright` and `chromium` are auto-installed if missing:
```bash
npm i -D playwright && npx playwright install chromium
```

## Install

```bash
./install.sh screenshot-grid
```

Or manually:
```bash
ln -sfn "$(pwd)/skills/screenshot-grid" ~/.claude/skills/screenshot-grid
```

## Files

```
skills/screenshot-grid/
├── SKILL.md                          # protocol Claude follows
├── README.md                         # this file
└── scripts/
    ├── screenshot-grid.mjs           # Playwright Node script
    └── screenshot-grid.sh            # bash wrapper with auto-install
```

## License

[MIT](../../LICENSE).
