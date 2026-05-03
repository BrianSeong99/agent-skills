#!/usr/bin/env bash
# finish-pr.sh <topic> [--squash] [--force]
#
# Phase 2 of the worktree-pr-flow ritual: clean up after a merged PR.
#   1. Verify PR is MERGED on the remote (via gh pr view --json state).
#   2. Switch primary worktree to main, pull --ff-only.
#   3. Remove the worktree (--force only if --force passed).
#   4. Delete the local branch (-d, or -D if --squash).
#   5. Delete the remote branch (idempotent; succeeds if already gone).
#
# Env (all optional):
#   WORKTREE_PR_BASE   (default: origin/main; only the branch portion is used)
#   WORKTREE_PR_PREFIX (default: ${USER}/, e.g. brian/)
#   WORKTREE_PR_DIR    (default: worktrees, relative to repo root)
#
# Exit codes:
#   0 = clean
#   1 = generic failure (git error, etc.)
#   2 = bad invocation
#   3 = PR not merged (and --force not passed)

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: finish-pr.sh <topic> [--squash] [--force]

  --squash   the PR was squash-merged (use git branch -D, the branch isn't fast-forward).
  --force    skip the "PR is MERGED" check and force-remove dirty worktrees.
EOF
  exit 2
}

topic=""
squash=0
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --squash) squash=1; shift ;;
    --force)  force=1;  shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "finish-pr: unknown flag: $1" >&2; usage ;;
    *)
      if [ -z "$topic" ]; then topic="$1"; shift
      else echo "finish-pr: extra positional arg: $1" >&2; usage
      fi
      ;;
  esac
done

[ -n "$topic" ] || usage

if ! printf '%s' "$topic" | grep -Eq '^[a-z0-9][a-z0-9-]{0,39}$'; then
  echo "finish-pr: invalid topic slug '$topic'" >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "finish-pr: not inside a git repo" >&2
  exit 2
}

# Resolve the *primary* worktree root, not the topic worktree itself —
# this script must run from anywhere and clean up the topic worktree.
primary_root=$(git -C "$repo_root" worktree list --porcelain \
  | awk '/^worktree /{print substr($0, 10); exit}')
[ -n "$primary_root" ] || {
  echo "finish-pr: could not resolve primary worktree" >&2
  exit 1
}

base="${WORKTREE_PR_BASE:-origin/main}"
prefix="${WORKTREE_PR_PREFIX:-${USER}/}"
dir_rel="${WORKTREE_PR_DIR:-worktrees}"
dir_rel="${dir_rel%/}"

# Derive the main branch name from the base ref (origin/main -> main).
main_branch="${base#*/}"
if [ "$main_branch" = "$base" ]; then
  # base had no remote prefix; use as-is.
  main_branch="$base"
fi

branch="${prefix}${topic}"
worktree_path="${primary_root}/${dir_rel}/${topic}"

# ---- step 1: verify merged on the remote ----

if [ "$force" -eq 1 ]; then
  echo "[verify] --force: skipping PR-merged check" >&2
elif ! command -v gh >/dev/null 2>&1; then
  echo "[verify] gh CLI not installed — cannot verify PR state. Pass --force to skip." >&2
  exit 1
else
  echo "[verify] gh pr view ${branch} --json state" >&2
  state=$(gh pr view "$branch" --json state -q .state 2>/dev/null) || {
    echo "[verify] no PR found for branch ${branch}." >&2
    echo "         If the branch was merged via a different mechanism, pass --force." >&2
    exit 3
  }
  case "$state" in
    MERGED)
      echo "[verify] PR is MERGED — proceeding." >&2
      ;;
    *)
      echo "[verify] PR is ${state} — refusing to clean up." >&2
      echo "         Merge the PR first, or pass --force to clean up regardless." >&2
      exit 3
      ;;
  esac
fi

# ---- step 2: switch primary worktree to main, pull --ff-only ----

# Only do this if the primary isn't already on main with no dirty state — leave the user's WIP alone.
current_branch=$(git -C "$primary_root" symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ "$current_branch" != "$main_branch" ]; then
  if ! git -C "$primary_root" diff --quiet || ! git -C "$primary_root" diff --cached --quiet; then
    echo "[main] primary worktree has uncommitted changes; not switching to ${main_branch}." >&2
    echo "       Commit/stash first, then re-run; or skip this step manually." >&2
    exit 1
  fi
  echo "[main] git -C ${primary_root} checkout ${main_branch}" >&2
  git -C "$primary_root" checkout "$main_branch"
fi

echo "[main] git -C ${primary_root} pull --ff-only" >&2
git -C "$primary_root" pull --ff-only || {
  echo "[main] pull --ff-only failed — your local main has diverged. Resolve manually." >&2
  exit 1
}

# ---- step 3: remove the worktree ----

if [ ! -e "$worktree_path" ]; then
  echo "[worktree] ${worktree_path} does not exist — already cleaned up?" >&2
else
  if [ "$force" -eq 1 ]; then
    echo "[worktree] git worktree remove --force ${worktree_path}" >&2
    git -C "$primary_root" worktree remove --force "$worktree_path"
  else
    echo "[worktree] git worktree remove ${worktree_path}" >&2
    git -C "$primary_root" worktree remove "$worktree_path"
  fi
fi

# ---- step 4: delete the local branch ----

if git -C "$primary_root" show-ref --verify --quiet "refs/heads/${branch}"; then
  if [ "$squash" -eq 1 ] || [ "$force" -eq 1 ]; then
    echo "[branch] git branch -D ${branch}" >&2
    git -C "$primary_root" branch -D "$branch"
  else
    echo "[branch] git branch -d ${branch}" >&2
    if ! git -C "$primary_root" branch -d "$branch"; then
      echo "[branch] -d refused (branch not fully merged into upstream)." >&2
      echo "         If the PR was squash-merged, re-run with --squash." >&2
      exit 1
    fi
  fi
else
  echo "[branch] local ${branch} not found — already deleted?" >&2
fi

# ---- step 5: delete the remote branch (idempotent) ----

# If the remote already deleted it (e.g., GitHub "auto-delete head branches" setting),
# this should silently succeed.
remote_name="${base%%/*}"
if [ "$remote_name" = "$base" ]; then
  remote_name="origin"
fi

echo "[remote] git push ${remote_name} --delete ${branch}" >&2
if ! git -C "$primary_root" push "$remote_name" --delete "$branch" 2>/dev/null; then
  # Check if it just doesn't exist remotely.
  if ! git -C "$primary_root" ls-remote --exit-code --heads "$remote_name" "$branch" >/dev/null 2>&1; then
    echo "[remote] ${branch} already gone on ${remote_name} — ok." >&2
  else
    echo "[remote] failed to delete ${branch} on ${remote_name}" >&2
    exit 1
  fi
fi

echo "[finish-pr] cleanup complete: ${branch}" >&2
