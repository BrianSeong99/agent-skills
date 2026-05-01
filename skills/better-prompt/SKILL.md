---
name: better-prompt
description: Critique a draft prompt and return a sharpened, ready-to-use rewrite. Use when the user asks to "improve this prompt", "make this prompt better", "rewrite my prompt", "critique this prompt", "fix this prompt", or hands over a prompt with the goal of refining it before sending. Also runs as `/better-prompt "<draft>"`. Returns: a short rubric-based diagnosis, a copy-pasteable rewrite, and a one-line note naming the task class and the biggest change.
---

# better-prompt — sharpen a draft prompt before you send it

Your job: take a draft prompt and return a tighter, more effective version. One pass. No iterative loops.

## Protocol — follow in order

### 1. Capture the input

The user supplies one of:
- A draft prompt (most common — the entire input is the prompt to refine).
- A task description with no draft yet ("I want to ask Claude to review my SQL migration — what should I send?").
- A draft plus optional metadata: target model/tool, constraints, a goal one-liner, an example output.

If only a goal is given (no draft), treat that as the draft and follow the same flow — the rewrite IS the prompt.

### 2. Classify into one task class

Read `~/.claude/skills/better-prompt/task-classes.md` and pick **exactly one** class that best fits:

- `coding` — build or modify code, tests, configs.
- `analysis` — understand, explain, reason about, debug something.
- `writing` — prose, docs, comms, copy.
- `extraction` — pull data out of unstructured input, transform, parse.
- `creative` — open-ended creative work, brainstorming.
- `general` — fallback when nothing else fits cleanly.

Class drives which guidance you load in step 4.

### 3. Score against the rubric

Read `~/.claude/skills/better-prompt/rubric.md`. For each criterion, mark **present**, **weak**, or **missing**:

1. **Goal clarity** — is there a single concrete outcome stated?
2. **Context** — surrounding situation, constraints, prior attempts.
3. **Constraints** — non-negotiables (don't, must, can't).
4. **Output spec** — desired format, length, structure.
5. **Examples** — reference outputs / before-after pairs / templates, where useful.

This score is the basis for the diagnosis you'll return.

### 4. Decide: ask, or rewrite

Count rubric items that are **missing AND cannot be inferred from context**:

- **0–1 missing-and-uninferrable** → proceed to rewrite. Use reasonable inferences; note them in the Notes section.
- **2+ missing-and-uninferrable** → ask up to **3 specific** clarifying questions. Each question targets one rubric gap. Wait for answers, then rewrite.

Hard cap: **never ask more than 3 questions**. If you'd need a fourth, write the rewrite anyway with explicit assumptions in Notes.

Examples of good clarifying questions:
- coding → "What stack/runtime is this targeting?", "Is this greenfield or modifying existing code?", "What security or perf bar matters most?"
- writing → "Who's the audience?", "Length cap?", "Tone — formal, conversational, terse?"
- extraction → "What format do you want the output in (JSON, CSV, list)?", "How should I handle ambiguous cases?"

### 5. Rewrite

Load the per-class guidance from `~/.claude/skills/better-prompt/examples.md` for shape reference, then write the improved prompt.

Style targets for the rewrite:
- **Self-contained.** The rewrite must work without seeing the original conversation — it's meant to be copy-pasted into a fresh session.
- **Imperative.** "Do X" not "Could you maybe do X if it's not too much trouble".
- **Sectioned.** Use short markdown sections (Task / Context / Requirements / Constraints / Deliverables / Return format) when the prompt is long enough to benefit. Skip sectioning for one-shot quick prompts.
- **Tight.** Cut hedging, throat-clearing, "in today's world", "it would be great if".
- **Format-explicit.** State the desired output shape clearly in a Return-format or Deliverables block.
- **Example-driven where useful.** If the user gave an example output, reference it; if a before-after pair clarifies, include one.

Do NOT:
- Add hyperbolic role-prompting ("You are the world's greatest…") — it's noise.
- Pad with unnecessary preamble.
- Invent constraints the user didn't imply.
- Hide your inferences — call them out in Notes.

### 6. Return

Format the response as **three sections, in order**:

```
## Diagnosis
- <Rubric item>: <state>. <one-line specific observation>
- <Rubric item>: <state>. <one-line specific observation>
- ... (3–5 bullets total, only the most actionable)

## Rewritten prompt

\`\`\`
<the entire rewrite, ready to paste>
\`\`\`

## Notes
- Class: <one of coding|analysis|writing|extraction|creative|general>
- Biggest change: <one sentence>
- Inferences I made: <comma-separated short list, or "none">
```

Honor explicit user requests for **rewrite-only** or **critique-only** — drop the section they don't want. Default is all three.

## Hard guardrails

- **One pass.** No iterative refine-and-rescore loop in V1.
- **Three questions max** before rewriting. Bias toward inferring + noting assumptions over asking.
- **Don't expand scope.** If the user's draft is for a small task, the rewrite is also for a small task. Don't turn a quick ask into a sprawling spec.
- **Don't prescribe a model.** Unless the user named one, the rewrite should be model-agnostic — Claude reads it just as well as the user's actual target.
- **Don't critique the user's intent**, only the prompt. If the user wants to do something dumb, that's their call — sharpen the prompt for what they asked.
- **Preserve the user's domain language.** If they call it "auth middleware" don't rename it "authentication subsystem".

## Out of scope (deferred)

- Auto-benchmarking the rewrite against the draft on real tasks.
- Learning across sessions / per-user style preferences.
- Prompt-caching / token-count optimization beyond what tightening already gets you.
- Multi-turn prompt design (system + user + tool sequences).
- Adversarial prompt hardening / jailbreak resistance — separate skill.
