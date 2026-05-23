# gh-issue-decompose

Decompose a feature epic into N child issues with consistent `Sub-issue of #<n>` parent-link bodies, filed via `gh issue create`. Links all children back to the epic in a closing comment.

## Why

Structuring a sprint around a parent epic means typing the same HEREDOC boilerplate 10–60 times — parent-link opener, short description, optional acceptance criteria, `gh issue create` invocation. This skill eliminates that per-issue overhead.

Labels are always confirmed interactively. No labels are assumed or auto-applied.

## Usage

Auto-trigger on phrases like "decompose this into issues", "break this epic into N issues", "create child issues for #N", "file these as sub-issues of #N".

Or explicit:

```
/gh-issue-decompose #74
/gh-issue-decompose https://github.com/org/repo/issues/74
```

### Flow

1. Skill asks for the epic number if not provided.
2. Skill asks for the breakdown (list of child titles/descriptions) if not provided.
3. Skill runs `gh label list` and asks which labels to apply (may be none).
4. Skill shows a preview of all composed bodies and waits for confirmation.
5. On confirmation, files each issue with `gh issue create`, printing each URL as it's created.
6. Posts a summary table comment on the epic linking all children.

## Install

```bash
./install.sh gh-issue-decompose
```

Or manually:

```bash
ln -sfn "$(pwd)/skills/gh-issue-decompose" ~/.claude/skills/gh-issue-decompose
```

Requires `gh` to be authenticated (`gh auth status`).

## Files

```
skills/gh-issue-decompose/
├── SKILL.md                    # protocol Claude follows
├── README.md                   # this file
└── templates/
    └── sub-issue.md            # body skeleton (parent-link + optional sections)
```

No helper scripts. This is a prompt-time skill — Claude composes the bodies and runs `gh issue create` via Bash.

## License

[MIT](../../LICENSE).
