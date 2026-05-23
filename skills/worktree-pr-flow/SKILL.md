---
name: worktree-pr-flow
version: 1.0.0
description: Create isolated git worktrees for PR work, run fail-closed checks, and clean up only after merge verification.
triggers:
  - make a PR for
  - open a PR
  - ship this as a PR
  - create a worktree for
  - start a PR
---

# worktree-pr-flow — isolated worktree PR pipeline

Use this skill when a task should become a pull request in its own git worktree. The protocol is intentionally linear: create an isolated branch/worktree, do the work there, run checks that fail closed, open the PR, then clean up only after GitHub reports the PR as merged.

## Protocol — follow in order

### 1. Start PR work

Choose a short topic slug that matches `^[a-z0-9][a-z0-9-]*$`. The topic becomes both the suffix of the branch name and the worktree directory name.

```bash
bash skills/worktree-pr-flow/scripts/start-pr.sh "<topic>"
```

The script:
- Reads `WORKTREE_PR_BASE` (default `origin/main`), `WORKTREE_PR_PREFIX` (default `${USER}/`), and `WORKTREE_PR_DIR` (default `worktrees/`).
- Fetches `origin`.
- Refuses to continue if the target branch or worktree directory already exists.
- Creates a new worktree at `${WORKTREE_PR_DIR}${topic}` with branch `${WORKTREE_PR_PREFIX}${topic}`.
- Prints the absolute worktree path.

Change into the printed worktree path before editing files.

### 2. Make the change

Implement only the requested PR scope inside the created worktree. Preserve unrelated user changes and do not edit outside the worktree unless the user explicitly asks.

When the implementation is ready, stage and commit from the worktree with a concise conventional commit message when applicable.

### 3. Run checks

Run the checks from the repository root inside the PR worktree:

```bash
bash skills/worktree-pr-flow/scripts/run-checks.sh
```

The script autodetects `pnpm`, `npm`, `bun`, or `cargo` from lockfiles/manifests. It runs install, typecheck, test, and build commands for the detected project type, with step overrides available through `WORKTREE_PR_INSTALL`, `WORKTREE_PR_TYPECHECK`, `WORKTREE_PR_TEST`, and `WORKTREE_PR_BUILD`.

The check runner is fail-closed. If no project type and no command overrides are detected, it exits non-zero with instructions to set override commands. Never treat a no-command run as success.

### 4. Open the pull request

Push the branch and create a PR using the repository's normal remote and base branch. Use `templates/pr-body.md` as the body shape unless the user supplied a different PR body.

```bash
git push -u origin "<branch>"
gh pr create --base "<base-branch>" --head "<branch>" --title "<title>" --body-file skills/worktree-pr-flow/templates/pr-body.md
```

Report the PR URL to the user.

### 5. Finish after merge

Only run cleanup after the PR is merged on GitHub:

```bash
bash skills/worktree-pr-flow/scripts/finish-pr.sh "<topic>"
```

Use `--squash` only when the local branch needs forced local deletion because the merged history does not contain the local branch tip:

```bash
bash skills/worktree-pr-flow/scripts/finish-pr.sh "<topic>" --squash
```

The script:
- Verifies `gh pr view <branch>` reports `MERGED`.
- Pulls the configured base into the main worktree with `--ff-only`.
- Removes the PR worktree.
- Deletes the local branch with `-d`, or `-D` when `--squash` is supplied.
- Deletes the remote branch without using `--force`.

## Hard guardrails

- Do not create PR work directly in the main worktree.
- Do not skip `run-checks.sh`; if it fails, report the failing step and do not present the PR as ready.
- Do not silently accept a repository where no commands are detected.
- Do not run cleanup for an open, closed, draft, or otherwise unmerged PR.
- Do not use `--force` in cleanup.
