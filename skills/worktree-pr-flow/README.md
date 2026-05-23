# worktree-pr-flow

Codifies the full git-worktree-based PR ritual: create worktree off `origin/main`, run install/typecheck/test/build, push, open PR, on-merge cleanup. One skill, two phases (`start` and `finish`), every Brian-specific bit pushed out to env vars.

## Why

The shape of every feature PR is the same 12-line shell sequence:

```bash
git fetch origin
git worktree add ../worktrees/<topic> -b brian/<topic> origin/main
cd ../worktrees/<topic>
# ...edit...
pnpm install && pnpm typecheck && pnpm test && pnpm build
git push -u origin brian/<topic>
gh pr create --title "..." --body "$(cat <<'EOF'
...
EOF
)"
# ...later, after merge...
git worktree remove ../worktrees/<topic>
git branch -d brian/<topic>
git push origin --delete brian/<topic>
```

90+ PRs/week of this in a single org's worth of work means ~1,000 lines of verbatim shell typed per week. This skill collapses it to `/start-pr <topic>` → `/finish-pr <topic>`, autodetecting the install/typecheck/test/build commands per language so it works on a pnpm Next.js repo, a `cargo` Rust repo, or this very repo (bash + jq, no test harness — autodetect reports "no test command detected" and skips gracefully).

## Usage

Auto-trigger phrases:
- "make a PR for X" / "ship X as a PR" / "open a PR for X off main" / "feature branch for X" / "worktree this"
- "the PR merged, clean up" / "finish the PR" / "remove that worktree"

Explicit:
```
/worktree-pr-flow <topic>     # full ritual, starts in start-phase
/start-pr <topic>              # phase 1 only
/finish-pr <topic>             # phase 2 only
```

`<topic>` is a kebab-case slug. The branch will be `<WORKTREE_PR_PREFIX><topic>` (default: `<USER>/<topic>`, e.g. `brian/<topic>`).

## Two phases

### Phase 1: start

```bash
bash ~/.claude/skills/worktree-pr-flow/scripts/start-pr.sh <topic>
```

1. `git fetch origin`
2. `git worktree add <DIR>/<topic> -b <PREFIX><topic> <BASE>`
3. Echoes the absolute path you should `cd` into.

You then make your changes inside that worktree. When ready, ask the host Claude session to "run checks" — that runs:

```bash
bash ~/.claude/skills/worktree-pr-flow/scripts/run-checks.sh
```

Which streams `[install]`, `[typecheck]`, `[test]`, `[build]` step-by-step and exits non-zero on first failure.

When checks pass, ask Claude to "push and open the PR". The host:
1. `git push -u origin <PREFIX><topic>`
2. Fills in `templates/pr-body.md` with summary + test-plan checklist.
3. `gh pr create --title "<conventional-commit title>" --body "$(cat <<'EOF' ... EOF)"`.

The body never includes AI-attribution trailers or "Generated with Claude Code" — global rule.

### Phase 2: finish

After you merge the PR on GitHub:

```bash
bash ~/.claude/skills/worktree-pr-flow/scripts/finish-pr.sh <topic> [--squash]
```

1. Verifies the PR is `MERGED` on the remote via `gh pr view --json state`. Refuses if not.
2. `git checkout main && git pull --ff-only origin main` in the main worktree.
3. `git worktree remove <DIR>/<topic>`.
4. `git branch -d <PREFIX><topic>` (use `-D` if `--squash` — squash-merges leave a non-fast-forward branch).
5. `git push origin --delete <PREFIX><topic>` (idempotent).

If GitHub auto-deleted the remote branch via the "automatically delete head branches" repo setting, step 5 silently succeeds.

## Install

```bash
./install.sh worktree-pr-flow
```

Or manually:
```bash
ln -sfn "$(pwd)/skills/worktree-pr-flow" ~/.claude/skills/worktree-pr-flow
```

Then reload Claude Code.

## Prerequisites

Required:
- `git` (≥2.5 for `worktree`).
- `bash`.
- Claude Code (the dispatcher).

For `gh pr create`:
- [`gh`](https://cli.github.com/) authenticated against the repo's host (run `gh auth status` to verify).

The skill works without `gh` — it'll push the branch but skip the `gh pr create` step and tell you to open the PR manually.

## Configuration

All via environment variables; no config file.

| Var | Default | Effect |
|---|---|---|
| `WORKTREE_PR_BASE` | `origin/main` | Base ref the worktree branches from. |
| `WORKTREE_PR_PREFIX` | `${USER}/` (e.g. `brian/`) | Branch-name prefix. Set to empty string for no prefix. |
| `WORKTREE_PR_DIR` | `worktrees/` (relative to repo root) | Where worktree dirs live. |
| `WORKTREE_PR_INSTALL` | autodetect | Install command. |
| `WORKTREE_PR_TYPECHECK` | autodetect | Typecheck command. |
| `WORKTREE_PR_TEST` | autodetect | Test command. |
| `WORKTREE_PR_BUILD` | autodetect | Build command. |

Autodetect is conservative — see `SKILL.md` for the lockfile-to-command table. If autodetect can't decide, the run-checks step **fails closed** and tells you to set the env var or skip the step. It will not guess.

### Per-repo config

For a repo where the autodetect won't get the right commands (e.g., a monorepo where you only want to test one package), set the env vars in the shell session before invoking the skill:

```bash
export WORKTREE_PR_TEST="pnpm --filter @scope/pkg test"
export WORKTREE_PR_BUILD="pnpm --filter @scope/pkg build"
```

Or, for the personal repo, ship a thin adapter skill (e.g. `omega-pr-flow`) that sets these via a wrapper script.

## Files

```
skills/worktree-pr-flow/
├── SKILL.md              # protocol Claude follows
├── README.md             # this file
├── scripts/
│   ├── start-pr.sh       # phase-1: fetch + worktree-add + branch
│   ├── run-checks.sh     # autodetect + run install/typecheck/test/build
│   └── finish-pr.sh      # phase-2: verify merged + cleanup local + remote
└── templates/
    └── pr-body.md        # PR body skeleton (Summary + Test plan)
```

No state directory; this skill is stateless. The worktrees themselves live in the consuming repo.

## Hard rules

- **No AI attribution.** Per global CLAUDE.md, no `Co-Authored-By: Claude`, no "Generated with Claude Code", no AI mentions in PR titles, bodies, or commits. The template intentionally omits these and the SKILL.md tells the host Claude to never add them.
- **Branched off `<WORKTREE_PR_BASE>` (default `origin/main`)**, not from another feature branch. No stacked PRs — they auto-close when the parent merges, GitHub refuses to reopen them. Two branches off `main` instead.
- **Repo's default must be `main`.** If you're in a still-`master` repo, the global rule says rename it first (`git branch -m master main && git push -u origin main && gh repo edit --default-branch main && git push origin --delete master`). The skill won't silently work around `master`.
- **`gh` is the source of truth for merged-state.** Phase 2 verifies via `gh pr view --json state` — never inferred from local state.

## Roadmap

V2:
- **Auto-rebase against a moved base** when checks pass but the base moved during the build window.
- **Repo-local PR template detection** — if `.github/PULL_REQUEST_TEMPLATE.md` exists, prefer it over the skill's template.
- **CI-status polling** — after `gh pr create`, optionally watch `gh pr checks` and report when green.
- **Conflict-aware finish** — detect and surface unmerged files post-rebase, instead of just failing the worktree-remove.

V3:
- **Project-aware adapters** that ship as separate skills (`omega-pr-flow`, `miden-pr-flow`) — the personal repo's domain.
- **Bandit selection** of which test/build subset to run based on which files changed (monorepo-aware).

## License

[MIT](../../LICENSE).
