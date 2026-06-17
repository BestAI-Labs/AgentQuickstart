# CLAUDE.md

This file points Claude Code at the same guidance every agent uses for this
repository.

See [AGENTS.md](AGENTS.md) for the full instructions. In short: read
`README.md`, follow the **Agent Runbook**, ensure a BestAI token is available
for any licensed workflows (`$BESTAI_TOKEN` or `~/.bestai/credentials`), then
run `bash install.sh` to install BestAI workflow skills into `~/.claude/skills`
(and `~/.codex/skills` if Codex is present).

Workflows are fetched from their own source repositories — nothing is stored in
this repo. The installer is idempotent and never overwrites a skill folder it
does not manage.
