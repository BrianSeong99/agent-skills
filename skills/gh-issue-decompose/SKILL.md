---
name: gh-issue-decompose
description: Take a feature epic and decompose it into N child issues with parent-link bodies (Sub-issue of #<n>). Asks for the epic number/URL if not provided, accepts the breakdown as input or asks for it, confirms labels interactively, then files each child issue via `gh issue create` with a HEREDOC body. Links all children back to the epic in a closing comment. Use when the user says "decompose this into issues", "file these as sub-issues of #N", "break this epic into N issues", "create child issues for #N", or runs `/gh-issue-decompose <epic-url-or-number>`.
---

# gh-issue-decompose — epic-to-sub-issues filer

Your job: take a feature epic and file N child issues against it, each with a consistent HEREDOC body and a `Sub-issue of #<n>` parent-link opener. Then post a comment on the epic linking back to all created children.

No labels are assumed. You confirm with the user before applying any.

## Protocol — follow in order

### 1. Collect the epic

If the user ran `/gh-issue-decompose <epic>` or included a number/URL in their message, extract it. Otherwise ask:

> "Which epic? Give me the issue number or URL (e.g. `#74` or `https://github.com/org/repo/issues/74`)."

Resolve to a number (`N`). If you need the repo, run:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

### 2. Collect the breakdown

If the user already supplied a list of child issue titles (or title + description pairs), use it directly.

Otherwise ask:

> "List the child issues — one per line. Title is enough; add a blank-line separator + extra notes if you want more detail in the body."

Wait for the list before proceeding.

### 3. Confirm labels (interactive — never assume)

Run:

```bash
gh label list --limit 100
```

Show the available labels to the user and ask:

> "Which labels should I apply to all child issues? (Enter names comma-separated, or press Enter for none.)"

Wait for the answer. If the user gives names, validate each against the label list output. If a label doesn't exist, ask whether to create it or skip it.

Store the confirmed label set (may be empty).

### 4. Compose and confirm each issue body

For each child issue, fill in the template at `~/.claude/skills/gh-issue-decompose/templates/sub-issue.md`:

- Replace `<!-- PARENT -->` with `Sub-issue of #N` (where N is the epic number).
- Replace `<!-- TITLE -->` with the issue title.
- Replace `<!-- DESCRIPTION -->` with the short description the user supplied, or the title itself if only a title was given.
- Keep optional sections (Acceptance, Notes) only if the user provided content for them; otherwise omit.

Show a numbered preview of all composed bodies before creating anything. Ask:

> "Looks good? (yes / edit N / abort)"

Only proceed when the user confirms. If they say "edit N", collect the replacement text for child N and update it before re-confirming.

### 5. Create the issues

For each child, run:

```bash
gh issue create \
  --title "<TITLE>" \
  --body "$(cat <<'EOF'
Sub-issue of #N

<short description>

## Acceptance criteria
<if provided>

## Notes
<if provided>
EOF
)" \
  [--label "<label1>" --label "<label2>"]
```

Capture the returned issue URL/number for each. Print each as it is created:

```
✓ #<child-n>  <title>  <url>
```

### 6. Link children back to the epic

After all children are created, post a single comment on the epic:

```bash
gh issue comment N --body "$(cat <<'EOF'
## Sub-issues created

| # | Title |
|---|-------|
| #<c1> | <title1> |
| #<c2> | <title2> |
...
EOF
)"
```

Print confirmation of the comment URL.

## Hard guardrails

- **Never auto-apply labels.** Not `enhancement`, not `bug`, not anything. Confirm with the user first, every time.
- **No test-plan checklist in every body.** The template has optional sections; only include them when the user supplied content. Don't invent acceptance criteria.
- **HEREDOC quoting.** Always use `'EOF'` (single-quoted) in the `cat <<'EOF'` delimiter to prevent shell expansion inside the body.
- **Abort cleanly.** If the user says "abort" at the confirmation step, stop immediately. Do not create partial issues silently.
- **One parent per run.** This skill handles one epic per invocation. If the user wants to decompose two epics, run twice.
- **gh must be authenticated.** If `gh auth status` fails, surface the error verbatim and stop.

## Out of scope (future)

- Milestones or projects assignment.
- Automatically converting a GitHub project's card list into child issues.
- Batch-editing already-created child issues.
- Stacked-PR linking.
