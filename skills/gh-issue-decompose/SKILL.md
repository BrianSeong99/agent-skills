---
name: gh-issue-decompose
version: 1.0.0
description: Use for `/gh-issue-decompose <epic-url-or-number>` or when the user says "decompose this into issues", "file these as sub-issues of #N", "break this epic into N issues", or "create child issues for #N".
triggers:
  - /gh-issue-decompose <epic-url-or-number>
  - decompose this into issues
  - file these as sub-issues of #N
  - break this epic into N issues
  - create child issues for #N
---

# gh-issue-decompose

Turn one parent epic into explicitly linked child GitHub issues. This is a pure prompt-time protocol; do not create or run helper scripts.

## Protocol

1. Ask the user for:
   - The epic URL or issue number.
   - The number of child issues to create.
   - A short title and purpose for each child issue.

2. Run:
   ```bash
   gh label list
   ```
   Show the full output to the user. Ask the user to pick labels for the child issues, or press enter to skip labels. NEVER auto-assign any label.

3. Compose every child issue body from `templates/sub-issue.md`. Preview each composed issue body in full for the user to confirm or edit before creating issues.

4. After the user confirms the previews, create each child issue with:
   ```bash
   gh issue create --title "..." --body "$(cat <<'EOF'
   ...
   EOF
   )" [--label <chosen>]
   ```
   Include `--label <chosen>` only when the user explicitly selected labels.

5. After all child issues are created, post one comment on the parent epic listing every created child issue number and title:
   ```bash
   gh issue comment <epic> --body "Sub-issues created: #N Title, #M Title, ..."
   ```
