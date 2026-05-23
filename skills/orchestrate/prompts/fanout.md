# Prompt shape — `code-fanout` (parallel cohort)

A fan-out is N independent codex runs spawned in parallel, each working on its
own milestone. The orchestrate skill caps concurrency, watches for stuck runs
via log mtime, and reaps each entry against its PR. The shape of each
per-milestone prompt is what this file documents.

The cross-model rule still applies — but **per run**, not collectively. Each
codex build, when it finishes, gets a single Opus review pass. Reviews are
NOT shared across the cohort.

## When to fan out (vs. a single `code-build`)

Use the `code-fanout` route when **all** are true:

- The work is naturally split into ≥3 independent milestones, each self-contained.
- The user has already broken the work into milestone-numbered briefs (M4.32, M4.33, …).
- Each milestone is realistic for one codex `--full-auto` run end-to-end (~5–30 min).
- You don't want to babysit them serially.

If the work is one big task pretending to be many small ones, that's a regular
`code-build`. Fan-out doesn't hide complexity.

## Per-milestone prompt — required shape

Each prompt file passed to `fanout-spawn.sh <id> <prompt-file>` should be a
complete, self-contained brief. Codex starts from `--full-auto` with no
conversation context — what you put in the file is all it sees.

Recommended structure:

```
# <id> — <one-line title>

## Context
<2–4 sentences: where this milestone sits in the larger plan, what the user
will validate against, what's intentionally out of scope.>

## Repo invariants
- working directory: <absolute path>
- branch: <branch name, cut from main>
- do NOT touch: <files / dirs to stay clear of>
- existing patterns to mirror: <file paths the codex agent should match>

## Acceptance
- [ ] <concrete, testable acceptance criterion 1>
- [ ] <criterion 2>
- [ ] tests pass: <command>
- [ ] no diff outside the listed scope

## Deliverable
1. The patch (codex applies edits in place via --full-auto).
2. A short Decisions: block (≤8 bullets, one line each) listing non-obvious
   choices made. The Opus reviewer will read this; clarity here costs the
   reviewer less time.
3. A PR opened against main with title `<id>: <title>`.
```

The Decisions block is **mandatory** for fan-out runs because the host Claude
session will not be in the room for the build — the reviewer is the only
peer-eyes on each branch.

## Cohort-level orchestration (what the host skill does)

1. Validate the cohort: every id is filename-safe, every prompt file exists,
   ids are distinct.
2. Cap concurrency at `ORCHESTRATE_FANOUT_CAP` (default 4). If the cohort is
   bigger than the cap, spawn the first N and queue the rest mentally — re-run
   `fanout-spawn.sh` for queued ids as earlier ones reap.
3. After each `fanout-spawn.sh`, log a build entry to runs.jsonl with
   `phase: "build"`, `fanout_id: <id>`, and a rough `cost_usd_estimate`.
4. Periodically run `fanout-check.sh` and surface anything with
   `computed_status` of `stuck` to the user. Do NOT auto-kill.
5. When a run's status becomes `exited` or `completed`, dispatch one Opus
   review pass over its diff (or its terminal log if the diff isn't accessible),
   log a review entry tied to the same `fanout_id`, then call `fanout-reap.sh`
   to record PR linkage.

## Stuck handling

`fanout-check.sh` flags a run as `stuck` when its codex log file's mtime is
older than `ORCHESTRATE_STUCK_AFTER_S` (default 300s = 5min) and the pid is
still alive. The skill surfaces stuck runs to the user with their log path and
last log line; the user decides whether to kill them. Reasons a run might
plateau without being broken:

- Codex is running a long test suite and producing no log output mid-test.
- Codex is waiting on a network call (rare with `--full-auto`).
- Codex genuinely hung (most common — kill it).

Letting the user make the call avoids killing legitimate long pauses.

## Anti-patterns

- **Don't fan out one prompt N times** "to see which result is best." That's
  best-of-N sampling, not fan-out — and it doesn't compose with cross-review.
  If you want best-of-N, ask the user explicitly; it's not on the V2 roadmap.
- **Don't share state between runs.** No "M4.33 builds on M4.32's output" —
  that's a stack, not a cohort. Stacks belong on a single serial branch.
- **Don't skip the Decisions block** to save tokens per run. Reviewer needs it.
- **Don't review across runs.** Each run gets its own Opus reviewer pass.
  Cross-cohort review isn't in scope; the value is independence.
