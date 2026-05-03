---
name: cut-from-main
description: Branch off origin/main cleanly, renaming a master-default repository to main first when explicitly confirmed or auto-approved.
---

# cut-from-main — branch from origin/main

Create a new branch from `origin/main`. If the repository still defaults to
`master`, rename the default branch to `main` before creating the new branch.

## Trigger

Explicit:

```bash
/cut-from-main <branch-name>
```

Auto-trigger when the user asks to:

- create a new branch
- cut a branch from main
- start a feature branch
- branch off main
- make a new feature branch

## Protocol

1. Capture the requested branch name exactly as supplied by the user.
2. Run the helper from the repository where the branch should be created:

   ```bash
   bash ~/.claude/skills/cut-from-main/scripts/cut.sh <branch-name>
   ```

3. Surface script output and errors verbatim. Do not paraphrase failures.
4. If the user has explicitly approved default-branch renaming, pass
   `--auto-rename`:

   ```bash
   bash ~/.claude/skills/cut-from-main/scripts/cut.sh <branch-name> --auto-rename
   ```

5. If the repository default branch is neither `main` nor `master`, refuse to
   guess. Tell the user they can override the base explicitly:

   ```bash
   bash ~/.claude/skills/cut-from-main/scripts/cut.sh <branch-name> --base <ref>
   ```

## Behavior

The helper enforces these rules:

- Verify the current directory is a git repository.
- Verify a remote named `origin` exists.
- Detect the remote default branch from `origin/HEAD`, falling back to the
  GitHub repository default branch through `gh api`.
- If the default branch is `main`, fetch `origin/main` and create the new
  branch from `origin/main`.
- If the default branch is `master`, ask before renaming unless `--auto-rename`
  was passed.
- Rename `master` to `main` with:
  `git branch -m`, `git push -u origin main`,
  `gh repo edit --default-branch main`, and
  `git push origin --delete master`.
- Refuse to cut from `master` when the user declines the rename.
- Refuse other default branches unless `--base <ref>` is supplied.

## Guardrails

- Do not create branches from `master`.
- Do not silently rename the remote default branch. Require confirmation unless
  the user requested `--auto-rename`.
- Do not hide git or GitHub CLI errors. The script output is the source of
  truth for the user.
