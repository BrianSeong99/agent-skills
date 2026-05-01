# Prompt shape — code-review (Sonnet subagent)

Read-mostly judgment work: "is this right", "find bugs", "what does this do", PR review. The Sonnet subagent doesn't see this conversation, so the prompt must be self-contained.

## Shape

```
Review the following <kind> for <criterion>. Return: <expected output shape>.

Context:
<what the code does, why it exists, anything load-bearing>

<paste the code or diff>

What to flag:
- <criterion 1>
- <criterion 2>
- <criterion 3>

What to ignore:
- <out-of-scope concerns>
```

## Good example

```
Review the following migration SQL for safety. We're adding a NOT NULL column to a 50M-row table.

Context: This runs against Postgres 15. The table has heavy concurrent writes. The team wants zero downtime.

ALTER TABLE users ADD COLUMN signup_source text NOT NULL DEFAULT 'web';

What to flag:
- Lock escalation that blocks reads or writes
- Long-running rewrites that pin a transaction
- Anything that breaks rolling deploys
- Better alternatives

What to ignore:
- Style nits, naming conventions
- The default value choice itself

Return: a short verdict (safe / unsafe / conditional), then a numbered list of concrete issues with severity.
```

## Anti-patterns

- "Tell me what you think" → too vague, Sonnet will hedge. Always specify what to flag.
- Long pre-amble before the artifact → keep the framing tight, paste the artifact, then list criteria.
- Asking Sonnet to *fix* it after reviewing → that's two dispatches. First review, then route the fix to Codex if accepted.
