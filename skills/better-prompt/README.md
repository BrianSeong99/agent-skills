# better-prompt

Critique a draft prompt and return a sharpened, ready-to-use rewrite. One pass — diagnosis + rewrite + notes.

## Why

Most "first-draft" prompts are missing one or two load-bearing pieces — usually the desired output format or the integration context. This skill catches those gaps against a fixed rubric, asks at most three clarifying questions if a critical field is missing, and rewrites the prompt into a tight, copy-pasteable form.

It's the inverse of `orchestrate` — that one routes a *task* to the right backend; this one sharpens the *prompt* before it gets sent anywhere.

## Usage

Auto-trigger on phrases like "improve this prompt", "rewrite my prompt", "make this prompt better", "critique this prompt".

Or explicit:
```
/better-prompt "Write code for a login system."
```

You can also paste a longer draft after the command — the skill treats whatever follows as the input.

## Output shape

Three sections, every time (unless you ask for rewrite-only or critique-only):

```
## Diagnosis
- <rubric item>: <state>. <one-line observation>
- ...

## Rewritten prompt
<copy-pasteable rewrite>

## Notes
- Class: <coding|analysis|writing|extraction|creative|general>
- Biggest change: <one sentence>
- Inferences I made: <comma-separated, or "none">
```

## Install

```bash
./install.sh better-prompt
```

Or manually:
```bash
ln -sfn "$(pwd)/skills/better-prompt" ~/.claude/skills/better-prompt
```

## How it works

1. **Classify** the draft into one of six task classes (`coding`, `analysis`, `writing`, `extraction`, `creative`, `general`). See [`task-classes.md`](./task-classes.md).
2. **Score** against a five-criterion rubric: goal clarity, context, constraints, output spec, examples. See [`rubric.md`](./rubric.md).
3. **Decide** — if 0–1 critical fields are missing-and-uninferrable, rewrite; if 2+, ask up to 3 specific clarifying questions first.
4. **Rewrite** using the per-class shape from [`examples.md`](./examples.md).
5. **Return** the three-section response.

The intelligence lives in `SKILL.md` plus those three reference files — no helper scripts. A future V2 might add scoring scripts and a one-shot iteration loop, but V1 is deliberately simple.

## Hard caps

- **One pass.** No iterative refine-and-rescore loop.
- **Three questions max** before rewriting. Bias toward inferring + noting.
- **Don't expand scope.** Small ask → small rewrite.
- **Don't prescribe a model.** Rewrite is model-agnostic unless the user named one.
- **Don't critique the user's intent.** Only the prompt.

## Files

```
skills/better-prompt/
├── SKILL.md          # protocol Claude follows
├── README.md         # this file
├── rubric.md         # 5 criteria, scoring discipline
├── task-classes.md   # 6 classes with signals + likely clarifying questions
└── examples.md       # one before/after per class
```

No state directory; this skill is stateless.

## Prior art

Closest references:
- [`nidhinjs/prompt-master`](https://github.com/nidhinjs/prompt-master) — Claude skill: target-tool detection → 3 clarifying questions → silent framework selection → token-efficiency pass.
- [`ckelsoe/prompt-architect`](https://github.com/ckelsoe/prompt-architect) — Claude Code skill with rubric scoring and decision-tree task classification.
- [`anthropics/prompt-eng-interactive-tutorial`](https://github.com/anthropics/prompt-eng-interactive-tutorial) — official Anthropic structure-and-roles guidance.
- [`promptfoo/promptfoo`](https://github.com/promptfoo/promptfoo) — declarative evaluation; conceptual influence for the rubric.
- [`stanfordnlp/dspy`](https://github.com/stanfordnlp/dspy) and [`zou-group/textgrad`](https://github.com/zou-group/textgrad) — prompt optimization frameworks; conceptual only — too heavy for a single skill.

## License

[MIT](../../LICENSE).
