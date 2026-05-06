#!/bin/bash
# Initialize a wiki directory (main or project).
# Idempotent: never overwrites existing files.
#
# Usage:
#   wiki-init.sh main <wiki_path>
#   wiki-init.sh project <wiki_path> <main_wiki_path>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

usage() {
  cat >&2 <<EOF
usage:
  wiki-init.sh main <wiki_path>
  wiki-init.sh project <wiki_path> <main_wiki_path>
EOF
  exit 1
}

[[ $# -ge 2 ]] || usage
role="$1"
wiki="$2"
main_path="${3:-}"

case "${role}" in
  main)
    [[ -z "${main_path}" ]] || { echo >&2 "main role takes no main_path arg"; usage; }
    ;;
  project)
    # main_path is optional — standalone project wikis are first-class in v2.4.
    ;;
  *) usage ;;
esac

# Python 3.11+ required for tomllib. Fail fast with a clear error if missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo >&2 "ERROR: python3 not found on PATH; karpathy-wiki requires Python 3.11+"
  exit 1
fi
if ! python3 --version 2>&1 | grep -qE 'Python 3\.(1[1-9]|[2-9][0-9])'; then
  cat >&2 <<'PYVER_EOF'
ERROR: karpathy-wiki requires Python 3.11+.

Install:
  macOS:  brew install python
  Linux:  apt install python3   (or your distro's equivalent)

Then re-run: bash scripts/wiki-init.sh
PYVER_EOF
  echo >&2 "Detected: $(python3 --version 2>&1)"
  exit 1
fi

mkdir -p "${wiki}"

# Directories (always ensure present)
for d in concepts entities queries ideas raw inbox .wiki-pending .wiki-pending/schema-proposals .locks .obsidian .raw-staging; do
  mkdir -p "${wiki}/${d}"
done

# Files — create only if missing.
today="$(date +%Y-%m-%d)"

if [[ ! -f "${wiki}/.wiki-config" ]]; then
  if [[ "${role}" == "main" ]]; then
    cat > "${wiki}/.wiki-config" <<EOF
role = "main"
created = "${today}"

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
EOF
  else
    {
      echo "role = \"project\""
      if [[ -n "${main_path}" ]]; then
        echo "main = \"${main_path}\""
      fi
      echo "created = \"${today}\""
      echo "fork_to_main = false"
      echo ""
      echo "[platform]"
      echo "agent_cli = \"claude\""
      echo "headless_command = \"claude -p\""
      echo ""
      echo "[settings]"
      echo "auto_commit = true"
    } > "${wiki}/.wiki-config"
  fi
fi

if [[ ! -f "${wiki}/index.md" ]]; then
  cat > "${wiki}/index.md" <<'EOF'
# Wiki Index

## Concepts
(empty)

## Entities
(empty)

## Queries
(empty)

## Ideas
(empty)
EOF
fi

if [[ ! -f "${wiki}/log.md" ]]; then
  cat > "${wiki}/log.md" <<EOF
# Wiki Log

## [${today}] init | wiki created
EOF
fi

if [[ ! -f "${wiki}/schema.md" ]]; then
  cat > "${wiki}/schema.md" <<EOF
# Wiki Schema

## Role
${role}

## Categories
- \`concepts/\` — ideas, patterns, principles (durable factual knowledge)
- \`entities/\` — specific tools, services, APIs
- \`queries/\` — filed Q&A worth keeping
- \`ideas/\` — forward-looking candidate work; requires \`status:\` and \`priority:\` frontmatter

## Tag Taxonomy (bounded)
Tags are evolved by the ingester; propose changes via schema edits, not ad-hoc.

## Numeric Thresholds
- Split a concept page: 2+ sources or 200+ lines
- Archive a raw source: referenced by 5+ wiki pages
- Restructure top-level category: 500+ pages within it
EOF
fi

if [[ ! -f "${wiki}/README.md" ]]; then
  cat > "${wiki}/README.md" <<EOF
# ${role} wiki — ${today}

This wiki is auto-managed by the karpathy-wiki plugin. Most of the time
you should not edit files directly — captures, ingestion, and page
writes happen through the plugin's tooling.

## Where to drop files

**\`inbox/\`** — the universal drop zone for ingestion. Put anything
that should become a wiki page here:

- Obsidian Web Clipper exports (configure your template's "Note
  location" to \`inbox\` and "Vault" to this wiki — see "Web Clipper
  setup" below).
- Research reports from subagents (the agent typically moves these
  for you).
- Manual file drops: downloaded articles, PDF→markdown exports,
  meeting notes.

After you drop a file, ingestion happens on the next agent session
start (silent), or immediately if you run \`wiki ingest-now <this-wiki-path>\`.

**Do NOT put files in \`raw/\`.** That directory is the ingester's
archive — every file there has a manifest entry tracking origin,
sha256, and which wiki pages reference it. If you put a file there
by accident, the next ingest will move it to \`inbox/\` and process
it normally (a WARN gets logged, but no data is lost).

## Web Clipper setup

In Obsidian Web Clipper settings → Templates → (your template) →
Location:

- **Note name:** \`{{title}}\` (or whatever filename pattern you prefer)
- **Note location:** \`inbox\`
- **Vault:** select this wiki's directory

That's it. Clip a page; the file lands in \`inbox/\`; next agent session
ingests it.

## Other top-level directories

- \`concepts/\`, \`entities/\`, \`queries/\`, \`ideas/\` — wiki content,
  written by the ingester. Editing pages directly is allowed but the
  ingester will eventually re-rate / re-link them.
- \`archive/\` — old content the ingester decided to retire.
- \`raw/\` — the ingester's archive (see above).
- \`.wiki-pending/\` — pending captures (transient).
- \`.locks/\` — concurrency primitives (transient).
- \`.raw-staging/\` — ingester staging area (transient).
- \`.manifest.json\`, \`.ingest.log\`, \`.ingest-issues.jsonl\` — machine
  state.

## Schema

See \`schema.md\` for the live category list, tag taxonomy, and
thresholds.
EOF
fi

if [[ ! -f "${wiki}/.manifest.json" ]]; then
  echo '{}' > "${wiki}/.manifest.json"
fi

if [[ ! -f "${wiki}/.gitignore" ]]; then
  cat > "${wiki}/.gitignore" <<'EOF'
# Runtime state (per-machine, never commit)
.locks/
.ingest.log
EOF
fi

# .obsidian/app.json — for Obsidian users; harmless if never opened
if [[ ! -f "${wiki}/.obsidian/app.json" ]]; then
  cat > "${wiki}/.obsidian/app.json" <<'EOF'
{
  "userIgnoreFilters": [
    ".wiki-pending/",
    ".locks/",
    ".ingest.log",
    ".manifest.json"
  ]
}
EOF
fi

# Git init — only if git available and wiki isn't already in a git repo
if command -v git >/dev/null 2>&1; then
  if ! (cd "${wiki}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    (cd "${wiki}" && git init >/dev/null && git add . && git commit -m "chore: init wiki" >/dev/null 2>&1 || true)
  fi
fi

echo "initialized: ${wiki} (${role})"
