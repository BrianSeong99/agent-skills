# Prompt shape — code-edit (`code-quick`, `code-build`)

Two modes, different shapes. The host Claude picks based on category.

## `code-quick` mode (single-pass, Codex spark)

For trivial mechanical edits where review overhead exceeds the catch rate. Single-file, ≤30 LoC change, edit pattern is obvious from the request.

State the change in plain English; name files/symbols Codex should touch. Codex reads the repo on its own — don't paste code.

```
--model gpt-5.3-codex-spark
Rename the variable `tmp` to `scratch` in src/utils/parse.ts. Update every reference inside that file. Don't touch other files.
```

No `Decisions:` block needed — single-pass means no reviewer.

## `code-build` mode (cross-review)

For substantive code work — implement a feature, refactor, port, multi-file change, anything that earns a reviewer. The builder is auto-picked (Codex for edit-volume tasks, Opus for reasoning-shaped tasks); SKILL.md handles the pick.

The build prompt MUST request a `Decisions:` block so the reviewer has visibility into non-obvious choices. Without it, the reviewer is judging blind on intent.

### Codex as builder (refactor / port / multi-file)

No `--model` flag — let Codex pick its strongest coder. Default `--write`. Append the Decisions-block requirement:

```
Extract the auth middleware in apps/web/middleware.ts into a new package at packages/auth/. Update import sites across the workspace. Preserve the public function signatures. Keep existing tests passing.

After making the changes, append a `Decisions:` block listing non-obvious choices you made (one bullet each, ≤1 line, ≤8 bullets total).
```

Codex returns: changes applied + Decisions block in stdout.

### Opus as builder (novel feature / algorithm / design-shaped)

```
Implement a custom in-process rate limiter for our Node.js service. Use a sliding window algorithm with per-tenant counters. Tenants are identified by an `X-Tenant-Id` header. Default limit: 100 req/min/tenant. Override via env var per tenant.

Constraints:
- No new dependencies (we already use `lru-cache`).
- Must not block the event loop on the hot path.
- Express middleware shape — `app.use(rateLimiter(opts))`.

Return:
1. The new file `src/middleware/rate-limiter.ts` with the implementation.
2. The integration diff in `src/app.ts`.
3. A `Decisions:` block — non-obvious choices (≤8 bullets, one line each).
```

Opus returns: code + integration + Decisions block.

### What goes in the Decisions block

Decisions the reviewer can't infer from the code alone:
- Library/API choice when alternatives exist ("used `setImmediate` instead of `process.nextTick` because…").
- Trade-offs the task surfaced ("favored simplicity over the per-request alloc; can revisit if perf flags").
- Inferred constraints ("assumed tenant IDs are short strings — added a 64-byte cap as defense-in-depth").
- Skipped optional features the task implied but didn't require ("not implementing dynamic per-tenant overrides via API; only env var").

What does NOT belong in Decisions:
- Restating the task ("I implemented a rate limiter as requested" — useless).
- Style nits ("I used const everywhere" — visible in code).
- Hedging ("could be improved by…" — not a decision, that's a future TODO).

## Read-only mode (rare; `code-review-only` category)

If the user wants Codex to read without editing — deep code understanding, walk-through, etc. — prepend `--read`:

```
--read
Walk through how request authentication flows from the API gateway to the database in this monorepo. Name the files and functions involved, in order.
```

This is the same flag Phase 2 uses when Codex is the reviewer. Codex won't write anything.

## Anti-patterns

- Pasting full file contents inline when Codex can read the repo — wasted tokens.
- Skipping the Decisions block in `code-build` mode — the reviewer is then judging blind, and the cross-review loses half its value.
- Mixing multiple unrelated tasks in one prompt — split into separate dispatches.
- Asking Codex for design opinions ("should I…") in `code-build` — that's `planning`, route to Opus instead.
