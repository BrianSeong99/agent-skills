#!/usr/bin/env bash
# screenshot-grid.sh — bash wrapper for screenshot-grid.mjs
# Auto-bootstraps Playwright + Chromium if not present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MJS="$SCRIPT_DIR/screenshot-grid.mjs"

# --help shortcut before any bootstrap
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  exec node "$MJS" --help
fi

# ---------------------------------------------------------------------------
# Bootstrap Playwright if missing
# ---------------------------------------------------------------------------
bootstrap_playwright() {
  local dir
  # Prefer node_modules alongside the script; fall back to a temp dir
  dir="$(dirname "$SCRIPT_DIR")"
  if [ ! -d "$dir/node_modules/playwright" ]; then
    echo "[screenshot-grid] Playwright not found. Bootstrapping (this takes ~1 min)..."
    pushd "$dir" > /dev/null
    npm install --save-dev playwright 2>&1 | tail -5
    npx playwright install chromium
    popd > /dev/null
    echo "[screenshot-grid] Bootstrap complete."
  fi
}

# Check if playwright CLI is reachable
if ! npx --no playwright --version > /dev/null 2>&1; then
  bootstrap_playwright
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
exec node "$MJS" "$@"
