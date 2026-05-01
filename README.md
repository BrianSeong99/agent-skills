# agent-skills

Open-source [Claude Code](https://www.anthropic.com/claude-code) skills.

Each skill in [`skills/`](./skills) is a self-contained directory with a `SKILL.md` and supporting files. Symlink the ones you want into `~/.claude/skills/` (or use [`install.sh`](./install.sh)).

## Available skills

| Skill | What it does |
|---|---|
| [`orchestrate`](./skills/orchestrate) | Multi-backend dispatcher with **cross-model peer review** built in. For substantive code/plan work, one model builds (auto-picked: Codex for refactors, Opus for novel features) and a *different* one reviews. Single-pass for trivial edits and one-shot text transforms. |
| [`better-prompt`](./skills/better-prompt) | Critiques a draft prompt against a fixed rubric and returns a sharpened rewrite. One pass, up to 3 clarifying questions, no scripts required. |

## Install

Clone, then run the installer for the skills you want:

```bash
git clone https://github.com/BrianSeong99/agent-skills.git
cd agent-skills
./install.sh orchestrate
```

`install.sh` is idempotent — re-running it just refreshes symlinks. Pass `--all` to install every skill in `skills/`.

To install manually, symlink the skill into `~/.claude/skills/`:

```bash
mkdir -p ~/.claude/skills
ln -sfn "$(pwd)/skills/orchestrate" ~/.claude/skills/orchestrate
```

Reload Claude Code (or start a fresh session) and the skill will be available.

## Prerequisites

Required for any skill in this repo:
- [Claude Code](https://www.anthropic.com/claude-code) installed and signed in
- `bash`, `curl`, `jq` on `PATH`

Per-skill extras (optional — skills degrade gracefully if any are missing):

**`orchestrate`:**
- [Codex CLI plugin](https://github.com/openai/codex) — install via Claude Code's plugin marketplace (`/plugins` → `codex@openai-codex`). Routes for narrow/broad code edits use Codex; without it those routes fall back to Sonnet.
- [Ollama](https://ollama.com) running locally, with at least one instruction-tuned model pulled (e.g. `ollama pull gemma3:4b`). Routes for `quick-lookup` use Ollama; without it those routes fall back to Sonnet.
- `node` (>=18) on `PATH` (Codex CLI dependency).

## Configuration

Skills read environment variables; there is no config file to maintain.

**`orchestrate`:**

| Var | Default | Effect |
|---|---|---|
| `OLLAMA_URL` | `http://localhost:11434` | Ollama daemon URL. |
| `OLLAMA_MODEL` | `gemma3:4b` | Local model used for `quick-lookup` route. |
| `OLLAMA_TIMEOUT_S` | `30` | Wall-clock budget for a single Ollama dispatch. |
| `CODEX_PLUGIN_ROOT` | autodiscovered | Override if you've moved the Codex plugin out of `~/.claude/plugins/cache/openai-codex/codex/`. |
| `ORCHESTRATE_DISABLED_BACKENDS` | empty | Comma-separated. e.g. `codex` or `ollama,codex` — opt out of a backend even if installed. |

## Privacy

Each skill writes any state to `~/.claude/<skill-name>/`. **Do not commit that directory.** It is per-machine, may contain logs of your dispatches, and is unrelated to the skill source.

The skills themselves never phone home or transmit telemetry. The backends they dispatch to (Claude API, Codex CLI, Ollama) follow their own privacy policies.

## Contributing

Pull requests welcome. Each skill should:
1. Be self-contained in its own `skills/<name>/` directory.
2. Have a `SKILL.md` with frontmatter (`name`, `description`) following [Claude Code's skill format](https://docs.claude.com/en/docs/claude-code/skills).
3. Have a `README.md` for humans, separate from `SKILL.md` (which Claude reads).
4. Degrade gracefully when optional dependencies are missing.
5. Document required env vars in this top-level README.

Architectural notes for each skill live in [`docs/`](./docs).

## License

[MIT](./LICENSE) — fork, embed, modify, sell. Attribution appreciated, not required.
