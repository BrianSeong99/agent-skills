# Worked examples

One before/after per class. Use these as shape references — the rewrites are not templates to fill in, they're examples of what "tightened" looks like.

## `coding`

**Before:**
```
Write code for a login system.
```

**After 3 clarifying answers** (stack=Node/Express + Postgres, existing app, sessions + rate limiting):
```
You are extending an existing Node.js/Express/Postgres codebase. Implement a production-grade login endpoint.

Requirements:
- Server-side sessions (not JWT).
- Rate limit login attempts per IP and per username.
- Validate credentials against the existing users table; never log raw passwords.
- Handle invalid credentials, locked accounts, and missing users with the same generic error to avoid user enumeration.
- Preserve the existing project structure and middleware conventions.

Deliverables:
- Files to create or modify (named explicitly).
- The code changes themselves.
- A 1-paragraph note on the security decisions made.
- A minimal test plan covering the happy path and 3 failure modes.

Don't:
- Rewrite unrelated auth flows.
- Introduce new dependencies beyond what's already in package.json.
```

**Notes:** class=coding; biggest change = converting a vague request into scoped implementation instructions with explicit security and integration constraints. Inferences: production-grade ambition, no new deps allowed, the same-error rule for failed login.

---

## `analysis`

**Before:**
```
Look at this PR and tell me what you think.
```

**After:**
```
Review the following PR for correctness, safety, and clarity. Return a verdict (approve / approve with notes / request changes), then a numbered list of concrete issues with severity (blocker / nit).

Context: this PR touches the rate limiter that protects the public API. Heavy traffic, ~5k req/s. Two engineers maintain this code.

What to flag:
- Race conditions or off-by-one errors in counter logic.
- Behavior change for existing callers (the public contract must hold).
- Missing test coverage for new branches.
- Anything that would surprise an on-caller at 3am.

What to ignore:
- Style nits (linter handles those).
- Naming taste preferences.

<paste diff>

Return: verdict line, then the numbered issue list. No preamble.
```

**Notes:** class=analysis; biggest change = swapping vague "tell me what you think" for a structured review with criteria and an explicit verdict format.

---

## `writing`

**Before:**
```
Write something for the README.
```

**After 2 clarifying answers** (audience=TS devs familiar with octokit, length=2 paragraphs):
```
Write the "Why this exists" section of a README for a TypeScript wrapper around the GitHub REST API.

Audience: TypeScript developers who've used `octokit` and found themselves rewriting the same retry/rate-limit/pagination boilerplate in every project.

The library's value: the official client exposes pagination, retry, and rate-limit handling as separate concerns. Stitching them together for "fetch all PRs across an org" takes 60+ lines. This wrapper does it in one call with sensible defaults you can override.

Voice:
- Direct, technical, no hype.
- 2 paragraphs, ~120 words.
- Markdown.
- No emoji, no "we believe…", no "in today's world…".

Return: just the section text, ready to paste under `## Why this exists`. No headers from you.
```

**Notes:** class=writing; biggest change = giving the audience, the value proposition, and the voice constraints the writer needs to actually write the section.

---

## `extraction`

**Before:**
```
Get the URLs out of this email thread.
```

**After:**
```
Extract every URL from the following email thread. Return one URL per line, plain text, no markdown links, no surrounding quotes.

Rules:
- Include each URL exactly once even if it appears multiple times.
- Strip trailing punctuation (commas, periods, parens) that aren't part of the URL.
- Skip URLs inside obvious quoted-reply blocks (lines starting with `>`).
- If no URLs are found, return the literal string `(none)`.

<paste thread>
```

**Notes:** class=extraction; biggest change = explicit output format + dedupe rule + edge-case handling for quoted replies and no-result.

---

## `creative`

**Before:**
```
Help me name my project.
```

**After 3 clarifying answers** (it's a privacy-preserving file sync tool, audience=privacy-conscious devs, must be available as both .com and on npm):
```
Suggest 8 candidate names for a privacy-preserving file-sync tool.

Constraints:
- Available as `.com` AND as an npm package name.
- Pronounceable in English; ≤8 letters preferred, ≤12 letters max.
- Evokes privacy, sync, or trust — but no over-used clichés (skip "vault", "shield", "secure").
- Memorable; not a portmanteau of "private" + "sync".

For each name, return: the name, a one-line origin or association, and a 1-10 score on memorability.

Format: numbered list, one name per item.
```

**Notes:** class=creative; biggest change = pinning down "good" with explicit constraints and a scoring criterion, plus a return format.

---

## `general`

**Before:**
```
What should I do about my CI being slow?
```

**After 2 clarifying answers** (current p50=22min, mostly waiting on test suite, ~800 tests in Jest):
```
Recommend a strategy to reduce a CI pipeline's p50 from 22min to under 8min. The bottleneck is a Jest test suite (~800 tests, mostly unit, some integration with a real Postgres). Currently runs serially in one job.

What I want: a ranked list of 3 approaches, with one paragraph per approach covering:
- The change.
- Expected wall-clock improvement (rough estimate).
- Operational cost (effort, ongoing maintenance, infra cost).
- The single biggest risk.

End with a 1-line recommendation: "Start with X because Y."

Don't suggest:
- Cutting tests or coverage.
- Switching off Jest (we're locked in).
```

**Notes:** class=general (a hybrid of analysis + planning); biggest change = scoping the answer to a ranked, comparable structure instead of an open-ended brainstorm.
