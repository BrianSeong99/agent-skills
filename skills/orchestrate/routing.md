# Routing table

Single source of truth for category → backend mapping. SKILL.md mirrors this; if they drift, this file wins.

## Categories

### `quick-lookup` → Ollama, single pass
**Signals:** regex / format conversion / single-fact extraction / case-conversion / draft-quality commit message / short text transform. Output ≤200 tokens. Doesn't need repo context, doesn't need internet, doesn't need correctness verification.
**Anti-signals:** anything load-bearing for production, anything multi-step.
**Model:** `OLLAMA_MODEL` (default `gemma3:4b`).
**No review.**

### `prose` → Sonnet, single pass
**Signals:** README sections, doc rewrites, blog drafts, polished commit messages (not draft-quality), copywriting. Quality matters.
**Anti-signals:** quick draft → `quick-lookup`. Strategy doc → `planning`.
**No review.**

### `code-quick` → Codex spark, single pass
**Signals:** single-file mechanical edit / rename a variable / fix a typo / add an import / remove a console.log / fix a single failing test. Edit pattern is obvious from the request, ≤30 LoC change. Reviewer overhead exceeds catch rate at this size.
**Anti-signals:** anything that needs design judgment, anything multi-file.
**Builder:** `Agent(subagent_type: "codex:codex-rescue", prompt: "--model gpt-5.5-codex-spark <task>")`.
**No review.**

### `code-build` → cross-review (Opus or Codex builds, the other reviews)
**Signals:** any non-trivial code work — implement a feature, refactor, port, restructure, write a module, fix a non-trivial bug, build something from a spec.
**This is the default for substantive code work.** Always cross-reviewed.

#### Auto-pick the builder

The builder must be the one whose strengths fit the task. The reviewer is whichever wasn't picked.

**Codex builds when** the task is about edit volume, repo navigation, or multi-file consistency. Codex reads the repo natively, holds a working set across files, and writes patches. Strong signals:
- "refactor" / "extract" / "consolidate" / "split" / "rename across files"
- "port from X to Y" / "migrate" / "rewrite this in <other language>"
- multi-file scope ("update all the call sites", "across the workspace", "everywhere we use X")
- volume cues ("there are 12 instances of", "every component that imports Y")
- mass edits / lint-style fixes / dependency upgrades that touch many files

**Opus builds when** the task is reasoning-heavy, novel, or design-shaped. Opus thinks broader and produces more coherent novel logic. Strong signals:
- "implement <new feature>" / "build a <new thing>"
- "design and implement" / "from this spec, write the code"
- algorithm-shaped ("write a function that solves X under constraint Y")
- architecture-shaped ("set up the module structure for", "wire these components together for the first time")
- single-file but high-novelty ("write a custom rate limiter that does X")

**Borderline → Opus builds, Codex reviews.** When in doubt, default to reasoning.

**User override always wins.** Phrases like:
- "use codex to build" / "build with codex" / "have codex do it" → Codex builds, Opus reviews.
- "use opus to build" / "build with opus" / "have claude do it" → Opus builds, Codex reviews.
- "no review" / "just build" → skip Phase 2; you're back to single-pass.

### `planning` → Opus builds, Codex reviews
**Signals:** "design", "architect", "PRD", "spec out", "what's the right approach", "break this into phases", "trade-offs", multi-step plans, ambiguous problems where the *thinking* is the deliverable.
**Anti-signals:** "just write the code" → `code-build`. "Summarize" → `prose`.
**Builder:** Opus subagent. **Reviewer:** Codex via `codex:codex-rescue` with `--read`.
The cross-review here is non-negotiable: a plan reviewed only by its author is a plan that hasn't been pressure-tested.

### `code-review-only` → cross-model reviewer (no Phase 1)
**Signals:** user has an artifact (code, diff, plan) and wants it reviewed without you regenerating it. "review this PR", "what's wrong with this", "find issues in <pasted code>".
**Reviewer pick:** if the artifact's author is known (the user names them, or it was just produced by another orchestrate dispatch), pick the cross-model. Otherwise, default to Opus (deeper reasoning) for high-stakes review or Codex (`--read`) for code-heavy review.
**Cross-model rule still applies:** never use the same tier as the original generator.

### `judge` (explicit second-opinion request)
**Signals:** user explicitly asks for a second opinion / cross-check / "what does codex think" / "have opus look at this".
**Same as `code-review-only` but the user is explicitly invoking the cross-model rule.** Honor their request literally — if they say "have codex look at this opus output", you do exactly that.

### fallback → Sonnet, single pass
**When:** unclassifiable, no signal matches.
**Why Sonnet:** safe middle. Cheaper than Opus, doesn't pretend to be a coding specialist.
**No review** in the fallback case — if the route is unclear, two passes don't make it clearer.

## Decision algorithm

1. **User pinned a backend explicitly?** Honor it. ("use codex" → Codex builds; "review with opus" → Opus reviews.) Skip auto-classification.
2. **User asked for no review?** ("just build", "no review", "skip the cross-check") → single-pass, no Phase 2. Set category accordingly (`code-build` becomes single-pass-Opus or single-pass-Codex by user's pick).
3. **User asked for review-only?** ("review this", "find issues in") → `code-review-only`, no Phase 1.
4. Otherwise, walk the categories above top-to-bottom. Pick the first whose signals match. Ties → cheaper backend.
5. **Stakes override:** if the task is irreversible (writes to main, sends a message, modifies prod config), upgrade one tier. `code-quick` → `code-build` (so it gets reviewed). Never downgrade.
6. **Availability override:** if the chosen backend is `ok:false` in preflight, fall through:
   - Codex down + `code-build`: try Opus single-pass with a "review unavailable" note.
   - Opus down + `code-build`: try Codex single-pass with a "review unavailable" note.
   - Both down: refuse with the fix commands surfaced from `preflight.json`.
7. **Wall-clock budget:** 5 min total per invocation. If Phase 2 hasn't returned by the cap, surface what we have.

## What is NOT in the table

- **Haiku.** Deliberately omitted.
- **Auto-fix loops.** V1.5 surfaces blockers and stops; the user re-dispatches with the review attached if they want a fix pass.
- **Multi-round debate.** The literature shows single-cross-review captures most of the gain; more rounds add cost without clear win.
- **Sonnet as a code reviewer.** When `code-build` or `planning` needs review, the reviewer is Codex or Opus — both are above Sonnet for code/plan judgment. Sonnet stays in `prose` and `fallback`.
- **Multiple Ollama models simultaneously.** One model per session via `OLLAMA_MODEL`.

## Cross-model rule (the load-bearing constraint)

Same model on both sides of build+review is **forbidden**, not optional. Position bias, verbosity bias, and self-preference bias are documented at scale (the LLM-as-judge literature is unambiguous). A model judging its own output assigns higher scores than the same output from another model, regardless of correctness.

If preflight says only one cross-pair is reachable (e.g., Codex down so Opus has no cross-reviewer), do **single-pass** with a clear note rather than fake-reviewing with the same model. Honesty over theater.
