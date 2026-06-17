# BestAI AgentQuickstart

One command to install **BestAI Labs workflows** into your local AI coding agent.

BestAI Labs builds workflows (packaged as *skills*) that give Claude Code and
Codex new, repeatable capabilities — for example long-form **Web Research**.
This repository is the quickstart: point your agent at it, and it creates the
right folders and installs the workflows you are entitled to.

This repo contains only a **catalog** and an **installer**. The workflows
themselves are **not** stored here — each one lives in its own source
repository and is fetched at install time. Licensed workflows live in private
repositories, so a client installs only the workflows their BestAI token can
reach.

> Want the fully managed experience (login, subscriptions, auto-sync, MCP
> config)? That is the **BestAI Workflow App**. AgentQuickstart is the
> lightweight, self-service path.

## What you get

| Workflow | Access | What it does |
| --- | --- | --- |
| **wide-research** (Web Research) | licensed | Long, multi-hour, breadth-first research on one topic — fans out parallel sub-agents wave after wave and produces a verified, cited report plus a living document. |

Run `./install.sh --list` for the current catalog.

- **Public** workflows install for anyone, no token needed.
- **Licensed** workflows live in private repos and require a BestAI access
  token. No token (or a token without access) means that workflow is simply
  skipped — nothing else breaks.

## Your BestAI access token

To install licensed workflows, provide the token BestAI Labs issued you, in
either of these ways:

```bash
# Option A — environment variable
export BESTAI_TOKEN=github_pat_xxx

# Option B — credentials file (recommended for repeat use)
mkdir -p ~/.bestai
printf 'token=github_pat_xxx\n' > ~/.bestai/credentials
chmod 600 ~/.bestai/credentials
```

The token is a read-only GitHub access token scoped to exactly the workflow
repositories you are licensed for. It is never written anywhere by the
installer. Don't have one? Contact BestAI Labs.

## Install with your AI agent (recommended)

Paste this into your Claude Code or Codex session:

> Read `https://raw.githubusercontent.com/BestAI-Labs/AgentQuickstart/main/README.md`
> and follow the **Agent Runbook** section to install the BestAI workflows.
> Install all workflows I am entitled to.

Your agent will fetch the installer and run it. That is the whole setup.

## Install from the terminal

```bash
git clone https://github.com/BestAI-Labs/AgentQuickstart.git
cd AgentQuickstart
export BESTAI_TOKEN=github_pat_xxx   # only needed for licensed workflows
./install.sh                 # install everything you are entitled to
# or
./install.sh wide-research   # install a single workflow
./install.sh --list          # see the catalog
```

Then start a new agent session so the skills are picked up.

## What gets created

The installer writes skill folders into the standard locations your agent
already reads:

- **Claude Code:** `~/.claude/skills/<skill-name>/`
- **Codex:** `~/.codex/skills/<skill-name>/`

It only targets the agents it detects (it looks for `~/.claude` and `~/.codex`).
Each installed skill is a self-contained folder (`SKILL.md` plus supporting
files) and a small `.bestai-managed` marker recording the source repo, so the
installer can update or remove it later without touching anything you created
yourself.

Nothing else on your system is modified — no global config, no shell rc files.

## How it works

```
your token  ──┐
              ▼
   skills.json (catalog: name → source repo, access)
              │
   for each entitled workflow:
     GitHub API tarball of its OWN repo  ──►  extract  ──►
        ~/.claude/skills/<name>/  and/or  ~/.codex/skills/<name>/
```

Access control is enforced by GitHub: licensed workflows are private repos, and
the tarball download only succeeds for a token that has been granted access.
A client without access gets a clean "cannot access" message and that workflow
is skipped.

## Agent Runbook

*This section is written for an AI agent. If you have been asked to install
BestAI workflows, follow these steps. They are idempotent and safe to re-run.*

**Goal:** install the BestAI workflow skills the user is entitled to into their
local Claude Code and/or Codex skill directories.

**Step 1 — Detect which agents are present.**

```bash
ls -d ~/.claude ~/.codex 2>/dev/null
```

`~/.claude` ⇒ Claude Code. `~/.codex` ⇒ Codex. Install into whichever exist.

**Step 2 — Make sure a token is available** (only needed for licensed
workflows). Check for one and ask the user if it is missing:

```bash
[ -n "$BESTAI_TOKEN" ] || sed -n 's/^token *= *//p' ~/.bestai/credentials 2>/dev/null
```

**Step 3 — Get the installer.**

```bash
git clone --depth 1 https://github.com/BestAI-Labs/AgentQuickstart.git /tmp/agentquickstart
cd /tmp/agentquickstart
```

**Step 4 — Install (preferred: run the installer).**

```bash
./install.sh                 # all entitled workflows, all detected agents
./install.sh wide-research   # or a specific workflow
```

The installer fetches each workflow from its own repository, is idempotent, and
backs up (never overwrites) any *unmanaged* skill folder of the same name.

**Step 4, alternative — install one workflow by hand** (if you cannot run the
script). Look up the workflow's `repo` in `skills.json`, then:

```bash
NAME=wide-research
REPO=BestAI-Labs/wide-research          # from skills.json
curl -fsSL -H "Authorization: Bearer $BESTAI_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     -o /tmp/$NAME.tgz \
     https://api.github.com/repos/$REPO/tarball/main
mkdir -p /tmp/$NAME && tar -xzf /tmp/$NAME.tgz -C /tmp/$NAME --strip-components=1
# then copy into each detected agent dir, without overwriting an existing
# folder you did not create:
for DIR in ~/.claude ~/.codex; do
  [ -d "$DIR" ] || continue
  mkdir -p "$DIR/skills"
  [ -e "$DIR/skills/$NAME" ] && mv "$DIR/skills/$NAME" "$DIR/skills/$NAME.bak-$(date +%Y%m%d-%H%M%S)"
  cp -R /tmp/$NAME "$DIR/skills/$NAME"
done
```

A `404` from the tarball download means the token cannot access that workflow —
the user is not licensed for it. Report that and move on.

**Step 5 — Verify.**

```bash
ls ~/.claude/skills/ ~/.codex/skills/ 2>/dev/null
```

Confirm each requested skill folder exists and contains `SKILL.md`.

**Step 6 — Report to the user** which workflows were installed, into which
agent directories, which (if any) were skipped for lack of access, and that
they should start a new agent session.

## Updating

Re-run the installer (or the runbook). Managed skills are re-fetched and
updated in place:

```bash
cd AgentQuickstart && git pull && ./install.sh
```

## Uninstalling

```bash
./install.sh --uninstall wide-research
```

The installer only removes skill folders it manages (those carrying the
`.bestai-managed` marker). Anything you created yourself is left untouched.

## Safety & transparency

- The installer is a single, readable `install.sh`. It makes no network calls
  except fetching workflow archives from GitHub.
- Your token is read from `BESTAI_TOKEN` or `~/.bestai/credentials` and is never
  stored, logged, or transmitted anywhere but GitHub.
- It only writes skill folders under `~/.claude/skills` and `~/.codex/skills`,
  and never overwrites a folder it does not manage — same-named unmanaged
  folders are backed up with a timestamp.

## For maintainers

- Each workflow is its **own repository**; nothing is vendored into this repo.
- `skills.json` is the catalog. To publish a workflow, add an entry:
  ```json
  { "name": "<slug>", "title": "...", "description": "...",
    "repo": "BestAI-Labs/<repo>", "ref": "main",
    "access": "licensed", "platforms": ["claude-code", "codex"] }
  ```
  Use `"access": "public"` only for repositories that are public.
- Entitlement is managed at the GitHub layer: grant a client's fine-grained
  token read access to the workflow repositories they have purchased.
- Design notes: `docs/DESIGN.md`.
