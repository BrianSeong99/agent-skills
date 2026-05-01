# Task classes

Six classes. Pick exactly one per prompt. The class drives which guidance you load in `examples.md`.

## `coding`

Build, modify, debug, or extend code, tests, configs, or scripts.

- Signals: "implement", "write a function", "refactor", "fix this bug", "add a test", file paths, language names, framework names.
- Most-frequent rubric gaps: stack/runtime, integration context (greenfield vs existing), security/perf bar, output format (diff, full file, patch).
- Likely clarifying questions:
  1. What stack/runtime is this targeting?
  2. Is this greenfield or modifying existing code? If existing, what conventions does the codebase follow?
  3. What's the security or performance bar? (Production-grade, prototype, throwaway?)

## `analysis`

Understand, explain, compare, reason about, or debug an artifact (code, doc, data, output).

- Signals: "explain", "what does this do", "compare", "trace through", "why is this happening", "is this right".
- Most-frequent rubric gaps: depth wanted, audience expertise, output structure (bullets vs prose vs table).
- Likely clarifying questions:
  1. Audience — what does the reader already know?
  2. Depth — high-level overview or step-by-step trace?
  3. Output format — narrative, structured table, or annotated source?

## `writing`

Prose, docs, READMEs, blog drafts, polished comms, copy.

- Signals: "draft a", "write a section", "rewrite this paragraph", "tweet about", "README for".
- Most-frequent rubric gaps: audience, tone, length cap, format constraints.
- Likely clarifying questions:
  1. Who's the audience?
  2. Length cap — words/paragraphs/characters?
  3. Tone — formal, terse, conversational, technical?

## `extraction`

Pull structured data out of unstructured input, transform, parse, classify, or normalize.

- Signals: "extract", "parse", "convert", "find all the", "tabulate", "get the URLs from".
- Most-frequent rubric gaps: output schema, ambiguous-case handling, completeness criterion (all instances? top N?).
- Likely clarifying questions:
  1. What output format? (JSON schema, CSV, plain list?)
  2. How should ambiguous cases be handled — best guess, mark as unknown, skip?
  3. All instances or just the most relevant ones?

## `creative`

Open-ended creative work — naming, brainstorming, ideation, fiction, design exploration.

- Signals: "brainstorm", "give me 10 ideas for", "name this", "what could we call", "design a logo concept".
- Most-frequent rubric gaps: how many options, evaluation criteria for "good", domain constraints.
- Likely clarifying questions:
  1. How many options do you want?
  2. What makes a good answer here — what's the criterion?
  3. Any domain constraints (existing names, brand voice, audience)?

## `general`

Fallback for prompts that don't fit any of the above cleanly. Don't overthink classification — this exists so you can move on.

- Signals: meta-questions ("what should I do about X"), open-ended advice, multi-class hybrids, unclear intent.
- Most-frequent rubric gaps: usually goal clarity itself.
- Likely clarifying questions:
  1. What's the single concrete outcome you want?
  2. What have you already tried or considered?
  3. What does success look like — how would you know the answer was good?

## Picking the class

If the prompt spans two classes (e.g., "explain this code AND fix the bug"), pick the **dominant** one based on what the requested deliverable mostly is. If `coding` and `analysis` both fit, pick the one that matches the verb at the top of the prompt.
