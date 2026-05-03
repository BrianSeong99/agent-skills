#!/usr/bin/env bash
# run-checks.sh
#
# Autodetects and runs install/typecheck/test/build for the current worktree.
# Streams output, exits non-zero on first failure.
#
# Env overrides (any non-empty value wins; pass an empty string to skip):
#   WORKTREE_PR_INSTALL
#   WORKTREE_PR_TYPECHECK
#   WORKTREE_PR_TEST
#   WORKTREE_PR_BUILD
#
# Detection table (lockfile-driven):
#   pnpm-lock.yaml      -> pnpm
#   package-lock.json   -> npm
#   bun.lockb / bun.lock-> bun
#   Cargo.toml          -> cargo
#
# Exit codes:
#   0 = all detected steps passed
#   1 = a step failed (which one is in the [step] header)
#   2 = bad invocation (not in a git worktree, etc.)

set -euo pipefail

# Locate the worktree root (works inside a worktree too).
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "run-checks: not inside a git repo" >&2
  exit 2
}
cd "$repo_root"

# ---- helpers ----

# pkg_json_has <script>: returns 0 if package.json defines the named script.
pkg_json_has() {
  local script="$1"
  [ -f package.json ] || return 1
  # Use node-free check: look for "<script>": pattern under "scripts".
  # This is fragile but cheap — if we miss a script the user can override via env.
  grep -Eq "\"${script}\"[[:space:]]*:" package.json || return 1
  return 0
}

# detect_install / typecheck / test / build: each echoes a command (or empty).
detect_install() {
  if [ -f pnpm-lock.yaml ]; then
    echo "pnpm install --frozen-lockfile"
  elif [ -f package-lock.json ]; then
    echo "npm ci"
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then
    echo "bun install --frozen-lockfile"
  elif [ -f Cargo.toml ]; then
    echo "cargo fetch"
  else
    echo ""
  fi
}

detect_typecheck() {
  if [ -f pnpm-lock.yaml ]; then
    if pkg_json_has typecheck; then echo "pnpm typecheck"
    elif [ -f tsconfig.json ]; then echo "pnpm exec tsc --noEmit"
    else echo ""
    fi
  elif [ -f package-lock.json ]; then
    if pkg_json_has typecheck; then echo "npm run typecheck"
    elif [ -f tsconfig.json ]; then echo "npx --no-install tsc --noEmit"
    else echo ""
    fi
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then
    if pkg_json_has typecheck; then echo "bun run typecheck"
    elif [ -f tsconfig.json ]; then echo "bunx tsc --noEmit"
    else echo ""
    fi
  elif [ -f Cargo.toml ]; then
    echo "cargo check --all-targets"
  else
    echo ""
  fi
}

detect_test() {
  if [ -f pnpm-lock.yaml ]; then
    if pkg_json_has test; then echo "pnpm test"; else echo ""; fi
  elif [ -f package-lock.json ]; then
    if pkg_json_has test; then echo "npm test"; else echo ""; fi
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then
    if pkg_json_has test; then echo "bun test"; else echo ""; fi
  elif [ -f Cargo.toml ]; then
    echo "cargo test"
  else
    echo ""
  fi
}

detect_build() {
  if [ -f pnpm-lock.yaml ]; then
    if pkg_json_has build; then echo "pnpm build"; else echo ""; fi
  elif [ -f package-lock.json ]; then
    if pkg_json_has build; then echo "npm run build"; else echo ""; fi
  elif [ -f bun.lockb ] || [ -f bun.lock ]; then
    if pkg_json_has build; then echo "bun run build"; else echo ""; fi
  elif [ -f Cargo.toml ]; then
    echo "cargo build"
  else
    echo ""
  fi
}

# resolve_step <env-var-name> <detect-fn>: env override beats detect; empty = skip.
resolve_step() {
  local var_name="$1"
  local detect_fn="$2"
  # Use indirect expansion to read the env var (and distinguish unset vs empty).
  if [ "${!var_name+set}" = "set" ]; then
    echo "${!var_name}"
  else
    "$detect_fn"
  fi
}

run_step() {
  local label="$1"
  local cmd="$2"
  if [ -z "$cmd" ]; then
    echo "[$label] no command detected — skipping (set WORKTREE_PR_${label^^} to override)" >&2
    return 0
  fi
  echo "[$label] $cmd" >&2
  # shellcheck disable=SC2086
  if ! bash -c "$cmd"; then
    echo "[$label] FAILED" >&2
    return 1
  fi
  echo "[$label] ok" >&2
}

# ---- resolve all four steps up front so the user sees the plan before we start ----

install_cmd=$(resolve_step WORKTREE_PR_INSTALL detect_install)
typecheck_cmd=$(resolve_step WORKTREE_PR_TYPECHECK detect_typecheck)
test_cmd=$(resolve_step WORKTREE_PR_TEST detect_test)
build_cmd=$(resolve_step WORKTREE_PR_BUILD detect_build)

cat >&2 <<EOF
[plan]
  install:   ${install_cmd:-(skip)}
  typecheck: ${typecheck_cmd:-(skip)}
  test:      ${test_cmd:-(skip)}
  build:     ${build_cmd:-(skip)}
EOF

# If everything is empty, surface that loudly — likely an unsupported repo.
if [ -z "$install_cmd$typecheck_cmd$test_cmd$build_cmd" ]; then
  cat >&2 <<EOF

[run-checks] no commands detected for this repo. Either:
  - pass WORKTREE_PR_{INSTALL,TYPECHECK,TEST,BUILD} env vars before re-running, or
  - skip this skill's check phase if the repo doesn't have a build pipeline.
EOF
  exit 0
fi

# ---- run them in order, fail-fast ----

run_step install   "$install_cmd"
run_step typecheck "$typecheck_cmd"
run_step test      "$test_cmd"
run_step build     "$build_cmd"

echo "[run-checks] all passed" >&2
