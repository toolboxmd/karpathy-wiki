#!/bin/bash
# wiki-ingest-now.sh — on-demand drift-scan + drain.
#
# Usage:
#   wiki-ingest-now.sh                — uses the cwd-resolved initial wiki
#   wiki-ingest-now.sh <wiki-path>    — operates on the explicit path,
#                                       no resolver, no prompting

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

ingest_one_wiki() {
  local wiki="$1"
  [[ -d "${wiki}" ]] || { echo >&2 "wiki ingest-now: wiki path does not exist: ${wiki}"; return 1; }
  [[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "wiki ingest-now: not a wiki (no .wiki-config): ${wiki}"; return 1; }

  # Verify structure
  for required in schema.md index.md .wiki-pending; do
    if [[ ! -e "${wiki}/${required}" ]]; then
      echo >&2 "wiki ingest-now: half-built wiki — missing ${required} at ${wiki}"
      return 1
    fi
  done

  # Manual activation uses the same scanner and bounded dispatcher as every
  # other mode. It never depends on a SessionStart hook being available.
  python3 "${SCRIPT_DIR}/wiki_dispatch.py" tick \
    --wiki "${wiki}" --source manual --scan
}

if [[ $# -eq 0 ]]; then
  # No-arg: use cwd resolver
  resolver_out="$(bash "${SCRIPT_DIR}/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0 || resolver_exit=$?

  if [[ "${resolver_exit}" != 0 ]]; then
    echo >&2 "wiki ingest-now: resolver exit ${resolver_exit}; cannot determine target wiki."
    case "${resolver_exit}" in
      10) echo >&2 "  pointer missing — run 'wiki init-main' first" ;;
      11) echo >&2 "  cwd unconfigured — run 'wiki use project|main|both' first" ;;
      12) echo >&2 "  cwd requires a main wiki but pointer is none/missing" ;;
      13) echo >&2 "  cwd has both .wiki-config and .wiki-mode (conflict); rm one" ;;
      14) echo >&2 "  half-built wiki at cwd or pointer target" ;;
    esac
    exit 1
  fi

  while IFS= read -r wiki_path; do
    [[ -n "${wiki_path}" ]] || continue
    ingest_one_wiki "${wiki_path}" || exit 1
  done <<< "${resolver_out}"
else
  # Explicit path — no resolver, no prompting
  ingest_one_wiki "$1" || exit 1
fi

exit 0
