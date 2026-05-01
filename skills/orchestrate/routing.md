# Routing table

Single source of truth for category → backend mapping in V1. SKILL.md mirrors this; if they drift, this file wins.

## Categories and signals

### `quick-lookup` → Ollama (configured local model)
**Signals:** regex / format conversion / single-fact extraction / case-conversion / lint-style fix / draft-quality commit message / short text transform. Output ≤ ~200 tokens. Doesn't need the wider context, doesn't need the internet, doesn't need to read files. Latency-sensitive ("quick", "real fast", "draft").
**Anti-signals:** anything that needs to read a repo, anything where correctness is load-bearing for production, anything multi-step.
**Model:** whatever's set in `OLLAMA_MODEL` (default `gemma3:4b`). Pick a small, fast, instruction-tuned local model.

### `code-edit-narrow` → Codex `gpt-5.3-codex-spark`
**Signals:** single-file edit, single-function change, mechanical rename, add-an-import, fix-a-typo-in-code, add-a-test-for-this-one-function. Context ≤ ~300 lines. Edit pattern is obvious from the request.
**Anti-signals:** "refactor", "across the codebase", multi-file, design questions, "should I…".

### `code-edit-broad` → Codex (default model, write-capable)
**Signals:** refactor across files, extract-into-package, implement-this-feature, port-this-from-X-to-Y, big migration. Codex is the strongest at reading and editing code in repo context.
**Anti-signals:** the task is mostly *thinking* (architecture), not *editing* — that goes to `planning` instead.

### `code-review` → Sonnet subagent
**Signals:** "what does this do", "is this right", "find bugs in", "review this PR", "is there a smell here". Read-mostly. Sonnet's nuance > Codex's literalism for judgment.
**Anti-signals:** the user wants edits applied — that's a `code-edit-*` category.

### `planning` → Opus subagent
**Signals:** "design", "architect", "PRD", "spec out", "what's the right approach", "break this into phases", "trade-offs", multi-step plans, ambiguous problems.
**Anti-signals:** "just write the code" — that's `code-edit-*`. "Summarize this doc" — that's `prose`.

### `prose` → Sonnet subagent
**Signals:** README sections, doc rewrites, blog draft, polished commit message (not draft-quality), tweet, copywriting. Output is human-readable text, quality matters.
**Anti-signals:** quick draft / one-shot transform → `quick-lookup`. Strategic positioning doc → `planning`.

### `judge` → cross-tier subagent (NEVER same model as generator)
**Signals:** user explicitly asks for a second opinion / review / critique of an existing artifact (output, code, doc). The generator's identity is known.
**Cross-model rule:**
- Generator was Opus → judge with Sonnet
- Generator was Sonnet → judge with Opus
- Generator was Codex → judge with Sonnet (or Opus if the user wants it harsh)
- Generator was Ollama → judge with Sonnet

The same model judging itself biases toward verbose/familiar/positional outputs (well-documented in the LLM-as-judge literature: position bias, verbosity bias, self-preference bias). Do not break this rule.

### fallback → Sonnet subagent
**When:** unclassifiable, user's request doesn't match any category cleanly, or primary backend errored AND the user didn't pin a backend.
**Why Sonnet:** safe middle. Cheaper than Opus, more capable than a small local model, doesn't pretend to be a coding specialist like Codex.

## Decision algorithm

1. If user named a backend explicitly ("use codex", "on opus", "ollama for this"), honor it. Skip classification.
2. If user named a model that doesn't exist in the V1 table (e.g. "haiku"), say so and propose the closest alternative. Don't silently substitute.
3. Otherwise, walk categories top-to-bottom; pick the first whose signals match. Ties → choose the cheaper backend.
4. If still unclassified, route to `fallback` (Sonnet).
5. **Stakes override:** if the task is irreversible (writes to main, sends a message, modifies prod config), upgrade one tier. Codex-spark → Codex-default. Sonnet → Opus. Never downgrade.
6. **Availability override:** if the chosen backend's `preflight.ok` is `false`, fall through: Ollama → Sonnet, Codex-spark → Codex-default → Sonnet, Codex-default → Sonnet. Tell the user about the fallback.

## What is NOT in the V1 table

- **Haiku.** Deliberately omitted; not a tier.
- **Multi-model ensembles.** No automatic critique-after-generate in V1.
- **Codex review modes** (`review`, `adversarial-review`). Only `task` is used; consistent with the codex plugin's own contract.
- **Multiple Ollama models simultaneously.** One configured model per session via `OLLAMA_MODEL`. Want to compare two? Run `/orchestrate` twice with different env vars.
