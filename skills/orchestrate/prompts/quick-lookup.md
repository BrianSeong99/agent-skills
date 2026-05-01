# Prompt shape — quick-lookup (Ollama / configured local model)

For one-shot transforms, regex, format conversion, single-fact extraction, draft-quality short text. Latency-sensitive, ≤200 tokens out.

## Shape

Send the prompt as a single self-contained instruction. No system message, no chain-of-thought. Just the task.

- One sentence of instruction.
- The input data inline.
- Optional: one-line output-format constraint.

## Good

```
Convert these snake_case identifiers to camelCase, one per line, no quotes:
foo_bar_baz
hello_world
http_request_2
```

```
Extract just the URL from this sentence and print it alone:
"I think the docs at https://example.com/start.html are clearer than the README."
```

```
Draft a 50-character-max conventional commit subject for: added retry logic to the rate-limiter middleware.
```

## Bad (do not send to a small local model)

- Anything that needs to read a file you haven't pasted in.
- Anything where you'd want to verify the answer ("are you sure?").
- Anything load-bearing for production correctness.
- Anything with branching logic ("if X then Y else Z, and explain why").

If the request shape doesn't fit, reroute — don't try to coerce it.
