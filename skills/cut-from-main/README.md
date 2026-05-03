# cut-from-main

Always branch from `origin/main`. Detects the repo's default branch, offers to rename `master → main` (with confirmation, or silently via `--auto-rename`), and refuses to branch off any other default unless `--base` is given.

## Why

The house rule is simple: every working branch is cut from `main`. No exceptions. In practice that means:

1. You have to remember to run `git fetch origin main` before cutting — otherwise you branch off a stale ref.
2. If the repo's default is still `master`, you have to remember the four-step rename before you can follow the rule.
3. If you forget either step, you end up with a branch that's behind or that sets a precedent of working off `master`.

This skill encodes both steps as a single command so neither gets skipped.

## Usage

Auto-trigger on phrases like "create a new branch", "cut a branch from main", "start a feature branch", "branch off main", "new feature branch".

Or explicit:

```
/cut-from-main <branch-name>
```

Flags:

| Flag | Effect |
|---|---|
| `--auto-rename` | Skip the master→main confirmation prompt. |
| `--base <ref>` | Use `<ref>` as the base (bypasses all default-branch detection). |
| `--help` | Print usage. |

## Behavior

```
/cut-from-main feat/my-feature
```

1. Verifies cwd is a git repo with an `origin` remote.
2. Detects the default branch (`git symbolic-ref` → `gh api` fallback).
3. **Default is `main`:** fetches and cuts. Done.
4. **Default is `master`:** prompts to rename (or runs rename silently with `--auto-rename`), then cuts. Refuses if the user declines.
5. **Default is anything else:** exits with an explanation; pass `--base <ref>` to override.

### Master → main rename sequence

When the rename runs:

```bash
git fetch origin master
git checkout master && git pull --ff-only
git branch -m master main
git push -u origin main
gh repo edit --default-branch main   # best-effort; warns if gh not logged in
git push origin --delete master
# then:
git fetch origin main
git checkout -b <branch-name> origin/main
```

## Install

```bash
./install.sh cut-from-main
```

Or manually:

```bash
ln -sfn "$(pwd)/skills/cut-from-main" ~/.claude/skills/cut-from-main
```

## Files

```
skills/cut-from-main/
├── SKILL.md              # protocol Claude follows
├── README.md             # this file
└── scripts/
    └── cut.sh            # shell implementation
```

## Hard caps

- **Never branch from `master`** directly — rename or refuse.
- **Never branch from a non-main default** unless `--base` is passed.
- **`git fetch origin main` runs every time**, even if the repo looks current.
- **No stacked branches** — this skill only cuts from `main`.
- **`gh` failures are non-fatal** during rename — local+remote state is already correct; a warning is shown.

## License

[MIT](../../LICENSE).
