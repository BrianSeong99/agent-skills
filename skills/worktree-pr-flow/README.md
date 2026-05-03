# worktree-pr-flow

## Purpose

`worktree-pr-flow` provides a small, repeatable ritual for pull-request work:

1. Create a dedicated git worktree and branch for a topic.
2. Run project checks with autodetection and fail-closed behavior.
3. Clean up the local and remote branch only after GitHub reports the PR as merged.

The scripts are intentionally conservative. They refuse ambiguous starts, fail when no check commands can be detected, and avoid force deletion of remote branches.

## Environment Variables

| name | default | effect |
|---|---|---|
| `WORKTREE_PR_BASE` | `origin/main` | Base branch used to create worktrees and update the main worktree during cleanup |
| `WORKTREE_PR_PREFIX` | `${USER}/` | Branch name prefix prepended to the topic slug |
| `WORKTREE_PR_DIR` | `worktrees/` | Parent directory for created worktrees |
| `WORKTREE_PR_INSTALL` | `autodetect` | Install command override |
| `WORKTREE_PR_TYPECHECK` | `autodetect` | Typecheck command override |
| `WORKTREE_PR_TEST` | `autodetect` | Test command override |
| `WORKTREE_PR_BUILD` | `autodetect` | Build command override |

## Scripts Overview

### `scripts/start-pr.sh`

Creates a new branch and worktree for a topic.

```bash
bash skills/worktree-pr-flow/scripts/start-pr.sh my-topic
```

The topic must match `^[a-z0-9][a-z0-9-]*$`. The script fetches `origin`, refuses existing branches or worktree directories, creates the worktree from `WORKTREE_PR_BASE`, and prints the absolute path.

### `scripts/run-checks.sh`

Runs install, typecheck, test, and build steps for the current project.

```bash
bash skills/worktree-pr-flow/scripts/run-checks.sh
```

Autodetection supports:

| signal | commands |
|---|---|
| `pnpm-lock.yaml` | `pnpm install`, optional `pnpm typecheck`, `pnpm test`, `pnpm build` |
| `package-lock.json` | `npm ci`, optional `npm run typecheck`, `npm test`, `npm run build` |
| `bun.lockb` | `bun install`, optional `bun run typecheck`, `bun test`, `bun run build` |
| `Cargo.toml` | `cargo check`, `cargo test`, `cargo build --release` |

For JavaScript projects, the `typecheck` step is skipped when `package.json` has no `typecheck` script.

### `scripts/finish-pr.sh`

Cleans up a PR worktree after merge verification.

```bash
bash skills/worktree-pr-flow/scripts/finish-pr.sh my-topic
```

The script verifies the PR state is `MERGED`, updates the main worktree with `git pull --ff-only`, removes the worktree, deletes the local branch, and deletes the remote branch. Pass `--squash` to use local `branch -D` after a squash merge.

## Quickstart

```bash
bash skills/worktree-pr-flow/scripts/start-pr.sh my-topic
cd worktrees/my-topic
# make changes, commit, and push
bash skills/worktree-pr-flow/scripts/run-checks.sh
gh pr create --base main --head "${USER}/my-topic" --title "feat: my topic" --body-file skills/worktree-pr-flow/templates/pr-body.md
```

After the PR is merged:

```bash
bash skills/worktree-pr-flow/scripts/finish-pr.sh my-topic
```
