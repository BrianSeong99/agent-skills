---
name: orchestrate
description: Dispatch a task to the right backend AND have a different model peer-review the result. For substantive code or planning work, runs a build phase (Opus or Codex, auto-picked by signal) followed by a cross-model review phase (the other one) — never the same model on both sides. For trivial code edits, single-pass on Codex spark. For one-shot text transforms, single-pass on local Ollama. Also supports parallel fan-out across N independent milestones (`--fanout`), capped auto-fix on blocker review (`--auto-fix`), and a $/task budget cap (`ORCHESTRATE_BUDGET_USD`). Use when the user asks to dispatch/route/orchestrate a task, mentions saving tokens or using a cheaper/local/specialized model, names a backend explicitly ("use codex", "run on opus", "ollama for this"), asks for a peer review / second-pair-of-eyes / cross-check, or wants to spawn N codex runs in parallel ("fan out M4.32 M4.33 M4.34"). Also runs as `/orchestrate "<task>"`.
---

# orchestrate — multi-backend dispatcher with cross-model peer review

You (the host Claude session) are the orchestrator. For substantive code/plan work, your job is **build + review**: classify the task, auto-pick the builder, dispatch to the builder, dispatch to a *different* reviewer model, synthesize a 3-section response, log both runs, return. For quick-lookups and tiny code edits, you do a single-pass dispatch with no review. For multi-milestone work the user has already chunked, you fan out in parallel and review each run independently.

The cross-review pattern is the point of this skill. The literature on LLM-as-judge biases is brutal: same-model self-review is actively misleading. **Builder ≠ reviewer, no exceptions.**

> **Version: V2.0.** V2 adds parallel fan-out (`--fanout`), capped auto-fix (`--auto-fix`), hook-installed stuck-loop detection, and a $/task budget cap. The V1.5 single-pass and build+review paths are unchanged — V2 is purely additive.

## Protocol — follow in order

### 0. Preflight (gate every invocation)

```bash
bash ~/.claude/skills/orchestrate/preflight.sh
```

Reads/caches `~/.claude/orchestrate/preflight.json` (5min TTL). Inspect `.codex.ok` and `.ollama.ok`.

- If a backend you'd route to is `ok:false`: surface `.msg` to the user (it has the fix command verbatim) and either (a) reroute to a working tier, or (b) abort if the user pinned that backend.
- **Cross-review specifically requires both Codex and a Claude tier to be reachable.** If Codex is down and the route is `code-build` or `planning`, fall back to a single Claude pass with a note in the attribution. Do not silently skip the review — tell the user.
- Claude tiers (Opus / Sonnet) are always available; no preflight needed for them.

### 0a. Budget gate (V2)

If `ORCHESTRATE_BUDGET_USD` is set, run before each dispatch:

```bash
bash ~/.claude/skills/orchestrate/scripts/budget-check.sh <task_hash> --estimate <usd>
```

Where `<task_hash>` is `printf '%s' "$task" | shasum -a 256 | cut -c1-8` and `<usd>` is your rough cost estimate for the dispatch you're about to make. Exit 0 = under cap, dispatch. Exit 1 = over cap, abort with the user-facing message: "Budget cap hit for this task. Spent $<spent>/<cap>. Re-run with `ORCHESTRATE_BUDGET_USD=<higher>` to continue."

Estimation is rough — don't pretend it's accounting. Better to abort an in-progress thrash early than to runaway. When the env var is unset, this gate is a no-op.

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
| `code-fanout` (V2) | N codex runs in parallel | one Opus review **per** completed run |
| fallback | Sonnet | none |

**Auto-pick rules for `code-build`** (full detail in routing.md):
- Refactor / migration / port-from-X-to-Y / multi-file restructure / codebase-wide change → **Codex builds**, Opus reviews. Codex is stronger at edit volume + repo navigation.
- Novel feature / algorithm / design-driven implementation / architectural code / "implement from this spec" → **Opus builds**, Codex reviews. Opus is stronger at reasoning-shaped code.
- Borderline → Opus builds, Codex reviews (default toward reasoning).
- **User override always wins.** "use codex to build" / "use opus to build" / "build with codex" → honor it; reviewer becomes the other.

**Fan-out trigger (V2):** if the user invokes `/orchestrate --fanout <id1> <id2> …` or says phrases like "fan out M4.32 M4.33 M4.34", "spawn N codex runs in parallel for these tasks", classify as `code-fanout` and jump to step 2d.

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

#### 2d. Fan-out builder (`code-fanout`, V2)

Read `~/.claude/skills/orchestrate/prompts/fanout.md` for the per-milestone prompt shape. The user supplies N (id, prompt-file) pairs; if the user gives inline briefs, write each to `/tmp/orchestrate_fanout_<id>.md` first.

For each `(id, prompt_file)`:

```bash
bash ~/.claude/skills/orchestrate/scripts/fanout-spawn.sh <id> <prompt-file>
```

The spawner enforces a concurrency cap (`ORCHESTRATE_FANOUT_CAP`, default 4). If the cap is reached, queue remaining ids and re-spawn after others finish.

Log a build entry per spawn (with `fanout_id` and a rough `cost_usd_estimate`):

```bash
bash ~/.claude/skills/orchestrate/scripts/log-run.sh '{"category":"code-fanout","backend":"codex","model":"gpt-5.3-codex","phase":"build","ok":true,"task_hash":"<8h>","fanout_id":"<id>","cost_usd_estimate":<f>}'
```

Then poll status:

```bash
bash ~/.claude/skills/orchestrate/scripts/fanout-check.sh
```

For each entry whose `computed_status` becomes `stuck`, surface to the user:
"Fan-out run `<id>` hasn't produced log output for >5min (log: /tmp/codex_<id>.log, pid: <pid>). It might be hung. Check it."

For each entry whose `computed_status` becomes `exited` or `completed`:
1. Dispatch a single Opus review pass over the diff (read the codex log + branch diff).
2. Log a review entry with `phase: "review"`, `fanout_id: <id>`, and `verdict`.
3. Run `fanout-reap.sh <id>` to record PR linkage.

Cross-model rule: every codex build in a fan-out cohort gets exactly one Opus review pass. No same-model reviews; no cross-cohort reviews.

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

**Hard guardrail:** if Phase 1 wall-clock + Phase 2 wall-clock would exceed **5 minutes total**, return what you have at the budget cap with a partial-result note. Do not let the review run unbounded. (Fan-out runs each carry their own 5min review budget; the cohort as a whole is not capped at 5min.)

### 3a. Auto-fix loop (V2, capped at one attempt)

When the review verdict is `BLOCKERS` AND either the user passed `--auto-fix` or `ORCHESTRATE_AUTO_FIX=1`, run **exactly one** fix attempt:

1. Re-dispatch to the **same builder** (Codex if Codex built, Opus if Opus built) with the original task **plus** the reviewer's full output (verdict + issue list + "what would change my verdict" line) attached. The fix prompt is:

   ```
   <original task>

   A reviewer flagged blockers in the previous attempt:

   <reviewer output verbatim>

   Address every [blocker]. Address [note]s if cheap. Skip [nit]s.
   Return the new deliverable + an updated Decisions: block noting what changed.
   ```

2. Run a **fresh** cross-model review pass over the fix attempt. (Same cross-model rule: builder ≠ reviewer.)

3. Surface the final verdict and stop. Hard cap = ONE fix attempt. Even if the second review is still BLOCKERS, do not retry.

Log the auto-fix attempt with `phase: "build-fix"` and the second review with `phase: "review-fix"` so runs.jsonl preserves the loop's lineage.

When the user has not opted into auto-fix, V1.5 behavior is unchanged: surface blockers and stop.

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

For `code-fanout`:

```
## Cohort summary
<id1>: <verdict>  (<recommendation>, PR #<n>: <state>)
<id2>: <verdict>  ...

## Stuck / blocked runs (if any)
<id>: log /tmp/codex_<id>.log mtime <age>m ago — investigate.

## Per-run details (collapsed; expand on request)
[one Build/Review/Recommendation block per id]
```

Recommendation rules (mechanical, no second-guessing):
- Verdict `APPROVE` → "Ship as-is."
- Verdict `APPROVE-WITH-NOTES`, all issues `[note]` or `[nit]` → "Ship; address notes when convenient."
- Any `[blocker]` → "Address blockers before shipping." (Or "Auto-fix attempted; <verdict-after-fix>." if `--auto-fix` ran.)

### 5. Log the runs

Log Phase 1 (and Phase 2 if it ran) separately:

```bash
bash ~/.claude/skills/orchestrate/scripts/log-run.sh '{"category":"<cat>","backend":"<be>","model":"<m>","walltime_s":<f>,"ok":<bool>,"task_hash":"<8h>","phase":"build"}'
bash ~/.claude/skills/orchestrate/scripts/log-run.sh '{"category":"<cat>","backend":"<be>","model":"<m>","walltime_s":<f>,"ok":<bool>,"task_hash":"<8h>","phase":"review","verdict":"<APPROVE|APPROVE-WITH-NOTES|BLOCKERS>"}'
```

`task_hash` is the same across both phases of one invocation: `printf '%s' "$task" | shasum -a 256 | cut -c1-8`. Wall-time is per-phase.

**V2 schema additions (all optional, backward-compatible):**
- `cost_usd_estimate` (number) — rough per-dispatch cost. Used by `budget-check.sh`.
- `stuck_flagged` (bool) — true if `fanout-check.sh` flagged this run as stuck.
- `fanout_id` (string) — milestone id for `code-fanout` entries.
- `phase` may also be `"build-fix"` or `"review-fix"` for `--auto-fix` retries.

Existing entries without these fields still parse correctly; consumers must default-coalesce.

## Hard guardrails

- **Builder ≠ reviewer, ever.** Codex builds → Opus reviews. Opus builds → Codex reviews. Sonnet generated → Opus reviews (or Codex). No same-model self-review even if the user asks. (V2 auto-fix preserves this: the fix attempt re-uses the original builder, then a fresh cross-model review runs over the fix.)
- **One build + one review per invocation, except `--auto-fix` which adds one capped fix.** No unbounded refine loops, ever.
- **5-minute total wall-clock cap per single-pass invocation.** Fan-out runs are per-milestone; the cohort is not 5min-capped (would defeat the purpose). The user is informed of long-running cohort entries via stuck-detection.
- **No host-Claude shortcuts.** If the route says cross-review, you run cross-review even if you "could just answer it." This skill exists to break that habit.
- **Auth-failure surfacing.** Copy preflight `.msg` verbatim to the user. Don't paraphrase.
- **No Haiku.** Deliberately omitted from the routing table.
- **Honor user opt-outs:**
  - "just build, no review" → single dispatch (Phase 1 only).
  - "review only what I have" → no Phase 1; dispatch to the cross-model reviewer with the user's pasted artifact.
  - "use codex to build" / "use opus to build" → flip the auto-pick.
  - `ORCHESTRATE_DISABLED_BACKENDS` env var → respect it; preflight already handles this.
- **No automatic re-dispatch unless `--auto-fix`.** If Phase 2 says BLOCKERS and auto-fix is off, return; don't re-dispatch to Phase 1 with the review attached.
- **Stuck runs are surfaced, not killed.** `fanout-check.sh` flags via log mtime, the skill tells the user, the user decides.

## V2 features — quick reference

### Parallel fan-out (`--fanout`)
- Trigger: `/orchestrate --fanout <id1> <id2> …` or "fan out X Y Z", "spawn N codex runs in parallel".
- Cap: `ORCHESTRATE_FANOUT_CAP` (default 4) concurrent runs.
- State: `~/.claude/orchestrate/fanout-state.json`.
- Stuck detection: log mtime older than `ORCHESTRATE_STUCK_AFTER_S` (default 300s) flags as stuck — surfaced to user, not auto-killed.
- Per run: codex builds, Opus reviews. Cross-model rule per run, not per cohort.
- Scripts: `scripts/fanout-spawn.sh`, `scripts/fanout-check.sh`, `scripts/fanout-reap.sh`.
- Prompt shape: `prompts/fanout.md`.

### Capped auto-fix (`--auto-fix` or `ORCHESTRATE_AUTO_FIX=1`)
- One fix attempt only. Even if second review is BLOCKERS, stop.
- Same builder reruns with reviewer output attached; fresh cross-model review runs over the fix.
- Run-log entries use `phase: "build-fix"` / `phase: "review-fix"`.

### Hook-based stuck-loop detection
- **Lives in `~/.claude/settings.json`, not SKILL.md** (per anthropics/claude-code#19225 — Stop/PostToolUse hooks declared inside SKILL.md don't fire).
- Install: `bash ~/.claude/skills/orchestrate/scripts/install-hook.sh` (idempotent; `--dry-run` to preview).
- Uninstall: `bash ~/.claude/skills/orchestrate/scripts/uninstall-hook.sh`.
- Mechanism: `PostToolUse` hook fingerprints `(tool, args, result_hash)` over the last 3 calls. 3 identical → write warning to `~/.claude/orchestrate/stuck.log` and surface via `additionalContext` so Claude sees it.

### $/task budget cap (`ORCHESTRATE_BUDGET_USD`)
- Set the env var to enable. Unset = no cap.
- Pre-dispatch: `bash scripts/budget-check.sh <task_hash> --estimate <usd>`. Exit 1 = aborts dispatch.
- Reads `runs.jsonl`'s `cost_usd_estimate` per `task_hash`. Rough heuristic; not accounting.

## Out of scope (V3 — do not do these now)

- **Bandit / Thompson-sampling routing:** read `runs.jsonl` (now even richer with `verdict`, `cost_usd_estimate`, and `fanout_id`) to learn which builder wins per task class.
- **Auto-rewriting prompt templates** from accumulated failure traces.
- **Session resume index** over the JSONL transcript layer Claude Code already maintains.
- **Multi-round debate / iterative refine beyond one auto-fix attempt.** The 2025 literature on debate loops is sobering; one extra pass on blockers captures the value, more rounds stabilize on coherent-but-wrong outputs.

`runs.jsonl` keeps growing; V3 reads it.
