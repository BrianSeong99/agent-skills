# Prompt shape — prose (Sonnet subagent)

Polished human-readable text: README sections, doc rewrites, blog drafts, polished commit messages, copywriting.

## Shape

```
Write <artifact type> for <audience> about <topic>.

Inputs:
<source material — bullets, prior draft, raw notes, an outline>

Voice / constraints:
- <tone — terse, formal, conversational, technical>
- <length — N words / N paragraphs / under N chars>
- <format — markdown / plain / specific structure>
- <do/don't list>

Return: <the artifact, no preamble, no apologies>
```

## Good example

```
Write the "Why this exists" section of a README for an open-source library.

Inputs:
- Library: a TypeScript wrapper around the GitHub REST API that adds opinionated defaults for retries, rate-limit handling, and pagination.
- Audience: TypeScript devs who've used `octokit` and found themselves writing the same retry/backoff/pagination boilerplate in every project.
- Problem it solves: the official client exposes pagination, retry, and rate-limit handling as separate concerns; assembling a "fetch all PRs across an org with sane retries" flow takes 60+ lines. This wrapper does it in one call with sensible defaults.

Voice / constraints:
- Direct, technical, no hype.
- 2 paragraphs.
- No emoji, no "we believe…", no "in today's world…".
- Markdown.

Return: just the section text, no headers from me, ready to paste under `## Why this exists`.
```

## Anti-patterns

- Asking for "marketing copy" without a target audience → Sonnet will hedge into mush.
- Long input dumps → distill to bullets first; quality of input dictates quality of output.
- Asking for "polished prose" on a quick-draft commit message → that's `quick-lookup` (Ollama). Save Sonnet for prose where the polish *matters*.
