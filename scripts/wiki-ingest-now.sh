#!/bin/bash
# wiki-ingest-now.sh — on-demand drift-scan + drain.
#
# Usage:
#   wiki-ingest-now.sh                — uses cwd-resolved wiki(s)
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

  # Run the same drift-scan + drain logic as SessionStart, but inline.
  # Since the SessionStart hook is a single script, we invoke it with
  # cwd set to the wiki AND override env vars to make it scan THIS wiki.
  # The hook keeps walk-up via wiki_root_from_cwd, which from inside the
  # wiki dir will find the wiki itself.
  ( cd "${wiki}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${REPO_ROOT}/hooks/session-start" >/dev/null 2>&1 )
}

if [[ $# -eq 0 ]]; then
  # No-arg: use cwd resolver
  resolver_out="$(bash "${SCRIPT_DIR}/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0 || resolver_exit=$?

  if [[ "${resolver_exit}" != 0 ]]; then
    echo >&2 "wiki ingest-now: resolver exit ${resolver_exit}; cannot determine target wiki(s)."
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
