---
name: screenshot-grid
description: Generate per-viewport (mobile / laptop / desktop / 2K) Playwright screenshots of a list of routes, wait for network idle, drop PNGs into a target dir. Use when the user says "take screenshots with playwright", "multi-viewport screenshot", "capture full page screenshots", "screenshot grid for these routes", "snap mobile/desktop/laptop", or explicitly invokes `/screenshot-grid`. Configurable via flags or env vars.
---

# screenshot-grid — multi-viewport Playwright screenshot capture

Capture per-viewport screenshots of one or more routes against a running dev server. Writes PNGs to a timestamped output directory, organised by viewport.

## Protocol — follow in order

### 1. Resolve configuration

Collect parameters from whichever source the user provides (flags inline, env vars, or conversation context). Defaults apply for anything omitted.

| Flag | Env var | Default | Meaning |
|---|---|---|---|
| `--base-url` | `SCREENSHOT_BASE_URL` | `http://localhost:3000` | Base URL to screenshot |
| `--routes` | `SCREENSHOT_ROUTES` | `/` | Comma-separated route list |
| `--out` | `SCREENSHOT_OUT` | `./screenshots/<timestamp>` | Output directory |
| `--viewports` | `SCREENSHOT_VIEWPORTS` | `mobile,laptop,desktop` | Comma-separated viewport names |
| `--full-page` | `SCREENSHOT_FULL_PAGE` | `true` | Full page vs viewport-only |
| `--dpr` | `SCREENSHOT_DPR` | `2` | deviceScaleFactor |
| `--reduced-motion` | `SCREENSHOT_REDUCED_MOTION` | `true` | Sets `reducedMotion: 'reduce'` |
| `--wait-for` | `SCREENSHOT_WAIT_FOR` | `networkidle` | Playwright wait condition |
| `--timeout-ms` | `SCREENSHOT_TIMEOUT_MS` | `30000` | Per-page navigation timeout |

Built-in viewport sizes:

| Name | Width × Height |
|---|---|
| `mobile` | 390 × 844 |
| `laptop` | 1024 × 768 |
| `desktop` | 1440 × 900 |
| `2k` | 2560 × 1440 |

### 2. Run the screenshot script

```bash
bash ~/.claude/skills/screenshot-grid/scripts/screenshot-grid.sh \
  --base-url <url> \
  --routes <routes> \
  --out <dir> \
  --viewports <viewports> \
  [--full-page true|false] \
  [--dpr <n>] \
  [--reduced-motion true|false] \
  [--wait-for <condition>] \
  [--timeout-ms <ms>]
```

The shell wrapper auto-installs `playwright` + `chromium` if missing (via `npm i -D playwright && npx playwright install chromium`). It then delegates to `screenshot-grid.mjs`.

### 3. Report results

After the script exits 0, report:
- Output directory path
- Number of PNGs written (viewports × routes)
- Any pages that errored (the script logs these and exits 1 if any failed)

If the script exits 1, surface the error log to the user.

### 4. Auto-trigger signals

This skill fires automatically when the user says:
- "take screenshots with playwright"
- "multi-viewport screenshot"
- "capture full page screenshots"
- "screenshot grid for these routes"
- "snap mobile/desktop/laptop"
- `/screenshot-grid` (explicit invocation)

When auto-triggered, infer `--base-url` and `--routes` from context. If the base URL cannot be inferred, ask one question: "What's the base URL to screenshot?"

## Hard guardrails

- **No hardcoded paths.** Everything is configurable via flags or env vars.
- **No partial captures.** If any page errors, exit code 1. Don't silently skip failed routes.
- **No browser installs beyond chromium.** The script only installs chromium to keep it fast. Don't install firefox or webkit unless the user explicitly asks.
- **Idempotent output dirs.** Each run gets its own timestamped subdir — don't overwrite previous runs.
- **Don't start a dev server.** This skill assumes the target server is already running. If it isn't, tell the user to start it first.

## Files

```
skills/screenshot-grid/
├── SKILL.md                          # this file — protocol Claude follows
├── README.md                         # user-facing docs
└── scripts/
    ├── screenshot-grid.mjs           # Playwright Node script
    └── screenshot-grid.sh            # bash wrapper with auto-install
```
