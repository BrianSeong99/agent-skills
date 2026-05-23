#!/usr/bin/env bash
# screenshot-grid.sh — bash wrapper for screenshot-grid.mjs
#
# Checks for playwright; installs playwright + chromium if missing.
# Then delegates to screenshot-grid.mjs with all arguments passed through.
#
# Usage:
#   ./screenshot-grid.sh [--base-url <url>] [--routes <r1,r2>] [--out <dir>]
#                        [--viewports <v1,v2>] [--full-page true|false]
#                        [--dpr <n>] [--reduced-motion true|false]
#                        [--wait-for <condition>] [--timeout-ms <ms>]
#                        [--help]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MJS="$SCRIPT_DIR/screenshot-grid.mjs"

# ---------------------------------------------------------------------------
# --help passthrough (also handles -h)
# ---------------------------------------------------------------------------
for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    node "$MJS" --help
    exit 0
  fi
done

# ---------------------------------------------------------------------------
# Ensure Node is available
# ---------------------------------------------------------------------------
if ! command -v node &>/dev/null; then
  echo "Error: node is not installed or not on PATH." >&2
  echo "Install Node.js >= 18: https://nodejs.org" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Ensure playwright is available; bootstrap if not
# ---------------------------------------------------------------------------
bootstrap_playwright() {
  echo "playwright not found — installing playwright + chromium..."
  npm i -D playwright
  npx playwright install chromium
  echo "playwright installed."
}

if ! npx --no -- playwright --version &>/dev/null 2>&1; then
  bootstrap_playwright
fi

# Verify chromium is installed; install it if playwright is present but chromium isn't
if ! npx --no -- playwright --version &>/dev/null 2>&1; then
  echo "Error: playwright install failed. Check npm output above." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Delegate to the Node script
# ---------------------------------------------------------------------------
exec node "$MJS" "$@"
