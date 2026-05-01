# orchestrate

Multi-backend task dispatcher for Claude Code. Routes a task to the most cost-appropriate engine — Claude Opus/Sonnet via subagent, OpenAI Codex CLI, or a local Ollama model — instead of running everything on the current host model.

## Why

When you're in a Claude Opus session, every quick lookup ("convert this list to camelCase") burns Opus tokens. Codex is genuinely better at reading and editing repo code than a Claude session with shell tools. A small local model is genuinely fast enough for one-shot text transforms, with no API cost.

The host Claude session classifies the task, dispatches to the right backend, logs the run, and returns the result with a one-line attribution. Future versions will read the run log to learn routing preferences over time.

## What's wired up (V1)

| Category | Backend | Notes |
|---|---|---|
| `quick-lookup` | Ollama (local) | Regex, format conversion, single-fact extraction. Configured via `OLLAMA_MODEL`. |
| `code-edit-narrow` | Codex CLI (`gpt-5.3-codex-spark`) | Single-file mechanical edits. |
| `code-edit-broad` | Codex CLI (default model) | Multi-file refactors, feature implementation. |
| `code-review` | Sonnet subagent | Read-mostly judgment. |
| `prose` | Sonnet subagent | Polished human-readable text. |
| `planning` | Opus subagent | Architecture, design, multi-step plans. |
| `judge` | Cross-tier subagent (different model than generator) | Second-opinion review. |

No Haiku. The gap between Sonnet and a small local model is small enough that Haiku doesn't earn a slot.

## Usage

Explicit:
```
/orchestrate "convert these snake_case names to camelCase: foo_bar, baz_qux"
```

The skill also auto-triggers on phrases like "use the right model for…", "save Opus tokens on…", "use codex for this", "run on ollama". See [`SKILL.md`](./SKILL.md) for the full description.

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

Optional (skill degrades gracefully when missing):
- [Codex CLI plugin](https://github.com/openai/codex) — install via `/plugins` → `codex@openai-codex`. Without it, `code-edit-*` falls back to Sonnet.
- [Ollama](https://ollama.com) with at least one instruction-tuned model pulled. Without it, `quick-lookup` falls back to Sonnet.

## Configuration

All configuration via environment variables (no config file).

| Var | Default | Effect |
|---|---|---|
| `OLLAMA_URL` | `http://localhost:11434` | Ollama daemon URL |
| `OLLAMA_MODEL` | `gemma3:4b` | Local model for `quick-lookup` |
| `OLLAMA_TIMEOUT_S` | `30` | Per-dispatch budget |
| `CODEX_PLUGIN_ROOT` | autodiscovered | Override Codex path if you've relocated the plugin |
| `ORCHESTRATE_DISABLED_BACKENDS` | empty | Comma list to opt out: `codex`, `ollama`, or both |

## Files

```
skills/orchestrate/
├── SKILL.md           # what Claude reads — routing protocol
├── routing.md         # category → backend table (referenced by SKILL.md)
├── README.md          # this file
├── preflight.sh       # auth + liveness check, cached 5min
├── scripts/
│   ├── dispatch-ollama.sh
│   └── log-run.sh
└── prompts/
    ├── quick-lookup.md
    ├── code-edit.md
    ├── code-review.md
    ├── planning.md
    └── prose.md
```

State (per-machine, never committed) lives at `~/.claude/orchestrate/`:
- `preflight.json` — last preflight result, 5min TTL
- `runs.jsonl` — append-only dispatch log

## Roadmap

V2:
- Cross-model evaluator-optimizer loop (max 3 iterations, hard cost cap)
- Hook-based stuck-loop detection
- Wall-clock + $/task budget caps

V3:
- Bandit (Thompson sampling) over `(category, backend, prompt-variant) → success`
- Auto-rewriting prompt templates from accumulated failure traces
- Session resume index

See [`docs/design-orchestrate.md`](../../docs/design-orchestrate.md) for the architectural rationale.

## License

[MIT](../../LICENSE).
