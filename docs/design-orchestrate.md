# Design notes — `orchestrate`

Architectural rationale for the orchestrate skill. Why the routing table looks the way it does, why certain things were deliberately left out, and what comes next.

## V1 → V1.5 — what changed and why

The first cut of this skill was scoped as a thin task router: classify the task, dispatch to one backend, return. That framing missed the actual value.

**What changed in V1.5:** for substantive code or planning work, the skill now runs a **build phase + cross-model review phase** as standard, not as a deferred V2 feature. The pattern users actually run by hand — "Claude builds, Codex reviews" or vice versa — is now baked in. Single-pass remains for trivial code edits and one-shot text transforms where review overhead exceeds the catch rate.

**Why this is the right framing:** picking one of three backends is a routing decision; the *value* of having three different model families on tap is that they have different blind spots. Cross-model review captures that value. Single-backend dispatch wastes it. Anthropic's own [orchestrator-worker + evaluator-optimizer combination](https://www.anthropic.com/research/building-effective-agents) describes exactly this composition.

## The pattern: orchestrator-worker + evaluator-optimizer

The skill implements two of Anthropic's effective-agent patterns composed together:

1. **Orchestrator-worker** — a central LLM (the host Claude session) classifies the task and delegates to a worker (a subagent or external CLI). This handles *which model builds*.
2. **Evaluator-optimizer** — a different model evaluates the worker's output against the task. This handles *which model reviews*.

What makes the composition useful here, specifically:
- **Host session is usually Claude Opus.** Every task that doesn't need Opus burns Opus tokens unnecessarily — but more importantly, Opus reviewing its own output is misleading (self-preference bias). Cross-model review side-steps both problems.
- **Codex and Opus have complementary strengths.** Codex is stronger at multi-file edit volume and repo navigation; Opus is stronger at reasoning-shaped novel logic. Pairing them — one builds, the other reviews — catches what each individually misses.
- **Local models are genuinely fast for one-shots.** A 4B-param model on Apple Silicon answers a `convert these to camelCase` request in <1s with no API cost. No review phase — review overhead exceeds catch rate at this size.

The skill is a routing-and-review policy. It doesn't add capability — it picks the best capability per task and pressure-tests the output with a different perspective.

## Why no Haiku

Haiku occupies an awkward middle ground:
- **Cheaper than Sonnet, slower than a local 4B model.** A round-trip through the Anthropic API has latency a local model doesn't pay.
- **Less capable than Sonnet, more capable than a local 4B model.** For tasks where Sonnet is overkill, a local model usually suffices. For tasks where Sonnet is needed, Haiku is below the bar.

The routing table is more legible without it: cheap-and-fast = Ollama, code-specialized = Codex, general-capable = Sonnet, hardest-thinking = Opus. Adding Haiku would require carving signals between Haiku and Ollama (when do I want one vs. the other?) — and the answer is almost never clean.

If a future version needs a fast cloud-side fallback when Ollama is down, Haiku is an obvious slot. V1 doesn't.

## Why cross-model judging

The LLM-as-judge literature (2024-2025) documents three biases that destroy single-model evaluation loops:
1. **Position bias** — judges favor the response shown first.
2. **Verbosity bias** — judges prefer longer, more formal responses regardless of correctness.
3. **Self-preference bias** — models score their own outputs higher because their own outputs have lower perplexity to themselves.

The fix is straightforward: never use the same tier for generation and judgment. The skill's `judge` route enforces this — Opus generated → Sonnet judges, and so on. Same-model judging is a documented trap; allowing it would silently bias every evaluation.

## Why one review pass, not a loop

V1.5 runs **exactly one** build + one review per invocation. No iterative refine-and-rescore.

Multi-agent debate and self-refine loops are appealing on paper, but the empirical 2025 finding is sobering: a single model with more compute often beats a multi-agent debate at the same total budget. Iterative critique loops earn their cost only when:
- The task has clear external success criteria (so the evaluator isn't just hallucinating preferences).
- The generator's first attempt has measurable room to improve (often it doesn't).
- The cost ceiling is enforced, otherwise the loop runs forever on coherent-but-wrong outputs.

A *single* cross-model review captures most of the gain documented in the literature — it forces the build through a different perspective once. Adding round-trips multiplies cost and latency without proportional improvement, and risks stabilizing on coherent-but-wrong outputs (the documented failure mode of self-refine loops). V2 will add an **auto-fix** loop (capped at one fix attempt) for the case where the user wants the skill to act on blockers automatically; iterative debate is intentionally not on the roadmap.

## Why file-based state

`~/.claude/orchestrate/runs.jsonl` is append-only JSON Lines. No database, no daemon, no service.

Reasons:
- **Skills are stateless on every invocation.** Persistent state must live on disk.
- **JSONL is the right primitive for streaming append.** Concurrent invocations don't corrupt the file (under POSIX, line-sized writes to an append-mode fd are atomic).
- **No new dependency.** `jq` is already required for parsing preflight results.
- **Easy to inspect.** `jq -r .backend runs.jsonl | sort | uniq -c` is the tool.
- **Easy to migrate.** When V3 introduces a bandit, it reads the same JSONL and computes its priors. No schema migration.

The downside: querying gets expensive at scale. At ~1KB per line, a year of heavy use is ~10MB — easily handled by the `jq | sort` pattern. If a skill's run log ever exceeds 100MB, that's the signal to introduce SQLite, not before.

## What V1.5 deliberately doesn't do

- **No auto-fix loop.** If the reviewer flags `[blocker]` issues, the skill surfaces them and stops. V2 will add a one-shot auto-fix (re-dispatch to builder with the review attached, capped at one attempt). For now: surface, stop, let the user decide.
- **No automatic prompt-template tuning.** The `prompts/*.md` files are hand-written and static. V3 will spawn an Opus "meta" subagent that reads accumulated failures and proposes new template versions — but only after the run log (which now includes per-phase entries with the reviewer's verdict tags) has enough signal to ground the rewrite.
- **No bandit routing.** Thompson sampling over `(category, builder, reviewer) → verdict-rate` needs ~50 trials per arm to outperform random — premature now. The infrastructure (richer per-phase run log) is built; the bandit isn't.
- **No hook-based stuck detection.** Hooks belong in `~/.claude/settings.json` and would touch global config. V2 will add a `PostToolUse` hook that fingerprints `(tool, args, result_hash)` over a rolling window and aborts on three identical calls.
- **No session resume index.** Claude Code already persists session transcripts as JSONL under `~/.claude/projects/`. The skill's job, when V3 adds resume, is to maintain a thin index over those transcripts — not to reinvent the persistence layer.

## Failure modes designed-around

- **Stuck loop:** can't happen in V1 — every `/orchestrate` invocation does exactly one dispatch and returns. V2 adds explicit guardrails for the critique loop.
- **Backend down:** preflight catches it; SKILL.md routes around the dead backend and surfaces the fix command.
- **Wrong backend chosen:** V1 has no learning, so this is the user's call. The run log records the decision so V3's bandit can correct over time.
- **Cheap model lying about confidence:** the literature flags this as the killer of cascade routing. V1 mitigates by being conservative — borderline tasks default to Sonnet, not Ollama. V2's evaluator loop adds an explicit verification gate.

## What this skill is not trying to be

- **Not a model gateway.** It doesn't proxy API calls, doesn't merge billing, doesn't load-balance providers. Each backend is invoked through its native tooling (Anthropic API for Claude tiers, Codex CLI for Codex, Ollama HTTP API for Ollama).
- **Not a workflow engine.** No DAGs, no shared state between dispatches in V1. Each `/orchestrate` is one shot.
- **Not a benchmarking harness.** The run log is for routing decisions, not capability evaluation. If you want to compare models on a task suite, use a real benchmark.

## Design provenance

The patterns this skill leans on, with sources:

- **Orchestrator-worker, evaluator-optimizer:** [Anthropic — Building Effective Agents](https://www.anthropic.com/research/building-effective-agents).
- **Cost-aware routing (cascade pattern):** [RouteLLM (UC Berkeley)](https://www.lmsys.org/blog/2024-07-01-routellm/) — 85% cost savings preserving 95% quality on MT-Bench.
- **LLM-as-judge biases:** position bias, verbosity bias, self-preference bias — multiple 2024-2025 papers (e.g. [Wang et al., "Large Language Models are not Fair Evaluators"](https://arxiv.org/abs/2305.17926)).
- **Stuck-loop fingerprinting:** standard ops pattern — fingerprint `(tool, args, result)` over a rolling window, abort on N identical calls.
- **Bandit routing:** Thompson sampling over arms; ~50 trials/arm to outperform random.

## V1.5 → V2.0 — what changed and why

V2 is **purely additive**. Every V1.5 dispatch path still works, identical shape. Four features land:

### 1. Parallel fan-out (`code-fanout`)

**Why this exists.** The session record across the last few weeks of work shows the same hand-rolled pattern over and over: 42 milestone-numbered codex runs in one Chainless week, 28 in one Miden bridge-build session. Each one was a separate `codex exec` invocation, with PID/log bookkeeping in `/tmp/m<N>-codex.log` and `/tmp/codex_pr<N>_prompt.md`. The skill now does that bookkeeping in one place.

**Design choices:**

- **Cap-N-in-flight, not unbounded.** `ORCHESTRATE_FANOUT_CAP` (default 4) keeps the cohort honest. Codex `--full-auto` is heavy on local CPU + network; running 12 in parallel just queues them at OS-level. Four is empirically the most a Mac Studio can drive without one of them starving on tool round-trips.
- **One Opus review per run, not collective.** Cross-model rule applies at the run level. Reviewing the cohort as a whole would be reduce-by-LLM, which the bias literature flags as fragile (the reduction step inherits self-preference effects when the reducer model is the same family as the dominant builder).
- **Stuck detection via log mtime, not via pid heartbeat.** Codex doesn't expose a heartbeat; pid liveness is necessary but not sufficient (a hung child still has a live pid). The actual signal is "log file hasn't grown in a while" — `stat -f %m` on `/tmp/codex_<id>.log` is the cheapest reliable proxy. Default threshold is 5min; configurable via `ORCHESTRATE_STUCK_AFTER_S`.
- **Surface, don't kill.** A long pause might be a long-running test. The skill flags stuck runs and tells the user; the user decides. Auto-kill is the wrong default — wrong-kill is worse than wrong-flag.
- **State is a JSON array, not JSONL.** Unlike `runs.jsonl` which is append-only, `fanout-state.json` is mutable per-entry (status transitions). Atomic write via `mktemp + mv` works at this size; anything bigger and we'd need SQLite, but a cohort is rarely >20 entries.

### 2. Capped auto-fix (one attempt)

**Why this exists.** Brian's 2026-04-30 explicit ask: "have codex review and adapt feedbacks until satisfactory." The "until satisfactory" framing is the dangerous part — left unbounded, this stabilizes on coherent-but-wrong outputs (the documented self-refine failure mode). V2 ships the loop **with a hard cap of one attempt**.

**Design choices:**

- **Same builder for the fix.** When Codex was the original builder, Codex retries with the Opus review attached. The reviewer's role is to flag, the builder's role is to fix; switching builders mid-loop loses the original's working set and decisions.
- **Fresh cross-model review on the fix.** Critically, the fix attempt does NOT skip review. It gets a brand-new cross-model review pass; the second-review verdict is what surfaces. Otherwise the loop becomes builder-only refinement, which is exactly the self-bias trap.
- **Hard cap at one.** Even if the second review still says BLOCKERS, the skill stops. The user decides whether to escalate, restart, or ship anyway. The empirical evidence on multi-round refine (2025) says round 2+ rarely helps and often hurts.
- **Logged distinctly.** `phase: "build-fix"` and `phase: "review-fix"` mark the retry in `runs.jsonl` so V3's bandit can learn whether auto-fix actually changed verdicts on average.

### 3. Hook-based stuck-loop detection in settings.json

**Why this lives in settings.json, not SKILL.md.** [anthropics/claude-code#19225](https://github.com/anthropics/claude-code/issues/19225) documents that Stop and PostToolUse hooks declared inside a SKILL.md don't fire — the harness only loads hooks defined in `~/.claude/settings.json` (or the project-local equivalent). We can't paper over this from inside the skill; we ship an idempotent installer instead.

**Design choices:**

- **Idempotent install.** `install-hook.sh` looks for our marker key (`_orchestrate_marker: "orchestrate-stuck-loop"`) inside any existing PostToolUse entry. Re-running is a no-op unless `--force` is passed.
- **Co-existence with other hooks.** The installer never touches non-orchestrate entries. `uninstall-hook.sh` filters by the same marker; nothing else gets touched.
- **`--dry-run` for review.** The installer prints the JSON it would write without modifying settings.json. This is how the skill teaches users what's about to land in their global config.
- **Fingerprint over a 3-call window.** The hook hashes `(tool_name, canonical(tool_input), sha256(tool_response).head)` and rolls a 3-line window in `~/.claude/orchestrate/stuck-window.jsonl`. Three identical fingerprints = warning. Three is the smallest window where "twice" doesn't trigger on legitimate retry-on-flake patterns; bigger windows (5+) miss real stuck loops because the harness has often already burned a lot of tokens.
- **Surface via `additionalContext`, don't block.** The hook returns a JSON object that Claude Code's harness reads to inject a system message into the next turn. This is non-blocking — Claude can still proceed, but it sees the warning. Outright blocking would fight cases where the user actually wants 3 identical calls (e.g., polling).

### 4. Per-task USD budget cap

**Why this exists.** Build+review doubles cost per dispatch on substantive code; `--auto-fix` doubles it again on blockers; fan-out multiplies by N. A 12-milestone fan-out with auto-fix can rack up real money without anyone watching. The 5-min wall-clock cap doesn't catch this — money runs out before time does on Opus.

**Design choices:**

- **Off by default.** `ORCHESTRATE_BUDGET_USD` unset = no cap. Existing users see no behavior change.
- **Per task_hash, not global.** The cap scopes to a single task (whatever invocation produced the hash). Cross-task accounting belongs in real billing, not in this guardrail.
- **Pre-dispatch check.** `budget-check.sh <hash> --estimate <usd>` exits 1 if the next dispatch would push spend past the cap. The skill aborts with the user-facing message "Budget cap hit for this task. Spent $X/$Y. Re-run with `ORCHESTRATE_BUDGET_USD=<higher>` to continue."
- **Rough heuristic, not accounting.** The estimate is per-dispatch, not per-token. Real costs come from the Anthropic + OpenAI billing dashboards. The cap is a "stop the runaway" guardrail; over/undershoot of ~30% is acceptable.

## V2 schema additions to `runs.jsonl`

All optional, all default-coalesced by readers:

| Field | Type | When |
|---|---|---|
| `cost_usd_estimate` | number | Per-dispatch cost estimate. Used by `budget-check.sh`. |
| `stuck_flagged` | bool | True if the dispatch was flagged stuck by `fanout-check.sh` at some point. |
| `fanout_id` | string | Milestone id for `code-fanout` entries. Ties build + review entries together. |

V1.5-shape entries (no V2 fields) still parse correctly; the new fields are pure addition. `log-run.sh` requires no changes — it already passes through whatever JSON the caller hands it.

## Why no auto-merge or post-fanout reduce step

After a fan-out cohort completes, there's a tempting next step: have Opus read all N reviews and produce a "cohort verdict" or auto-merge the green ones. We deliberately don't.

- **Auto-merge crosses a safety boundary.** Merging is irreversible-ish; the skill is read-and-review by design. PRs exist to be reviewed by humans. The skill stops at "PR opened, here's the cross-review."
- **A cohort-level reducer reintroduces single-judge bias.** The whole point of cross-review is that builder ≠ reviewer. A cohort-reducer that re-reads N (Codex build, Opus review) pairs is itself a single Opus pass — which means it has Opus's biases at the cohort level. We reject the reduction.

If the user wants a cohort-level summary, they can ask the host session for one explicitly. The skill won't impose it.
