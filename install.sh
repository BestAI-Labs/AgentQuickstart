#!/usr/bin/env bash
#
# AgentQuickstart installer
# ------------------------------------------------------------------------------
# Installs BestAI Labs workflow skills into the local skill directories used by
# Claude Code (~/.claude/skills) and/or Codex (~/.codex/skills).
#
# Skills are NOT bundled in this repository. Each workflow lives in its own
# source repository and is fetched at install time. Licensed workflows live in
# PRIVATE repositories and require a BestAI access token: a client whose token
# does not grant access to a skill's repository simply cannot install it.
#
# Design goals:
#   - Idempotent: re-running produces the same end state.
#   - Safe: never silently overwrites a skill directory it does not manage;
#           unmanaged same-named directories are backed up first.
#   - Access-controlled: licensed skills need a token; no access => not installed.
#
# Token resolution (first match wins):
#   1. $BESTAI_TOKEN
#   2. ~/.bestai/credentials   (a line: token=ghp_xxx or token=github_pat_xxx)
#
# Usage:
#   ./install.sh                   Install every catalog skill for every detected agent
#   ./install.sh wide-research     Install only the named skill(s)
#   ./install.sh --all             Install every catalog skill (explicit)
#   ./install.sh --list            List catalog skills and exit
#   ./install.sh --claude-only     Target Claude Code (~/.claude/skills) only
#   ./install.sh --codex-only      Target Codex (~/.codex/skills) only
#   ./install.sh --uninstall NAME  Remove a managed skill (refuses unmanaged dirs)
#   ./install.sh --help
#
# Testing without touching the real HOME:
#   BESTAI_QS_PREFIX=/tmp/aqs-test BESTAI_TOKEN=xxx ./install.sh
# ------------------------------------------------------------------------------
set -euo pipefail

MARKER=".bestai-managed"
API="https://api.github.com"
CATALOG_URL="https://raw.githubusercontent.com/BestAI-Labs/AgentQuickstart/main/skills.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install prefix. Defaults to $HOME; override for testing.
PREFIX="${BESTAI_QS_PREFIX:-$HOME}"
CLAUDE_ROOT="$PREFIX/.claude"
CODEX_ROOT="$PREFIX/.codex"

# Catalog location: local file next to this script, or a downloaded copy.
CATALOG="${BESTAI_QS_CATALOG:-$SCRIPT_DIR/skills.json}"

# ----- output helpers ---------------------------------------------------------
c_reset=''; c_bold=''; c_green=''; c_yellow=''; c_red=''; c_dim=''
if [ -t 1 ]; then
  c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_green=$'\033[32m'
  c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_dim=$'\033[2m'
fi
info()    { printf '%s\n' "$*"; }
ok()      { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn()    { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
err()     { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
section() { printf '\n%s%s%s\n' "$c_bold" "$*" "$c_reset"; }
timestamp() { date +%Y%m%d-%H%M%S; }

usage() {
  cat <<'EOF'
AgentQuickstart installer — install BestAI Labs workflow skills locally.

Skills are fetched from their own source repositories. Licensed workflows are
private and need a BestAI token (set BESTAI_TOKEN or ~/.bestai/credentials).

Usage:
  ./install.sh                  Install every catalog skill for every detected agent
  ./install.sh wide-research    Install only the named skill(s)
  ./install.sh --all            Install every catalog skill (explicit)
  ./install.sh --list           List catalog skills and exit
  ./install.sh --claude-only    Target Claude Code (~/.claude/skills) only
  ./install.sh --codex-only     Target Codex (~/.codex/skills) only
  ./install.sh --uninstall NAME Remove a managed skill (refuses unmanaged dirs)
  ./install.sh --help

Testing without touching the real HOME:
  BESTAI_QS_PREFIX=/tmp/aqs-test BESTAI_TOKEN=xxx ./install.sh
EOF
}

# ----- dependency checks ------------------------------------------------------
require_deps() {
  local missing=""
  command -v curl >/dev/null 2>&1 || missing="$missing curl"
  command -v tar  >/dev/null 2>&1 || missing="$missing tar"
  if [ -n "$missing" ]; then
    err "missing required command(s):$missing"; exit 1
  fi
  if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    err "need 'jq' or 'python3' to read the catalog. Install one, or follow the manual steps in README.md."
    exit 1
  fi
}

# ----- token resolution -------------------------------------------------------
resolve_token() {
  if [ -n "${BESTAI_TOKEN:-}" ]; then printf '%s' "$BESTAI_TOKEN"; return; fi
  local cred="$PREFIX/.bestai/credentials"
  if [ -f "$cred" ]; then
    sed -n 's/^[[:space:]]*token[[:space:]]*=[[:space:]]*//p' "$cred" | head -n1
    return
  fi
  printf ''
}

# ----- catalog access ---------------------------------------------------------
# Ensure $CATALOG points at a readable file; download it if necessary.
ensure_catalog() {
  if [ -f "$CATALOG" ]; then return; fi
  local tmp; tmp="$(mktemp)"
  if curl -fsSL -o "$tmp" "$CATALOG_URL"; then
    CATALOG="$tmp"
  else
    err "no local skills.json and could not download the catalog from $CATALOG_URL"
    exit 1
  fi
}

# Emit one TSV row per skill: name<TAB>repo<TAB>ref<TAB>access<TAB>platforms<TAB>title
catalog_tsv() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.skills[] | [.name, .repo, (.ref // "main"), (.access // "public"), ((.platforms // []) | join(",")), (.title // .name)] | @tsv' "$CATALOG"
  else
    python3 - "$CATALOG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for s in d.get("skills", []):
    print("\t".join([
        s.get("name", ""),
        s.get("repo", ""),
        s.get("ref", "main") or "main",
        s.get("access", "public") or "public",
        ",".join(s.get("platforms", [])),
        s.get("title", s.get("name", "")),
    ]))
PY
  fi
}

catalog_names() { catalog_tsv | cut -f1; }
catalog_row()   { catalog_tsv | awk -F'\t' -v n="$1" '$1==n {print; exit}'; }

do_list() {
  ensure_catalog
  section "Available workflows (catalog)"
  local name repo ref access platforms title
  while IFS=$'\t' read -r name repo ref access platforms title; do
    [ -n "$name" ] || continue
    printf '  %s%-16s%s %s[%s]%s %s\n' \
      "$c_bold" "$name" "$c_reset" "$c_dim" "$access" "$c_reset" "$title"
  done < <(catalog_tsv)
  printf '\nLicensed workflows need a BestAI token (BESTAI_TOKEN or ~/.bestai/credentials).\n'
  printf 'Install all:  %s./install.sh%s   Install one:  %s./install.sh <name>%s\n' \
    "$c_dim" "$c_reset" "$c_dim" "$c_reset"
}

# ----- install primitives -----------------------------------------------------
is_managed() { [ -f "$1/$MARKER" ]; }

write_marker() {
  local dest="$1" name="$2" repo="$3" ref="$4"
  cat > "$dest/$MARKER" <<EOF
# This skill is managed by BestAI AgentQuickstart. Remove it with the installer's
# --uninstall flag, or by deleting this directory.
skill = $name
repo = $repo
ref = $ref
installed_at = $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

# Copy an extracted skill payload into one target skills directory.
install_into() {
  local name="$1" target_skills_dir="$2" label="$3" src="$4" repo="$5" ref="$6"
  local dest="$target_skills_dir/$name"
  mkdir -p "$target_skills_dir"

  local verb="installed"
  if [ -e "$dest" ]; then
    if is_managed "$dest"; then
      rm -rf "$dest"; verb="updated"
    else
      local backup; backup="$dest.bak-$(timestamp)"
      mv "$dest" "$backup"
      warn "$label: existing unmanaged '$name' backed up -> $(basename "$backup")"
    fi
  fi
  cp -R "$src" "$dest"
  write_marker "$dest" "$name" "$repo" "$ref"
  ok "$label: $name $verb"
}

# Should we install $skill_platforms into $agent? (agent detected AND supported)
agent_supported() {
  local agent="$1" platforms="$2" key
  case "$agent" in
    claude) [ "$target_claude" -eq 1 ] || return 1; key="claude-code" ;;
    codex)  [ "$target_codex"  -eq 1 ] || return 1; key="codex" ;;
    *) return 1 ;;
  esac
  case ",$platforms," in *",$key,"*) return 0 ;; *) return 1 ;; esac
}

# Fetch + extract + install a single skill. Returns non-zero on failure.
install_skill() {
  local name="$1"
  local row repo ref access platforms title
  row="$(catalog_row "$name")"
  if [ -z "$row" ]; then err "unknown skill: '$name' (try ./install.sh --list)"; return 1; fi
  IFS=$'\t' read -r name repo ref access platforms title <<<"$row"
  ref="${ref:-main}"

  if [ "$access" = "licensed" ] && [ -z "$TOKEN" ]; then
    err "$name is a licensed workflow — set BESTAI_TOKEN or ~/.bestai/credentials. Contact BestAI Labs."
    return 1
  fi

  # Download the source repo tarball.
  local tgz; tgz="$(mktemp)"
  local code url="$API/repos/$repo/tarball/$ref"
  if [ -n "$TOKEN" ]; then
    code="$(curl -sSL -o "$tgz" -w '%{http_code}' \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$url" || echo 000)"
  else
    code="$(curl -sSL -o "$tgz" -w '%{http_code}' \
      -H "Accept: application/vnd.github+json" "$url" || echo 000)"
  fi
  case "$code" in
    200) : ;;
    404) err "$name: cannot access $repo (not licensed, token lacks access, or ref '$ref' missing)."; rm -f "$tgz"; return 1 ;;
    401|403) err "$name: access denied to $repo (HTTP $code) — check your BestAI token."; rm -f "$tgz"; return 1 ;;
    *) err "$name: download failed (HTTP $code) from $repo."; rm -f "$tgz"; return 1 ;;
  esac

  # Extract; a GitHub tarball wraps everything in a single top-level directory.
  local ex; ex="$(mktemp -d)"
  if ! tar -xzf "$tgz" -C "$ex"; then
    err "$name: could not extract archive."; rm -f "$tgz"; rm -rf "$ex"; return 1
  fi
  rm -f "$tgz"
  local payload; payload="$(find "$ex" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [ -z "$payload" ] || [ ! -f "$payload/SKILL.md" ]; then
    err "$name: $repo does not look like a skill (no SKILL.md at its root)."; rm -rf "$ex"; return 1
  fi

  # Defensive cleanup of anything that must not be installed.
  rm -rf "$payload/.git"
  find "$payload" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find "$payload" -name '*.pyc' -delete 2>/dev/null || true
  find "$payload" -name '.DS_Store' -delete 2>/dev/null || true

  local did=0
  if agent_supported claude "$platforms"; then
    install_into "$name" "$CLAUDE_ROOT/skills" "Claude Code" "$payload" "$repo" "$ref"; did=1
  fi
  if agent_supported codex "$platforms"; then
    install_into "$name" "$CODEX_ROOT/skills" "Codex" "$payload" "$repo" "$ref"; did=1
  fi
  rm -rf "$ex"

  if [ "$did" -eq 0 ]; then
    warn "$name: no enabled target agent supports it (skill platforms: $platforms)"
    return 1
  fi
  return 0
}

uninstall_skill() {
  local name="$1" any=0 label dir dest
  for spec in "claude::$CLAUDE_ROOT/skills" "codex::$CODEX_ROOT/skills"; do
    label="${spec%%::*}"; dir="${spec##*::}"; dest="$dir/$name"
    [ -e "$dest" ] || continue
    if is_managed "$dest"; then
      rm -rf "$dest"; ok "$label: removed managed '$name'"; any=1
    else
      warn "$label: '$name' is not managed by AgentQuickstart -> left untouched"
    fi
  done
  [ "$any" -eq 1 ] || warn "nothing to uninstall for '$name'"
}

# ----- argument parsing -------------------------------------------------------
WANT_CLAUDE=auto
WANT_CODEX=auto
DO_LIST=0
UNINSTALL_NAME=""
REQUESTED=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    --list)        DO_LIST=1 ;;
    --all)         : ;;
    --claude-only) WANT_CLAUDE=yes; WANT_CODEX=no ;;
    --codex-only)  WANT_CODEX=yes;  WANT_CLAUDE=no ;;
    --uninstall)   shift; UNINSTALL_NAME="${1:-}";
                   [ -n "$UNINSTALL_NAME" ] || { err "--uninstall needs a skill name"; exit 2; } ;;
    --*)           err "unknown option: $1"; usage; exit 2 ;;
    *)             REQUESTED+=("$1") ;;
  esac
  shift
done

require_deps
TOKEN="$(resolve_token)"

if [ "$DO_LIST" -eq 1 ]; then do_list; exit 0; fi
if [ -n "$UNINSTALL_NAME" ]; then uninstall_skill "$UNINSTALL_NAME"; exit 0; fi

ensure_catalog

# Resolve which skills to install.
AVAILABLE=()
while IFS= read -r s; do [ -n "$s" ] && AVAILABLE+=("$s"); done < <(catalog_names)
if [ "${#AVAILABLE[@]}" -eq 0 ]; then err "catalog is empty: $CATALOG"; exit 1; fi

TO_INSTALL=()
if [ "${#REQUESTED[@]}" -eq 0 ]; then
  TO_INSTALL=("${AVAILABLE[@]}")
else
  for want in "${REQUESTED[@]}"; do
    found=0
    for have in "${AVAILABLE[@]}"; do [ "$want" = "$have" ] && found=1 && break; done
    if [ "$found" -eq 1 ]; then TO_INSTALL+=("$want")
    else err "unknown skill: '$want' (try ./install.sh --list)"; exit 1; fi
  done
fi

# Resolve target agents.
target_claude=0
target_codex=0
case "$WANT_CLAUDE" in yes) target_claude=1 ;; auto) [ -d "$CLAUDE_ROOT" ] && target_claude=1 ;; esac
case "$WANT_CODEX"  in yes) target_codex=1  ;; auto) [ -d "$CODEX_ROOT"  ] && target_codex=1  ;; esac
if [ "$target_claude" -eq 0 ] && [ "$target_codex" -eq 0 ]; then
  warn "neither ~/.claude nor ~/.codex detected; installing for both."
  target_claude=1; target_codex=1
fi

# ----- run --------------------------------------------------------------------
section "AgentQuickstart — installing BestAI workflows"
info "${c_dim}prefix:${c_reset}  $PREFIX"
targets_desc=""
[ "$target_claude" -eq 1 ] && targets_desc="${targets_desc}Claude Code "
[ "$target_codex" -eq 1 ]  && targets_desc="${targets_desc}Codex "
info "${c_dim}targets:${c_reset} ${targets_desc:-none}"
info "${c_dim}token:${c_reset}   $( [ -n "$TOKEN" ] && echo present || echo none )"
info "${c_dim}skills:${c_reset}  ${TO_INSTALL[*]}"
echo

failed=0
for name in "${TO_INSTALL[@]}"; do
  install_skill "$name" || failed=$((failed + 1))
done

section "Done."
if [ "$failed" -gt 0 ]; then
  warn "$failed workflow(s) could not be installed (see messages above)."
fi
info "Restart your agent (or start a new session) so it picks up the new skills."
[ "$target_claude" -eq 1 ] && info "  Claude Code: $CLAUDE_ROOT/skills"
[ "$target_codex" -eq 1 ]  && info "  Codex:       $CODEX_ROOT/skills"
[ "$failed" -eq 0 ]
