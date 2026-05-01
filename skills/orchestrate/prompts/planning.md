# Prompt shape — planning (Opus builds, Codex reviews)

Open-ended design, architecture, PRDs, multi-step plans, trade-off reasoning. The hardest reasoning lives here. Opus is worth the cost when the *thinking* is the deliverable. The cross-review (Codex `--read`) catches blind spots and over-confidence — a plan reviewed only by its author is a plan that hasn't been pressure-tested.

## Build phase shape (Opus subagent)

```
You're advising on <problem domain>. Goal: <single concrete outcome>.

Context:
<constraints — performance, deadlines, team size, existing tech, what's been tried>

What I want from you:
<the actual question, phrased as a request for a specific artifact — plan, spec, decision, set of options>

Constraints / non-negotiables:
- <constraint 1>
- <constraint 2>

Don't:
- <out-of-scope topics>
- <known traps to avoid>

Return:
1. The plan/spec/decision in the requested shape (e.g. "ranked list of 3 options with one-line tradeoffs and a recommendation", or "step-by-step phases with file paths and acceptance criteria").
2. A `Decisions:` block — non-obvious choices you made when constructing the plan (≤8 bullets, one line each).
```

The `Decisions:` block is what makes the cross-review valuable. Without it, the reviewer is critiquing surface structure; with it, the reviewer is critiquing reasoning.

## Good example

```
You're advising on the rate-limiting strategy for a public REST API. Goal: pick an algorithm that balances fairness across tenants with low operational complexity.

Context:
- ~5,000 requests/sec aggregate, expected to grow 3x in 12 months.
- Current state: a single nginx `limit_req` zone shared across all tenants. Heavy users starve quiet ones during spikes.
- Storage available: Redis cluster (already used for sessions). No appetite for Kafka or a streaming layer.
- Team is two backend engineers.

What I want from you:
A ranked recommendation of 2-3 algorithms (token bucket, sliding window, leaky bucket, GCRA), with a one-paragraph trade-off analysis and a single recommendation.

Constraints:
- Must be per-tenant, with a fallback global cap.
- Must work with our existing Redis (no new infra).
- Operational simplicity matters — we'd rather lose 5% efficiency than gain a complex queue.

Don't:
- Discuss client-side retries or backoff.
- Re-explain the basics of what rate limiting is.

Return:
1. Ranked list, 1 paragraph each, ending with "Recommendation: <X> because Y".
2. `Decisions:` block — non-obvious calls you made when ranking (≤8 bullets, one line each).
```

## Cross-review note

After Opus returns, SKILL.md dispatches the plan to Codex (`--read`) for cross-review. The reviewer brief in `cross-review.md` enforces the verdict format. Common things the cross-review catches in plans:
- The recommendation hand-waves an integration problem ("Phase 3: integrate with auth" with no detail on how, when this is the riskiest part).
- The trade-off analysis weighs criteria the task didn't list (e.g., "performance" when the task said operational simplicity matters more).
- A constraint from the task isn't carried into the recommendation.
- The plan over-scopes — adds work the user didn't ask for.

## Anti-patterns

- "Help me think about X" → too open. Ask Opus for a specific artifact.
- Pretending Opus has memory of prior conversation — it doesn't. Brief it cold.
- Multi-question prompts ("and also, what about Y, and Z?") → split into separate dispatches; the answers will be shallow otherwise.
- Skipping the Decisions block — the cross-review then critiques structure rather than reasoning, and you lose half the value.
