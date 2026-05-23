---
name: worktree-pr-flow
description: Full git-worktree-based PR ritual. Creates a worktree off `origin/main` on a fresh feature branch, autodetects and runs install/typecheck/test/build, pushes, opens a PR with a HEREDOC body, and on merge cleans up the worktree + branch (local and remote). Use when the user asks to "make a PR for X", "ship X as a PR", "open a PR for X off main", "feature branch for X", "worktree this", "start a PR", "finish/close out the PR", or invokes `/worktree-pr-flow <topic>`, `/start-pr <topic>`, `/finish-pr <topic>`. Configurable per-repo via env vars (WORKTREE_PR_BASE / PREFIX / DIR / INSTALL / TYPECHECK / TEST / BUILD). Repo-agnostic — no hardcoded paths or project names.
---

# worktree-pr-flow — git-worktree PR ritual, codified

You (the host Claude session) drive a two-phase ritual: **start-pr** (create the worktree, run checks, push, open the PR) and **finish-pr** (after the user merges on GitHub, clean up local + remote branch and the worktree). The user invokes either phase explicitly, or you infer the phase from the conversation.

The skill exists because the user runs this exact 12-line shell sequence ~90 times a week. Codifying it cuts the boilerplate; the autodetect handles cross-repo variance (pnpm vs npm vs bun vs cargo); the env-var overrides handle the cases autodetect can't.

## Protocol — follow in order

### 0. Preflight

Verify you're being invoked inside a git repo:

```bash
git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "not inside a git repo"; exit 1; }
```

If not, surface that and stop. Don't try to `cd` somewhere — let the user position you.

Check that `gh` is on PATH (only needed for the PR-open step). If missing and the user is in start-phase, surface install instructions and continue without the PR-open step (push still works).

### 1. Decide the phase

Phase signals — pick exactly one:

| User said | Phase |
|---|---|
| "make a PR for X" / "ship X as a PR" / "start a PR for X" / "worktree this" / `/start-pr X` / `/worktree-pr-flow X` | `start` |
| "the PR merged, clean up" / "finish the PR" / `/finish-pr X` / "remove that worktree" / "delete brian/X locally" | `finish` |
| Ambiguous | Ask: "Are we starting a new PR or finishing one already on GitHub?" — one question, then proceed. |

The two phases share the env-var configuration but otherwise don't depend on each other. The user can do `start` in this session and `finish` weeks later in a different session.

### 2. Resolve config (both phases)

Read these env vars; for each unset one, fall back to the autodetect or hardcoded default. Surface the resolved values to the user only if they're non-default — don't spam them with the boring case.

| Var | Default |
|---|---|
| `WORKTREE_PR_BASE` | `origin/main` |
| `WORKTREE_PR_PREFIX` | `${USER}/` (e.g. `brian/`) |
| `WORKTREE_PR_DIR` | `worktrees/` (relative to repo root) |
| `WORKTREE_PR_INSTALL` | autodetect (see `scripts/run-checks.sh`) |
| `WORKTREE_PR_TYPECHECK` | autodetect |
| `WORKTREE_PR_TEST` | autodetect |
| `WORKTREE_PR_BUILD` | autodetect |

Autodetect signals (in `scripts/run-checks.sh`):

| Lockfile / manifest | Install | Typecheck | Test | Build |
|---|---|---|---|---|
| `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` | `pnpm typecheck` if `package.json` has it, else `pnpm exec tsc --noEmit` if `tsconfig.json` exists | `pnpm test` if defined | `pnpm build` if defined |
| `package-lock.json` | `npm ci` | same logic, `npm run typecheck` / `npx tsc --noEmit` | `npm test` if defined | `npm run build` if defined |
| `bun.lockb` or `bun.lock` | `bun install --frozen-lockfile` | `bun run typecheck` if defined, else `bunx tsc --noEmit` if `tsconfig.json` | `bun test` | `bun run build` if defined |
| `Cargo.toml` | `cargo fetch` | `cargo check --all-targets` | `cargo test` | `cargo build` |
| (none of the above) | (skip) | (skip) | (skip) | (skip) |

If autodetect can't decide a step, leave it empty and report `no <step> command detected; pass WORKTREE_PR_<STEP>=... or skip` to the user. **Fail closed** — don't guess.

### 3. Phase: start

Required input: a `<topic>` slug (kebab-case, lowercase, ≤40 chars). If the user gave a sentence ("make a PR for adding X to Y"), extract a slug. Confirm the slug back to the user before proceeding *only if* it required nontrivial extraction; otherwise just use it.

Run:

```bash
bash ~/.claude/skills/worktree-pr-flow/scripts/start-pr.sh <topic>
```

That script:
1. `git fetch origin` (so the base ref is fresh).
2. `git worktree add <WORKTREE_PR_DIR>/<topic> -b <WORKTREE_PR_PREFIX><topic> <WORKTREE_PR_BASE>`
3. Echoes the absolute path the user should `cd` into.

After the worktree is created, surface the path and the next-step menu to the user:

```
Worktree ready at <abs-path>.
Next:
  1. cd <abs-path>
  2. Make your changes.
  3. When ready, ask me to run checks (or run: bash ~/.claude/skills/worktree-pr-flow/scripts/run-checks.sh).
  4. Then ask me to open the PR.
```

**Do not run checks automatically after creating the worktree** — the user hasn't made changes yet. The check-run is a separate ask.

When the user later asks to "run checks" / "verify" / "lint and test it":

```bash
cd <worktree-path>
bash ~/.claude/skills/worktree-pr-flow/scripts/run-checks.sh
```

Stream the output. If it exits non-zero, surface which step failed (the script prints `[install]`, `[typecheck]`, `[test]`, `[build]` headers) and stop. **Don't auto-retry, don't auto-fix.** Hand control back.

When the user later asks to "push and open the PR" / "ship it":

1. `git -C <worktree> push -u origin <WORKTREE_PR_PREFIX><topic>`
2. Build the PR body from `templates/pr-body.md`. You fill in the slots:
   - `{{summary}}` — 1-3 bullets describing the change.
   - `{{test_plan}}` — Markdown checklist of TODOs to verify (the user runs these after merge or in CI).
3. Open the PR via:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<filled-in body>
EOF
)"
```

Title shape: conventional-commit style, `<type>(<scope>): <subject>`, ≤70 chars. Subject derived from the topic and the changes.

**Hard rule (from global CLAUDE.md):** never include `Co-Authored-By: Claude`, "Generated with Claude Code", or any AI-attribution in the title or body. Never. The template intentionally omits it.

### 4. Phase: finish

Required input: a `<topic>` slug. If unset, infer from the current branch (`git symbolic-ref --short HEAD` and strip the prefix), and confirm.

Run:

```bash
bash ~/.claude/skills/worktree-pr-flow/scripts/finish-pr.sh <topic> [--squash]
```

That script:
1. Verifies the PR is `MERGED` on the remote via `gh pr view <prefix><topic> --json state -q .state`.
   - If not merged, refuses with the actual state and a hint (e.g. "PR is OPEN — merge it on GitHub first, or pass --force to skip the check, or close it and run with --abandoned").
2. Switches the main worktree to `main` (`git checkout main`) and `git pull --ff-only origin main`.
3. `git worktree remove <WORKTREE_PR_DIR>/<topic>` (with `--force` only if the user passed `--force`).
4. `git branch -d <prefix><topic>` (use `-D` only if the user passed `--squash`, since squash-merges leave a non-fast-forward branch).
5. `git push origin --delete <prefix><topic>` (idempotent — silently succeeds if the remote already deleted it via "delete branch on merge" setting).

Surface the cleanup transcript to the user. If any step fails, stop and report — don't try to auto-recover.

### 5. Edge cases & opt-outs

- **User wants to skip checks entirely:** honor it. They can push from the worktree without going through `run-checks.sh`. The skill is a convenience, not a gate.
- **User wants a different base:** they pass `WORKTREE_PR_BASE=origin/release-1.x` or similar. Use it.
- **Repo's default branch is `master`:** per the global rule, this should already have been renamed to `main`. If the user is in a still-`master` repo, surface the four-command rename from `~/.claude/CLAUDE.md` and stop. Don't silently work around it.
- **Stacked PRs:** the user has a global rule against them. If the user is currently inside a worktree on a `<prefix>X` branch and asks to start a new PR for Y "branched off this", **push back**: explain the auto-close risk and propose two parallel branches off `main` instead. Only proceed if the user overrides explicitly.
- **Worktree path collision:** if `<WORKTREE_PR_DIR>/<topic>` already exists, the script surfaces the conflict and stops. Don't auto-suffix.
- **Multiple PRs in flight:** fine. Each is its own worktree under `<WORKTREE_PR_DIR>/`. The skill doesn't care.

## Hard guardrails

- **No AI attribution in titles, bodies, or commits.** Hard rule from the global CLAUDE.md. Suppress unconditionally.
- **No stacked PRs.** Each branch is cut from `<WORKTREE_PR_BASE>` (default `origin/main`). Push back if the user asks to chain.
- **Branched-off-main means *fresh*.** `git fetch origin` runs before every worktree-add. Stale base = wasted PR.
- **Fail closed on autodetect.** If install/typecheck/test/build can't be detected, report it. Don't run a wrong command.
- **No auto-retry on check failure.** Surface the failing step and stop. The user fixes it; the user re-runs.
- **No auto-merge.** This skill never merges. Even after `finish-pr` confirms merged-state, that's a verification, not an action — the user merged manually on GitHub.
- **No clobbering.** `git worktree remove` without `--force` if the worktree is dirty; `git branch -d` not `-D` unless the merge was a squash.
- **`gh` is the source of truth for merged-state.** Don't infer from local state — the user might have merged from a different machine.

## Out of scope (V2 — do not do these now)

- **Auto-rebase against a moved base** (`git pull --rebase origin main` mid-flight). V1 just creates fresh and pushes; if the base moved, the user re-runs.
- **Conflict-resolution helpers** (re-running checks after rebase, surfacing conflict files). V1 surfaces the failure and hands off.
- **PR template selection by repo** (`.github/PULL_REQUEST_TEMPLATE.md`). V1 always uses the skill's own template; if a repo has a local template, the user pastes it manually for now.
- **CI-status polling** (`gh pr checks --watch`). V1 opens the PR and stops; the user watches CI themselves.
- **Branch-name auto-extraction from commit messages.** V1 takes the slug from the user.
