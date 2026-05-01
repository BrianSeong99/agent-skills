# Rubric — what makes a prompt good

Five criteria. Score each as **present**, **weak**, or **missing**. The diagnosis returned to the user pulls the 3-5 most actionable items from this list.

## 1. Goal clarity

A single, concrete outcome the prompt is asking for.

- **Present:** "Implement a login endpoint", "Summarize this paper in 200 words", "Find security issues in this diff".
- **Weak:** "Help with auth", "Look at this paper", "Review this".
- **Missing:** No verb at all; the prompt only describes a topic.

Common fix: put the goal in an imperative sentence at the top.

## 2. Context

The surrounding situation the model needs to do the task well.

- **Present:** Stack named, prior attempts described, why-this-matters mentioned, files/data referenced.
- **Weak:** Some context but key load-bearing pieces absent (e.g., "fix this bug" without saying what the bug is).
- **Missing:** No context at all; the prompt is a one-liner expecting the model to infer everything.

Common fix: add 2-4 lines under "Context:" naming the stack, the prior state, and the constraint that makes this hard.

## 3. Constraints

Non-negotiables. What the response **must** include or **must not** do.

- **Present:** "Don't use JWT — use server-side sessions", "Must work without internet access", "Preserve the public API".
- **Weak:** Implied constraints scattered throughout the prose, easy to miss.
- **Missing:** No explicit don'ts or musts.

Common fix: a bulleted "Constraints" or "Don't" block.

## 4. Output spec

The desired shape, format, length, or structure of the response.

- **Present:** "Return a numbered list with severity ratings", "Output JSON matching this schema: …", "Reply with the rewritten paragraph and nothing else".
- **Weak:** Format implied but not pinned ("a short summary").
- **Missing:** Nothing said about output shape.

Common fix: add a "Return:" line at the bottom describing exactly what to produce.

## 5. Examples

Reference outputs, templates, or before-after pairs that anchor the model on the desired style.

- **Present:** A concrete example of the desired output shape, even if just one.
- **Weak:** Vague description of the desired style ("make it formal").
- **Missing:** No example given, when one would have helped.
- **N/A:** Not all prompts need examples — for very simple tasks, examples add noise. Skip this criterion if the task is genuinely one-shot.

Common fix: when the desired style is non-obvious, paste one example output.

## Scoring discipline

- **Don't pad the diagnosis.** Pick the 3-5 items where the actual observed weakness has the biggest payoff. Skip items that are present-and-strong.
- **Be specific.** "Goal clarity: weak — 'help with auth' doesn't say what to build" is useful. "Goal clarity: weak" is not.
- **Don't moralize.** No "you should always include examples". Diagnose what's there, suggest what's missing for THIS prompt.
