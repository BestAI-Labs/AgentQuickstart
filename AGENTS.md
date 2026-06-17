# AGENTS.md — instructions for AI agents

If you are an AI agent with this repository available, your task is to install
BestAI Labs workflow skills into the user's local agent environment.

Workflows are **not** stored in this repo. Each lives in its own source
repository and is fetched at install time; licensed workflows are private and
need a BestAI access token.

**Do this:**

1. Read `README.md` and follow the **Agent Runbook** section.
2. Ensure a token is available if the user wants licensed workflows
   (`$BESTAI_TOKEN` or `~/.bestai/credentials`). Ask the user if it is missing.
3. Prefer running `bash install.sh` (optionally with skill names, e.g.
   `bash install.sh wide-research`). It is idempotent and safe to re-run.
4. Install only into the agents that exist on the machine (`~/.claude` for
   Claude Code, `~/.codex` for Codex).

**Rules:**

- Never overwrite a skill folder you did not create. The installer backs up any
  same-named *unmanaged* folder to `<name>.bak-<timestamp>` before installing —
  do the same if you install by hand.
- A `404` when fetching a workflow's tarball means the token is not entitled to
  that workflow. Report it and continue; do not retry in a loop.
- Do not write secrets or global config. The installer only creates skill
  folders under `~/.claude/skills` and `~/.codex/skills`, and never stores the
  token.
- After installing, tell the user what was installed, what was skipped for lack
  of access, and that they should start a new agent session.

The catalog of workflows (with each one's source repo and access level) is in
`skills.json`, or run `bash install.sh --list`.
