---
name: orchestrate
description: Dispatch a task to the right backend AND have a different model peer-review the result. For substantive code or planning work, runs a build phase (Opus or Codex, auto-picked by signal) followed by a cross-model review phase (the other one) — never the same model on both sides. For trivial code edits, single-pass on Codex spark. For one-shot text transforms, single-pass on local Ollama. Use when the user asks to dispatch/route/orchestrate a task, mentions saving tokens or using a cheaper/local/specialized model, names a backend explicitly ("use codex", "run on opus", "ollama for this"), or asks for a peer review / second-pair-of-eyes / cross-check on existing work. Also runs as `/orchestrate "<task>"`.
---

# orchestrate — multi-backend dispatcher with cross-model peer review

You (the host Claude session) are the orchestrator. For substantive code/plan work, your job is **build + review**: classify the task, auto-pick the builder, dispatch to the builder, dispatch to a *different* reviewer model, synthesize a 3-section response, log both runs, return. For quick-lookups and tiny code edits, you do a single-pass dispatch with no review.

The cross-review pattern is the point of this skill. The literature on LLM-as-judge biases is brutal: same-model self-review is actively misleading. **Builder ≠ reviewer, no exceptions.**

## Protocol — follow in order

### 0. Preflight (gate every invocation)

```bash
bash ~/.claude/skills/orchestrate/preflight.sh
```

Reads/caches `~/.claude/orchestrate/preflight.json` (5min TTL). Inspect `.codex.ok` and `.ollama.ok`.

- If a backend you'd route to is `ok:false`: surface `.msg` to the user (it has the fix command verbatim) and either (a) reroute to a working tier, or (b) abort if the user pinned that backend.
- **Cross-review specifically requires both Codex and a Claude tier to be reachable.** If Codex is down and the route is `code-build` or `planning`, fall back to a single Claude pass with a note in the attribution. Do not silently skip the review — tell the user.
- Claude tiers (Opus / Sonnet) are always available; no preflight needed for them.

### 1. Classify

Read `~/.claude/skills/orchestrate/routing.md`. Pick exactly one category:

| Category | Phase 1 (build) | Phase 2 (review) |
|---|---|---|
| `quick-lookup` | Ollama (local model) | none |
| `prose` | Sonnet | none |
| `code-quick` | Codex spark (`--model gpt-5.3-codex-spark --write`) | none |
| `code-build` | **auto-pick: Opus OR Codex** by signal (see routing.md) | the other one |
| `planning` | **Opus** | Codex |
| `code-review-only` | n/a (artifact already exists) | cross-model from generator |
| `judge` (explicit second-opinion request) | n/a | cross-model |
| fallback | Sonnet | none |

**Auto-pick rules for `code-build`** (full detail in routing.md):
- Refactor / migration / port-from-X-to-Y / multi-file restructure / codebase-wide change → **Codex builds**, Opus reviews. Codex is stronger at edit volume + repo navigation.
- Novel feature / algorithm / design-driven implementation / architectural code / "implement from this spec" → **Opus builds**, Codex reviews. Opus is stronger at reasoning-shaped code.
- Borderline → Opus builds, Codex reviews (default toward reasoning).
- **User override always wins.** "use codex to build" / "use opus to build" / "build with codex" → honor it; reviewer becomes the other.

### 2. Phase 1 — Build

Dispatch to the builder. The builder must include a `Decisions:` block in its output so the reviewer has visibility into non-obvious choices.

#### 2a. Codex builder (`code-quick`, `code-build` when Codex is picked)

Spawn the existing Codex subagent via the `Agent` tool — never call `codex-companion.mjs` directly:

```
Agent(subagent_type: "codex:codex-rescue", prompt: "<task text, optionally prefixed with --model gpt-5.3-codex-spark for code-quick>")
```

For `code-build` (with review): **append** this to the task text so Codex returns the Decisions block:

```
After making the changes, append a `Decisions:` block listing non-obvious choices you made (one bullet each, ≤1 line). Keep it under 8 bullets.
```

For `code-quick` (no review): no Decisions block needed — single pass.

Read `~/.claude/skills/orchestrate/prompts/code-edit.md` for prompt-shape guidance.

#### 2b. Opus builder (`code-build` when Opus is picked, `planning`)

Spawn a general-purpose subagent at Opus tier:

```
Agent(subagent_type: "general-purpose", model: "opus", description: "<2-4 word desc>", prompt: "<full self-contained task brief>")
```

The task brief MUST request a `Decisions:` block:

```
<the user's task, restated>

Return:
1. The deliverable (code with file paths / plan / spec).
2. A short `Decisions:` block — non-obvious choices you made (≤8 bullets, one line each).
```

Read `prompts/code-edit.md` (build mode) or `prompts/planning.md` for shape.

#### 2c. Ollama (`quick-lookup`) and Sonnet (`prose`, fallback)

Single-pass, no review. Same as before:

```bash
bash ~/.claude/skills/orchestrate/scripts/dispatch-ollama.sh "<prompt>"
```
or
```
Agent(subagent_type: "general-purpose", model: "sonnet", description: "<desc>", prompt: "<brief>")
```

Skip to step 4.

### 3. Phase 2 — Cross-model review

Read `~/.claude/skills/orchestrate/prompts/cross-review.md` for the reviewer brief shape. Then dispatch to the **other** model:

- If Codex built → review with **Opus** subagent (`general-purpose`, `model: "opus"`).
- If Opus built → review with **Codex** subagent (`codex:codex-rescue`, prepend `--read` so it doesn't try to edit).

The reviewer prompt must be self-contained — it sees neither the conversation nor the user. Construct it as:

```
You are reviewing another model's work. Be specific, terse, and skeptical. Do not rewrite — flag.

ORIGINAL TASK:
<verbatim user request>

BUILDER (<builder model name>):
<full builder output, including the Decisions block>

WHAT TO RETURN:
1. Verdict line — one of: APPROVE | APPROVE-WITH-NOTES | BLOCKERS
2. Numbered issue list. Tag each [blocker] / [note] / [nit].
3. One closing sentence: "What would change my verdict to APPROVE: <specific change>." (Skip if verdict is already APPROVE.)

WHAT TO FLAG:
- Correctness errors (logic bugs, off-by-one, wrong API usage).
- Missed requirements from the original task.
- Edge cases the build doesn't handle.
- Security issues (auth, input validation, injection, secrets).
- Decisions in the Decisions block that look wrong given the task constraints.

WHAT TO IGNORE:
- Style preferences not stated in the task.
- Naming taste.
- Performance optimizations not asked for.
- Suggestions to "consider" alternatives that don't address a real issue.
```

**Hard guardrail:** if Phase 1 wall-clock + Phase 2 wall-clock would exceed **5 minutes total**, return what you have at the budget cap with a partial-result note. Do not let the review run unbounded.

### 4. Synthesize and return

For single-pass categories (`quick-lookup`, `prose`, `code-quick`, `fallback`):

```
via <backend> (<model>): <output>
```

For build+review categories (`code-build`, `planning`, `code-review-only`, `judge`):

```
## Build (via <builder> / <model>)
<builder output, including the Decisions block>

## Review (via <reviewer> / <model>)
<reviewer verdict line + numbered issues>

## Recommendation
<one line, derived from reviewer's verdict tags>
```

Recommendation rules (mechanical, no second-guessing):
- Verdict `APPROVE` → "Ship as-is."
- Verdict `APPROVE-WITH-NOTES`, all issues `[note]` or `[nit]` → "Ship; address notes when convenient."
- Any `[blocker]` → "Address blockers before shipping."

### 5. Log the runs

Log Phase 1 (and Phase 2 if it ran) separately:

```bash
bash ~/.claude/skills/orchestrate/scripts/log-run.sh '{"category":"<cat>","backend":"<be>","model":"<m>","walltime_s":<f>,"ok":<bool>,"task_hash":"<8h>","phase":"build"}'
bash ~/.claude/skills/orchestrate/scripts/log-run.sh '{"category":"<cat>","backend":"<be>","model":"<m>","walltime_s":<f>,"ok":<bool>,"task_hash":"<8h>","phase":"review","verdict":"<APPROVE|APPROVE-WITH-NOTES|BLOCKERS>"}'
```

`task_hash` is the same across both phases of one invocation: `printf '%s' "$task" | shasum -a 256 | cut -c1-8`. Wall-time is per-phase. The `verdict` field on the review entry is what V2 will use for bandit routing.

## Hard guardrails

- **Builder ≠ reviewer, ever.** Codex builds → Opus reviews. Opus builds → Codex reviews. Sonnet generated → Opus reviews (or Codex). No same-model self-review even if the user asks.
- **One build + one review per invocation.** No auto-fix loop in V1.5. If the reviewer flags blockers, surface them and stop. The user decides whether to re-dispatch with the review attached, escalate, or ship anyway.
- **5-minute total wall-clock cap.** If reviewer hasn't returned by then, surface a partial-result note and what we have.
- **No host-Claude shortcuts.** If the route says cross-review, you run cross-review even if you "could just answer it." This skill exists to break that habit.
- **Auth-failure surfacing.** Copy preflight `.msg` verbatim to the user. Don't paraphrase.
- **No Haiku.** Deliberately omitted from the routing table.
- **Honor user opt-outs:**
  - "just build, no review" → single dispatch (Phase 1 only).
  - "review only what I have" → no Phase 1; dispatch to the cross-model reviewer with the user's pasted artifact.
  - "use codex to build" / "use opus to build" → flip the auto-pick.
  - `ORCHESTRATE_DISABLED_BACKENDS` env var → respect it; preflight already handles this.
- **No automatic re-dispatch.** If Phase 2 says BLOCKERS, return; don't re-dispatch to Phase 1 with the review attached unless the user explicitly asks ("apply the review", "fix the blockers and re-review").

## Out of scope (V2/V3 — do not do these now)

- **Auto-fix loop:** if reviewer flags blockers, automatically re-dispatch to builder with the review attached, capped at one fix attempt.
- **Bandit / Thompson-sampling routing:** read `runs.jsonl` (now richer with `phase` + `verdict`) to learn which builder wins per task class.
- **Auto-rewriting prompt templates** from accumulated failure traces.
- **Stuck-loop detection** via `PostToolUse` hooks.
- **Session resume index** over the JSONL transcript layer Claude Code already maintains.

`runs.jsonl` is being populated for these phases. V1.5 only writes; nothing reads.
