# Prompt shape — cross-model review (Phase 2)

The reviewer dispatch is a structured second-look at the builder's output. The reviewer is **always a different model** than the builder (LLM-as-judge bias literature is the reason — same-model self-review is misleading, not just neutral).

This file describes the brief shape only. SKILL.md handles the dispatch mechanics.

## Brief shape (always self-contained — reviewer doesn't see the conversation)

```
You are reviewing another model's work. Be specific, terse, and skeptical. Do not rewrite — flag.

ORIGINAL TASK:
<verbatim user request, no paraphrase>

BUILDER (<builder model name, e.g. "opus" or "codex (gpt-5.5-codex)">):
<full builder output — code/plan AND the Decisions block>

WHAT TO RETURN:
1. Verdict line — one of: APPROVE | APPROVE-WITH-NOTES | BLOCKERS
2. Numbered issue list. Tag each [blocker] / [note] / [nit].
3. One closing sentence: "What would change my verdict to APPROVE: <specific change>." (Skip if verdict is already APPROVE.)

WHAT TO FLAG:
- Correctness errors (logic bugs, off-by-one, wrong API usage, broken control flow).
- Missed requirements from the original task — anything the user asked for that isn't there.
- Edge cases the build doesn't handle (empty input, error paths, concurrent access, large inputs).
- Security issues (auth, input validation, injection, leaked secrets, broken access control).
- Decisions in the Decisions block that look wrong given the task's stated constraints.

WHAT TO IGNORE:
- Style preferences the task didn't state.
- Naming taste.
- Performance optimizations not asked for.
- Suggestions to "consider" alternatives that don't address a concrete issue.
- Anything the original task explicitly took off the table.
```

## Tagging discipline (verdict feeds the recommendation line)

The reviewer's tags map mechanically to the user-facing recommendation. Be honest with the tags or the recommendation will mislead.

- **`[blocker]`** — would cause real harm (data loss, broken prod path, security exposure, missed core requirement). Anything tagged blocker means the user should NOT ship without addressing.
- **`[note]`** — material but not shipping-blocking. Bug under specific conditions, missed minor requirement, edge case worth handling. User can ship with these in the backlog.
- **`[nit]`** — style, micro-optimization, taste. Nice-to-have. Skip in V1.5 — surface only if it would cost the user almost nothing to fix.

If everything is `[nit]`, the verdict is `APPROVE` and the nit list is fine to include for the user's awareness.

## Examples of good vs. bad review issues

### Good

```
Verdict: BLOCKERS

1. [blocker] The rate-limit counter is incremented BEFORE the credential check (line 47), so unauthenticated requests can exhaust a victim's quota by spraying their username. Move the increment after the credential check.
2. [blocker] `bcrypt.compare` is wrapped in a try/catch that swallows ErrorTypes, returning `false` on internal errors. This makes intermittent DB issues look like wrong-password to the user. Re-throw or log+return 500.
3. [note] No test coverage for the locked-account path. The Decisions block claims "tests still pass" but the new branch is untested.
4. [nit] `loginAttemptsByIp` is named inconsistently with the rest of the codebase's snake_case (`login_attempts_by_ip` elsewhere).

What would change my verdict to APPROVE: fix the two blockers and add one test for the locked-account path.
```

### Bad (do not produce)

```
Verdict: APPROVE-WITH-NOTES

1. [note] You might consider adding more comments.
2. [note] Have you thought about using TypeScript strict mode here?
3. [note] Performance could be better with caching.
4. [nit] I would prefer if the function was named differently.
```

The bad version is generic, doesn't engage with the actual code, suggests work the task didn't ask for, and has no concrete failure mode tied to any specific issue.

## When the reviewer is Codex (Opus built)

Spawn `codex:codex-rescue` with `--read` prepended so Codex doesn't try to edit:

```
--read
You are reviewing another model's work. <... rest of the brief above ...>
```

Codex with `--read` will read the repo if it needs to verify the build's claims about file state — that's a feature, not a bug. Do NOT remove `--read`; the reviewer must not modify code.

## When the reviewer is Opus (Codex built)

Spawn `general-purpose` with `model: "opus"`. The Opus subagent doesn't have repo access by default — the brief must include the full builder output (code, file paths, Decisions block) so the reviewer can judge without re-reading files. If the build's correctness depends on something Opus can't verify without the codebase (e.g., "this works because the existing utility function X handles edge cases"), the reviewer should flag that as `[note] cannot verify <specific claim> without the codebase` rather than guess.

## Anti-patterns

- **Don't ask the reviewer to rewrite.** The contract is "flag, don't fix." Mixing concerns degrades both signals.
- **Don't paraphrase the original task.** Verbatim only — paraphrase introduces drift between what the user asked for and what the reviewer evaluates against.
- **Don't truncate the builder output.** Reviewer needs the Decisions block; cutting it for "brevity" defeats the cross-review.
- **Don't pre-bias the reviewer** ("the builder said this is good, can you confirm?"). Frame neutrally.
