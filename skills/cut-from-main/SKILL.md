---
name: cut-from-main
description: Branch off origin/main cleanly. Fetches before cutting. If the repo's default branch is master, offers to run the four-step master→main rename (or does it silently with --auto-rename) before cutting the new branch. Refuses to branch off non-main defaults unless --base override is given. Use when the user says "create a new branch", "cut a branch from main", "start a feature branch", "branch off main", "new feature branch", or runs `/cut-from-main <branch-name>`.
---

# cut-from-main — always branch from origin/main

Your job: cut a new branch from `origin/main`, handling the case where the repo's default is still `master` (or something else entirely).

House rule being encoded: **every working branch is cut from `main`. No exceptions.**

## Protocol — follow in order

### 1. Capture the input

The user supplies one of:
- `/cut-from-main <branch-name>` — explicit invocation.
- A natural phrase: "create a new branch called X", "start a feature branch for Y", "cut a branch from main named Z".

Extract:
- `branch_name` — required. If missing, ask once.
- `--auto-rename` flag — skip the master→main confirmation.
- `--base <ref>` — override base ref (for repos deliberately on a non-main default).

### 2. Run the script

Execute:

```bash
bash ~/.claude/skills/cut-from-main/scripts/cut.sh <branch-name> [--auto-rename] [--base <ref>]
```

The script is the source of truth. Read its output and surface any errors verbatim to the user.

### 3. Script behavior (what to expect)

The script follows this decision tree:

1. **Verify cwd is a git repo.** Exit 1 with explanation if not.
2. **Verify `origin` remote exists.** Exit 1 if not.
3. **Detect default branch:**
   - `git symbolic-ref refs/remotes/origin/HEAD --short` → strip `origin/`.
   - If that fails, fall back to `gh api repos/:owner/:repo --jq .default_branch` (warns if `gh` not logged in).
4. **If default is `main`:** run `git fetch origin main && git checkout -b <name> origin/main`. Done.
5. **If default is `master`:**
   - Without `--auto-rename`: prompt "This repo's default branch is master. Rename to main now? [y/N]".
   - On yes (or `--auto-rename`): run the four-step rename, then cut the branch.
   - On no: exit 1 — refusing to cut from `master` per house rule.
6. **If default is anything else:** exit 1 with explanation; user can pass `--base <ref>` to override.

### 4. Master→main rename sequence (steps run inside the script)

```bash
git fetch origin master
git checkout master && git pull --ff-only
git branch -m master main
git push -u origin main
gh repo edit --default-branch main   # warns if gh not logged in
git push origin --delete master
```

Then cut the new branch:

```bash
git checkout -b <name> origin/main
```

### 5. Return to user

On success:
```
Branch <name> cut from origin/main.
```
Plus any rename output if the master→main rename ran.

On failure: surface the script's stderr verbatim. Do not paraphrase error messages.

## Hard guardrails

- **Never cut from `master` directly.** If the user declines the rename, refuse and explain.
- **Never cut from a non-main default** unless `--base` is explicitly passed.
- **`git fetch origin main` runs every time**, even if the repo looks current. Stale tracking refs are a common source of drift.
- **No stacked branches.** This skill cuts from `main` only — if the user asks to branch from another feature branch, flag the stacking risk and refuse unless `--base` is passed.
- **`gh` failures are non-fatal** for the rename (the local+remote state is already correct after `push -u origin main` + `push origin --delete master`); surface a warning but continue.

## Flags

| Flag | Behavior |
|---|---|
| `--auto-rename` | Skip the master→main confirmation prompt. |
| `--base <ref>` | Use `<ref>` instead of `origin/main` as the base. Skips all default-branch detection. |
| `--help` | Print usage and exit 0. |

## Out of scope

- Setting up branch protection rules after rename.
- Auto-updating `.github/` workflows that reference `master`.
- PR base-branch migration.
