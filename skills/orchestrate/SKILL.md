---
name: orchestrate
description: Route a task to the most cost-appropriate AI backend (Claude Opus/Sonnet via subagent, OpenAI Codex CLI, or a local Ollama model) instead of running everything on the current model. Use when the user asks to dispatch/route/orchestrate a task, mentions saving tokens or using a cheaper/local/specialized model, names a backend explicitly ("use codex", "run on ollama", "do this on opus"), or describes a task whose obvious best home is not the current host model — e.g. quick local-only string transforms (Ollama), narrow code edits (Codex), open-ended planning (Opus). Also runs as `/orchestrate "<task>"`.
---

# orchestrate — multi-backend task dispatcher

You (the host Claude session) are the orchestrator. Your job: classify the user's task, dispatch it to the right backend, log the run, and return the result with a one-line attribution. Do **not** do the task yourself unless the route lands on a Claude tier — then you spawn a subagent at that tier.

## Protocol — follow in order

### 0. Preflight (gate every invocation)

Run preflight to discover available backends:

```bash
bash ~/.claude/skills/orchestrate/preflight.sh
```

The script writes/caches `~/.claude/orchestrate/preflight.json` (5min TTL) and prints the JSON. Read `.codex.ok` and `.ollama.ok`.

- **If a backend the route needs is `ok:false`**, surface the failure to the user with the fix command (from `.msg`) and either (a) reroute to a working tier, or (b) abort if the user explicitly asked for that backend. Do not silently retry.
- **Graceful degradation:** if Codex or Ollama isn't installed at all, the skill still works — every route just falls through to Claude tiers. Don't refuse to operate.
- Claude tiers (Opus / Sonnet via the Agent tool) are always available; no preflight needed for them.

### 1. Classify

Read `~/.claude/skills/orchestrate/routing.md`. Pick exactly **one** category for the task. Map category → backend:

| Category | Backend | Model |
|---|---|---|
| `quick-lookup` | Ollama (local) | configured local model (default `gemma3:4b`; override via `OLLAMA_MODEL`) |
| `code-edit-narrow` | Codex via `codex:codex-rescue` | spark (`--model gpt-5.3-codex-spark --write`) |
| `code-edit-broad` | Codex via `codex:codex-rescue` | default (`--write`, no `--model`) |
| `code-review` | Sonnet subagent | n/a |
| `planning` | Opus subagent | n/a |
| `prose` | Sonnet subagent | n/a |
| `judge` (only when user explicitly asks for a second opinion) | Sonnet **or** Opus, MUST differ from generator | n/a |
| fallback | Sonnet subagent | n/a |

Be smart, not stingy: borderline-but-recoverable → cheaper tier; high-stakes/irreversible → skip the cheap tier and go straight to Opus or Codex-default.

### 2. Dispatch

Use **exactly one** of the four dispatch paths below. Do not combine them in V1; no auto-critique loop.

#### 2a. Ollama (`quick-lookup`)

```bash
bash ~/.claude/skills/orchestrate/scripts/dispatch-ollama.sh "<the prompt you want the local model to answer>"
```

Read the prompt-template guidance at `~/.claude/skills/orchestrate/prompts/quick-lookup.md` for shape. The script returns the model's response on stdout, or exits non-zero on daemon failure / timeout (30s default budget). On failure, fall back to Sonnet and note the fallback in your attribution line.

#### 2b. Codex (`code-edit-narrow`, `code-edit-broad`)

Spawn the existing Codex subagent via the `Agent` tool — do **not** call `codex-companion.mjs` directly. Pass the user's task as the prompt; include the model flag only for `code-edit-narrow`:

- For narrow edits: prepend `--model gpt-5.3-codex-spark` to the prompt content (the codex subagent parses it).
- Default to write-capable (`--write` is the codex-rescue default).

```
Agent(subagent_type: "codex:codex-rescue", prompt: "<task text, optionally prefixed with --model gpt-5.3-codex-spark>")
```

Read `~/.claude/skills/orchestrate/prompts/code-edit.md` for prompt-shape guidance.

#### 2c. Claude Sonnet (`code-review`, `prose`, `judge`-vs-Opus, fallback)

Spawn a Sonnet subagent via the `Agent` tool with explicit model override:

```
Agent(subagent_type: "general-purpose", model: "sonnet", description: "<2-4 word desc>", prompt: "<full self-contained task brief>")
```

Read the relevant prompts/*.md (`code-review.md` or `prose.md`) for shape. The subagent prompt must be self-contained — it doesn't see this conversation.

#### 2d. Claude Opus (`planning`, `judge`-vs-Sonnet)

Same as Sonnet but `model: "opus"`:

```
Agent(subagent_type: "general-purpose", model: "opus", description: "<2-4 word desc>", prompt: "<full self-contained task brief>")
```

Read `prompts/planning.md` for shape.

### 3. Log the run

Right after the dispatch returns (success or fail), log it:

```bash
bash ~/.claude/skills/orchestrate/scripts/log-run.sh '{"category":"<cat>","backend":"<ollama|codex|sonnet|opus>","model":"<model-id-or-null>","walltime_s":<float>,"ok":<true|false>,"task_hash":"<short hash>"}'
```

Compute `task_hash` as the first 8 hex chars of `sha256(user_task_text)` (use `printf '%s' "$task" | shasum -a 256 | cut -c1-8`).
Estimate `walltime_s` from your own clock (note time before dispatch, after).
Set `ok` based on whether the backend returned a usable result.

### 4. Return to user

Hand the user the backend's output verbatim, prefixed with one short attribution line:

> `via <backend> (<model-id-or-tier>): `

Example: `via codex (gpt-5.3-codex-spark): <output>`. Do not add post-hoc commentary unless the user asks.

## Hard guardrails

- **One dispatch per `/orchestrate` invocation.** No automatic critique/re-run loops in V1. If the result is unusable, surface that and let the user decide whether to re-route.
- **No silent retries.** If a backend errors, log `ok:false`, tell the user, suggest the fallback. Don't loop.
- **No host-Claude shortcuts.** If the route says Codex, you call Codex even if you "could just answer it." This skill exists to avoid that habit.
- **Cross-model rule for `judge`**: never use the same tier for generation and judgment. Codex generated → Sonnet/Opus judges. Opus generated → Sonnet judges. Sonnet generated → Opus judges. Ollama generated → Sonnet judges.
- **Auth-failure surfacing**: if preflight reports a backend down, copy the `.msg` field directly into your reply so the user gets the fix command verbatim.
- **No Haiku.** Deliberately omitted from the V1 routing table — the gap between Sonnet and a small local model is small enough that Haiku doesn't earn a slot.
- **Honor user opt-out.** If `ORCHESTRATE_DISABLED_BACKENDS` env var lists a backend (comma-separated, e.g. `codex` or `ollama,codex`), preflight already marks them `ok:false` with `msg:"disabled by user"` — treat them as unavailable and route accordingly.

## Out of scope (deferred to V2/V3 — do not do these now)

- Auto evaluator-optimizer loops.
- Bandit / Thompson-sampling routing from `runs.jsonl`.
- Auto-rewriting prompt templates from accumulated failures.
- Stuck-loop detection via hooks.
- Session resume index.

`runs.jsonl` is being populated for those future phases. V1 only writes; nothing reads.
