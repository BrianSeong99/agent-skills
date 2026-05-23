#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  cut.sh <branch-name> [--auto-rename] [--base <ref>]
  cut.sh --help

Create <branch-name> from origin/main.

Options:
  --auto-rename   Rename a master-default repo to main without prompting.
  --base <ref>    Override default-branch policy and create from <ref>.
  -h, --help      Show this help.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

warn() {
  echo "warning: $*" >&2
}

run() {
  echo "+ $*" >&2
  "$@"
}

is_yes() {
  case "$1" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

remote_url_to_slug() {
  local url="$1"
  local slug=""

  case "$url" in
    git@github.com:*)
      slug="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      slug="${url#ssh://git@github.com/}"
      ;;
    https://github.com/*)
      slug="${url#https://github.com/}"
      ;;
    http://github.com/*)
      slug="${url#http://github.com/}"
      ;;
    github.com/*)
      slug="${url#github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  slug="${slug%.git}"
  slug="${slug%%/*}/${slug#*/}"

  if [[ "$slug" == */* && "$slug" != /* && "$slug" != */ ]]; then
    printf '%s\n' "$slug"
    return 0
  fi

  return 1
}

detect_default_branch() {
  local default_branch=""
  local origin_url=""
  local slug=""

  default_branch="$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null || true)"
  if [ -n "$default_branch" ]; then
    printf '%s\n' "${default_branch#origin/}"
    return 0
  fi

  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin_url" ] && slug="$(remote_url_to_slug "$origin_url")"; then
    gh api "repos/$slug" --jq .default_branch 2>/dev/null || return 1
    return 0
  fi

  gh api repos/:owner/:repo --jq .default_branch 2>/dev/null || return 1
}

checkout_from_base() {
  local branch_name="$1"
  local base_ref="$2"

  if [[ "$base_ref" == origin/* ]]; then
    run git fetch origin "${base_ref#origin/}"
  fi
  run git checkout -b "$branch_name" "$base_ref"
}

rename_master_to_main() {
  run git fetch origin master
  run git checkout master
  run git pull --ff-only
  run git branch -m master main
  run git push -u origin main

  if ! gh repo edit --default-branch main; then
    warn "gh repo edit --default-branch main failed; continuing"
  fi

  run git push origin --delete master
  run git fetch origin main
}

branch_name=""
auto_rename=0
base_ref=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --auto-rename)
      auto_rename=1
      shift
      ;;
    --base)
      shift
      [ $# -gt 0 ] || die "--base requires a ref"
      base_ref="$1"
      shift
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      [ -z "$branch_name" ] || die "only one branch name may be supplied"
      branch_name="$1"
      shift
      ;;
  esac
done

[ -n "$branch_name" ] || {
  usage >&2
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "current directory is not a git repository"
git remote get-url origin >/dev/null 2>&1 || die "remote 'origin' not found"

if [ -n "$base_ref" ]; then
  checkout_from_base "$branch_name" "$base_ref"
  exit 0
fi

default_branch="$(detect_default_branch || true)"
[ -n "$default_branch" ] || die "could not detect origin default branch; pass --base <ref> to override"

case "$default_branch" in
  main)
    checkout_from_base "$branch_name" origin/main
    ;;
  master)
    if [ "$auto_rename" -eq 1 ]; then
      rename_master_to_main
    else
      printf 'Default is master. Rename now? [y/N] ' >&2
      read -r answer || answer=""
      if ! is_yes "$answer"; then
        die "refusing to cut from master; rerun with --auto-rename or approve the rename"
      fi
      rename_master_to_main
    fi
    run git checkout -b "$branch_name" origin/main
    ;;
  *)
    die "origin default branch is '$default_branch', not main or master; pass --base <ref> to override"
    ;;
esac
