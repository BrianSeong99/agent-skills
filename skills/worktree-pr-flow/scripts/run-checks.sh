#!/usr/bin/env bash
set -euo pipefail

has_package_script() {
  local script_name="$1"

  if [ ! -f package.json ]; then
    return 1
  fi

  node -e '
const fs = require("fs");
const script = process.argv[1];
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
process.exit(pkg.scripts && Object.prototype.hasOwnProperty.call(pkg.scripts, script) ? 0 : 1);
' "$script_name"
}

run_step() {
  local label="$1"
  local command="$2"

  if [ -z "$command" ]; then
    echo "skip $label"
    return 0
  fi

  echo "run $label: $command"
  bash -lc "$command"
}

PM=""

if [ -f pnpm-lock.yaml ]; then
  PM="pnpm"
elif [ -f package-lock.json ]; then
  PM="npm"
elif [ -f bun.lockb ]; then
  PM="bun"
elif [ -f Cargo.toml ]; then
  PM="cargo"
fi

INSTALL="${WORKTREE_PR_INSTALL:-}"
TYPECHECK="${WORKTREE_PR_TYPECHECK:-}"
TEST="${WORKTREE_PR_TEST:-}"
BUILD="${WORKTREE_PR_BUILD:-}"

if [ -z "$PM" ] &&
  [ -z "$INSTALL" ] &&
  [ -z "$TYPECHECK" ] &&
  [ -z "$TEST" ] &&
  [ -z "$BUILD" ]; then
  echo 'no commands detected; set WORKTREE_PR_INSTALL/TYPECHECK/TEST/BUILD to override' >&2
  exit 1
fi

if [ -n "$PM" ]; then
  case "$PM" in
    pnpm)
      INSTALL="${INSTALL:-pnpm install}"
      if [ -z "$TYPECHECK" ] && has_package_script typecheck; then
        TYPECHECK="pnpm typecheck"
      fi
      TEST="${TEST:-pnpm test}"
      BUILD="${BUILD:-pnpm build}"
      ;;
    npm)
      INSTALL="${INSTALL:-npm ci}"
      if [ -z "$TYPECHECK" ] && has_package_script typecheck; then
        TYPECHECK="npm run typecheck"
      fi
      TEST="${TEST:-npm test}"
      BUILD="${BUILD:-npm run build}"
      ;;
    bun)
      INSTALL="${INSTALL:-bun install}"
      if [ -z "$TYPECHECK" ] && has_package_script typecheck; then
        TYPECHECK="bun run typecheck"
      fi
      TEST="${TEST:-bun test}"
      BUILD="${BUILD:-bun run build}"
      ;;
    cargo)
      TYPECHECK="${TYPECHECK:-cargo check}"
      TEST="${TEST:-cargo test}"
      BUILD="${BUILD:-cargo build --release}"
      ;;
  esac
fi

run_step install "$INSTALL"
run_step typecheck "$TYPECHECK"
run_step test "$TEST"
run_step build "$BUILD"
