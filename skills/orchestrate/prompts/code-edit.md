# Prompt shape — code-edit (Codex via codex:codex-rescue)

Codex is an editing-first agent with repo access. The codex-rescue subagent forwards your prompt to `codex-companion.mjs task` once and returns stdout. Write the prompt accordingly.

## Shape

State the change in plain English, naming files/symbols Codex should touch. Codex reads the repo on its own — you don't need to paste code.

- **Imperative** ("rename X to Y in foo.ts").
- **Locate by name**, not line number (renames break line refs).
- **Acceptance criteria** if non-obvious ("preserve public API", "tests still pass", "update the call sites").
- **Scope** ("only in src/auth/", "across the workspace").
- **Effort hint** if you have one. Default: leave `--effort` unset; only set it when the user asks.

## Narrow (`code-edit-narrow` → spark model)

Prepend `--model gpt-5.3-codex-spark` to the prompt content so the codex-rescue subagent picks it up:

```
--model gpt-5.3-codex-spark
Rename the variable `tmp` to `scratch` in src/utils/parse.ts. Update every reference inside that file. Don't touch other files.
```

## Broad (`code-edit-broad` → default model)

No `--model` flag — let Codex pick its strongest coder.

```
Extract the auth middleware in apps/web/middleware.ts into a new package at packages/auth/. Update import sites across the workspace. Preserve the public function signatures. Keep existing tests passing.
```

## Read-only (rare in V1 — code-review category prefers Sonnet)

If the user genuinely wants Codex to read without editing (deep code understanding), prepend `--read` to override the default `--write`:

```
--read
Walk through how request authentication flows from the API gateway to the database in this monorepo. Name the files and functions involved, in order.
```

## Anti-patterns

- Pasting full file contents inline — Codex reads the repo, that's wasted tokens.
- Asking Codex for design opinions ("should I…") — that's `planning`, route to Opus instead.
- Multiple unrelated tasks in one prompt — split into separate dispatches.
