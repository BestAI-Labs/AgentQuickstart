# AgentQuickstart — Design

Status: approved 2026-06-16; revised 2026-06-17 (skills are no longer bundled).
This is the design of record for the repository.

## Purpose

A **public** GitHub repository (`BestAI-Labs/AgentQuickstart`) that serves as a
one-command, agent-executable bootstrap for installing BestAI Labs workflows
(packaged as *skills*) into a customer's local Claude Code and/or Codex
environment.

A customer points their agent at the repo; the agent reads `README.md` (written
as an executable runbook) and runs the installer, which creates the needed
directories and fetches each entitled workflow from its own source repository.

It is the lightweight, self-service complement to the managed delivery system
(`bestai-workflow-app` + `bestai-workflow-cloud`). It deliberately does **not**
do subscriptions, cloud sync, or MCP configuration.

## Audience (dual)

- **Primary:** an AI agent (Claude Code / Codex) that reads `README.md` and
  executes the Agent Runbook.
- **Secondary:** a human who runs `git clone && ./install.sh`.

## Repository layout

```
AgentQuickstart/
  README.md            # human intro + agent-executable runbook (the centerpiece)
  AGENTS.md            # pointer + rules for an agent that has cloned the repo
  CLAUDE.md            # Claude Code-facing pointer to AGENTS.md
  install.sh           # idempotent installer (bash 3.2-compatible)
  skills.json          # catalog ONLY: name -> source repo, ref, access, platforms
  docs/DESIGN.md       # this file
  LICENSE              # proprietary (all rights reserved, customer-use grant)
```

There is no `skills/` directory. This repo never contains workflow source.

## Key decisions

- **Standalone, not a front door to the desktop app.** Self-contained; the
  agent reads the README and runs the installer. No cloud dependency.
- **Skills are NOT vendored.** Each workflow lives in its **own** source
  repository and is fetched at install time. This repo holds only the catalog
  and installer. *(Reason: bundling source into a public repo would expose
  private/licensed workflows, and would let every client read workflows they
  have not purchased.)*
- **Access control is enforced at the GitHub layer.** Licensed workflows are
  private repositories. A client is issued a fine-grained, read-only token
  scoped to exactly the workflow repos they have purchased. The installer
  downloads each workflow via the GitHub tarball API using that token; a repo
  the token cannot reach returns `404` and is cleanly skipped. The token's
  repo scope **is** the entitlement — no separate entitlement service is
  needed for this lightweight path.
- **Public workflows need no token.** The `access` field per catalog entry is
  `public` or `licensed`; public repos download anonymously.
- **Target Claude Code and Codex.** Skills install into `~/.claude/skills/` and
  `~/.codex/skills/`, filtered by each skill's `platforms` and by which agents
  are detected. A real copy is written per agent (no symlinks — more robust
  across machines/platforms).

## Installer contract (`install.sh`)

- **Fetch model:** for each requested skill, resolve `repo`/`ref`/`access` from
  the catalog, download `GET /repos/{repo}/tarball/{ref}` (with the token when
  present), extract (a tarball has one top-level dir, stripped), validate a
  root `SKILL.md`, then install the payload into the target agent dirs.
- **Token source:** `$BESTAI_TOKEN`, else `~/.bestai/credentials` (`token=...`).
  Never stored or logged.
- **Idempotent:** re-running re-fetches and updates managed skills in place.
- **Safe:** a folder it created carries a `.bestai-managed` marker (recording
  source repo + ref + date). A same-named folder *without* that marker is
  treated as the user's own and is backed up to `<name>.bak-<timestamp>` —
  never clobbered.
- **Graceful degradation:** a licensed skill with no token, or a `404`/`403`,
  is reported per-skill and skipped; other skills still install. Non-zero exit
  if any requested skill failed.
- **Dependencies:** `curl` + `tar` (required); `jq` *or* `python3` to read the
  catalog. Written for bash 3.2 (macOS system bash): no associative arrays, no
  `mapfile`.
- **Testable in isolation:** `BESTAI_QS_PREFIX=/tmp/... ./install.sh` installs
  into a temp prefix instead of the real `$HOME`; the same prefix is used to
  resolve `~/.bestai/credentials`.
- Flags: `--list`, `--all`, `--claude-only`, `--codex-only`,
  `--uninstall NAME`, `--help`; positional args select specific skills.

## Catalog (`skills.json`)

```json
{
  "catalog_version": "2",
  "skills": [
    { "name": "wide-research", "title": "...", "description": "...",
      "repo": "BestAI-Labs/wide-research", "ref": "main",
      "access": "licensed", "platforms": ["claude-code", "codex"] }
  ]
}
```

Publishing a workflow = add an entry here and grant entitled tokens access to
its repo. No content is copied.

## Out of scope (YAGNI)

- Subscriptions, billing, a cloud entitlement service (the managed app owns
  these). Entitlement here is GitHub repo access.
- MCP configuration.
- A native Windows `install.ps1` (the runbook is cross-platform; on Windows the
  installer runs under Git Bash / WSL). Can be added later.
