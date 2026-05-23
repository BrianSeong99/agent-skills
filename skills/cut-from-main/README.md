# cut-from-main

Branch off `origin/main` cleanly.

If a repository still uses `master` as its default branch, this skill can rename
it to `main` before creating the requested branch.

## Usage

```bash
bash skills/cut-from-main/scripts/cut.sh <branch-name>
```

Approve the `master` to `main` rename without an interactive prompt:

```bash
bash skills/cut-from-main/scripts/cut.sh <branch-name> --auto-rename
```

Use an explicit base when the remote default branch is neither `main` nor
`master`:

```bash
bash skills/cut-from-main/scripts/cut.sh <branch-name> --base <ref>
```

## Behavior

- Verifies the current directory is a git repository.
- Verifies `origin` exists.
- Detects the remote default branch from `origin/HEAD`, with a GitHub CLI
  fallback.
- Creates the branch from `origin/main` when the default branch is `main`.
- Refuses to create branches from `master`.
- Can rename a `master` default branch to `main` with confirmation.

## Help

```bash
bash skills/cut-from-main/scripts/cut.sh --help
```
