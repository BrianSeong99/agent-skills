# orchestrate

Multi-backend task dispatcher for Claude Code with cross-model peer review built in. For substantive code or planning work, one model builds and a *different* one reviews — every time. The cross-review pattern is the point.

## Why

If you already use Claude and Codex side-by-side because each catches what the other misses, this skill automates the handoff. The host Claude session classifies the task, picks a builder by signal (Codex for refactor/migration/multi-file work, Opus for novel features and design-shaped logic), dispatches, then sends the build to the *other* model for review. You get a build + a verdict + a one-line recommendation in one invocation.

For trivial mechanical edits and one-shot text transforms, the skill stays single-pass — review overhead would exceed the catch rate.

## What's wired up (V1.5)

| Category | Phase 1 (build) | Phase 2 (review) | When |
|---|---|---|---|
| `quick-lookup` | Ollama (local model) | none | one-shot text transforms |
| `prose` | Sonnet | none | polished human-readable text |
| `code-quick` | Codex spark | none | trivial mechanical edits ≤30 LoC |
| `code-build` | **auto-pick: Opus or Codex** | the other | substantive code work — default for real coding |
| `planning` | Opus | Codex | design, architecture, PRDs, multi-step plans |
| `code-review-only` | n/a | cross-model | review an artifact you already have |
| `judge` | n/a | cross-model | explicit second-opinion request |
| fallback | Sonnet | none | unclassifiable |

**Auto-pick rules for `code-build`:**
- Refactor / migration / port / multi-file consistency / mass edits → **Codex builds**, Opus reviews.
- Novel feature / algorithm / design-shaped / single-file high-novelty → **Opus builds**, Codex reviews.
- Borderline → Opus builds, Codex reviews (default toward reasoning).
- "use codex to build" / "use opus to build" — user override always wins.

**Cross-model rule (load-bearing):** builder ≠ reviewer, ever. Same-model self-review is documented to be misleading (position bias, verbosity bias, self-preference bias). If only one of Codex/Opus is reachable and the route needs cross-review, the skill falls back to single-pass with a clear "review unavailable" note rather than fake-reviewing with the same model.

## Usage

Explicit:
```
/orchestrate "implement a sliding-window rate limiter for our Express API, per-tenant, no new deps"
```

Auto-trigger phrases the skill responds to: "use the right model for…", "have codex review", "second pair of eyes", "build this and have <other> check it", "use codex for this", "run on ollama", "use opus to plan".

User opt-outs:
- `"just build, no review"` → single-pass.
- `"review what I have"` → no Phase 1, paste the artifact.
- `"use codex to build"` / `"use opus to build"` → flip the auto-pick.

## Output shape

Single-pass categories return a one-line attribution + the result:
```
via codex (gpt-5.5-codex-spark): <output>
```

Build+review categories return three sections:
```
## Build (via opus)
<code or plan, including the Decisions block>

## Review (via codex)
Verdict: APPROVE-WITH-NOTES
1. [note] Edge case: empty tenant ID falls through to the global cap silently.
2. [nit] `lruCache` import is unused.
What would change my verdict to APPROVE: handle empty tenant ID explicitly (reject or fall to anon bucket).

## Recommendation
Ship; address notes when convenient.
```

The recommendation line is mechanical:
- `APPROVE` → "Ship as-is."
- `APPROVE-WITH-NOTES` → "Ship; address notes when convenient."
- Any `[blocker]` → "Address blockers before shipping."

## Cost honesty

Build+review doubles the per-dispatch cost on substantive code work (two LLM calls instead of one). If your manual workflow is "Claude builds, Codex reviews" anyway, this is the cost you're already paying — just automated and consistent. For trivial edits, the skill stays single-pass; you're not paying for a review where it doesn't earn its keep.

The 5-minute total wall-clock cap protects against a slow reviewer. If Phase 2 is still running at the cap, the skill returns what it has with a partial-result note.

## Install

From the repo root:
```bash
./install.sh orchestrate
```

Or manually:
```bash
ln -sfn "$(pwd)/skills/orchestrate" ~/.claude/skills/orchestrate
```

Then reload Claude Code.

## Prerequisites

Required:
- `bash`, `curl`, `jq`
- Claude Code (the dispatcher)

For full cross-review on `code-build` and `planning`:
- [Codex CLI plugin](https://github.com/openai/codex) — install via `/plugins` → `codex@openai-codex`. Without it, those categories fall back to Opus single-pass with a "review unavailable" note.
- `node` (>=18) — Codex CLI dependency.

Optional:
- [Ollama](https://ollama.com) with at least one instruction-tuned model pulled (e.g. `ollama pull gemma3:4b`). Without it, `quick-lookup` falls back to Sonnet.

## Configuration

All via environment variables; no config file.

| Var | Default | Effect |
|---|---|---|
| `OLLAMA_URL` | `http://localhost:11434` | Ollama daemon URL |
| `OLLAMA_MODEL` | `gemma3:4b` | Local model for `quick-lookup` |
| `OLLAMA_TIMEOUT_S` | `30` | Per-dispatch budget |
| `CODEX_PLUGIN_ROOT` | autodiscovered | Override Codex path if relocated |
| `ORCHESTRATE_DISABLED_BACKENDS` | empty | Comma list to opt out: `codex`, `ollama`, or both |

## Files

```
skills/orchestrate/
├── SKILL.md            # protocol Claude reads
├── routing.md          # category → backend, auto-pick rules
├── README.md           # this file
├── preflight.sh        # backend auth + liveness, cached 5min
├── scripts/
│   ├── dispatch-ollama.sh
│   └── log-run.sh
└── prompts/
    ├── quick-lookup.md
    ├── prose.md
    ├── code-edit.md       # code-quick + code-build (with Decisions block)
    ├── planning.md        # build + cross-review note
    ├── code-review.md     # for code-review-only
    └── cross-review.md    # the reviewer brief shape (Phase 2)
```

State at `~/.claude/orchestrate/`:
- `preflight.json` — last preflight result, 5min TTL.
- `runs.jsonl` — append-only dispatch log; entries now include `phase: "build"|"review"` and the reviewer's `verdict` field, which V2 will use for bandit routing.

## Roadmap

V2:
- **Auto-fix loop (capped)** — if the reviewer flags blockers, automatically re-dispatch to the builder with the review attached, max one fix attempt, then stop.
- **Hook-based stuck-loop detection** via `PostToolUse`.
- **Cost / wall-clock budget caps** beyond the current 5-min hard cap (per-task $-budget).

V3:
- **Bandit routing** (Thompson sampling) over `(category, builder, reviewer) → verdict-rate` from the richer `runs.jsonl`.
- **Auto-rewriting prompt templates** from accumulated failure traces.
- **Session resume index** over the JSONL transcript layer Claude Code already maintains.

See [`docs/design-orchestrate.md`](../../docs/design-orchestrate.md) for the architectural rationale.

## License

[MIT](../../LICENSE).
