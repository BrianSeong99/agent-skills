# Design notes — `orchestrate`

Architectural rationale for the orchestrate skill. Why the routing table looks the way it does, why certain things were deliberately left out, and what comes next.

## The pattern: orchestrator-worker

This skill implements Anthropic's [orchestrator-worker pattern](https://www.anthropic.com/research/building-effective-agents): a central LLM (the host Claude session) classifies the task, delegates it to a worker (a subagent or external CLI), and synthesizes the result.

What makes it useful here, specifically:
- **Host session is usually Claude Opus.** Every task that doesn't need Opus burns Opus tokens unnecessarily.
- **Codex is genuinely better at code editing.** It reads the repo natively, maintains a working set across files, and writes patches — things a Claude session with `Read`/`Edit` tools approximates but doesn't excel at.
- **Local models are genuinely fast for one-shots.** A 4B-param model on Apple Silicon answers a `convert these to camelCase` request in <1s with no API cost.

The skill is essentially a routing policy. It doesn't add capability — it picks the best capability per task.

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

## Why no automatic critique loop in V1

Multi-agent debate and self-refine loops are appealing on paper, but the empirical 2025 finding is sobering: a single model with more compute often beats a multi-agent debate at the same total budget. Critique loops earn their cost only when:
- The task has clear external success criteria (so the evaluator isn't just hallucinating preferences).
- The generator's first attempt has measurable room to improve (often it doesn't).
- The cost ceiling is enforced, otherwise the loop runs forever on coherent-but-wrong outputs.

V2 will add the loop with explicit guardrails: cross-model judge, max 3 iterations, hard cost cap. Until then, the user can manually invoke `judge` as a separate dispatch.

## Why file-based state

`~/.claude/orchestrate/runs.jsonl` is append-only JSON Lines. No database, no daemon, no service.

Reasons:
- **Skills are stateless on every invocation.** Persistent state must live on disk.
- **JSONL is the right primitive for streaming append.** Concurrent invocations don't corrupt the file (under POSIX, line-sized writes to an append-mode fd are atomic).
- **No new dependency.** `jq` is already required for parsing preflight results.
- **Easy to inspect.** `jq -r .backend runs.jsonl | sort | uniq -c` is the tool.
- **Easy to migrate.** When V3 introduces a bandit, it reads the same JSONL and computes its priors. No schema migration.

The downside: querying gets expensive at scale. At ~1KB per line, a year of heavy use is ~10MB — easily handled by the `jq | sort` pattern. If a skill's run log ever exceeds 100MB, that's the signal to introduce SQLite, not before.

## What V1 deliberately doesn't do

- **No automatic prompt-template tuning.** The five `prompts/*.md` files are hand-written and static in V1. V3 will spawn an Opus "meta" subagent that reads accumulated failures and proposes new template versions — but only after the run log has enough signal to ground the rewrite.
- **No bandit routing.** Thompson sampling over `(category, backend, prompt-variant)` arms needs ~50 trials per arm to outperform random — premature in V1. The infrastructure (run log) is built; the bandit isn't.
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
