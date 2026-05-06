#!/bin/bash
# wiki-resolve.sh — non-interactive wiki resolver.
#
# Determines which wiki(s) a chat-driven capture should target based on
# cwd's .wiki-config or .wiki-mode and the user's main-wiki pointer.
# Returns target wiki paths on stdout (one per line) and exit 0, OR
# exits with one of these specific codes signaling user input is needed:
#
#   10 — pointer missing or broken (need bootstrap or re-init)
#   11 — cwd unconfigured (need per-cwd prompt)
#   12 — config requires main but pointer is none/missing
#   13 — both .wiki-config AND .wiki-mode present at cwd (conflict)
#   14 — half-built wiki (cwd or pointer target missing required files)
#
# Cwd-only resolution: walks NO parents. The SessionStart hook handles
# its own walk-up via wiki_root_from_cwd; this resolver is for
# user-driven CLI commands (bin/wiki capture, bin/wiki ingest-now).
#
# Override $WIKI_POINTER_FILE for testing (default: ~/.wiki-pointer).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"

# Read main wiki pointer.
main_wiki=""
if [[ ! -e "${POINTER_FILE}" ]]; then
  exit 10
fi
# Follow symlinks for the pointer file itself
pointer_content="$(cat "${POINTER_FILE}" 2>/dev/null | tr -d '[:space:]')"
case "${pointer_content}" in
  "")
    exit 10  # Empty pointer file
    ;;
  none)
    main_wiki=""
    ;;
  *)
    if [[ ! -f "${pointer_content}/.wiki-config" ]]; then
      exit 10
    fi
    # Validate role = "main" on the pointer target
    if ! grep -q '^role = "main"' "${pointer_content}/.wiki-config"; then
      exit 10
    fi
    # Validate structure
    for required in schema.md index.md .wiki-pending; do
      if [[ ! -e "${pointer_content}/${required}" ]]; then
        exit 14
      fi
    done
    main_wiki="${pointer_content}"
    ;;
esac

# Read cwd state.
config_present=0
mode_present=0
[[ -f "$(pwd)/.wiki-config" ]] && config_present=1
[[ -f "$(pwd)/.wiki-mode" ]] && mode_present=1

# Conflict: both files present.
if [[ "${config_present}" == 1 && "${mode_present}" == 1 ]]; then
  exit 13
fi

wiki_root=""
fork=0

if [[ "${config_present}" == 1 ]]; then
  config="$(pwd)/.wiki-config"
  role=$(grep '^role = ' "${config}" | head -1 | sed 's/^role = "\(.*\)"/\1/')

  case "${role}" in
    main|project)
      wiki_root="$(pwd)"
      # Validate structure
      for required in schema.md index.md .wiki-pending; do
        if [[ ! -e "${wiki_root}/${required}" ]]; then
          exit 14
        fi
      done
      ;;
    project-pointer)
      sub=$(grep '^wiki = ' "${config}" | head -1 | sed 's/^wiki = "\(.*\)"/\1/')
      [[ -n "${sub}" ]] || exit 14
      # Resolve relative path against cwd
      if [[ "${sub}" == /* ]]; then
        wiki_root="${sub}"
      else
        wiki_root="$(pwd)/${sub#./}"
      fi
      # Validate structure
      [[ -f "${wiki_root}/.wiki-config" ]] || exit 14
      for required in schema.md index.md .wiki-pending; do
        if [[ ! -e "${wiki_root}/${required}" ]]; then
          exit 14
        fi
      done
      ;;
    *)
      # Unknown role — treat as conflict-equivalent
      exit 13
      ;;
  esac

  # Read fork_to_main (default false)
  if grep -q '^fork_to_main = true' "${config}"; then
    fork=1
  fi

elif [[ "${mode_present}" == 1 ]]; then
  mode_value=$(head -1 "$(pwd)/.wiki-mode" | tr -d '[:space:]')
  case "${mode_value}" in
    main-only)
      [[ -n "${main_wiki}" ]] || exit 12
      wiki_root="${main_wiki}"
      fork=0
      ;;
    *)
      # Unknown .wiki-mode value
      exit 13
      ;;
  esac
else
  # No config, no mode — unconfigured cwd.
  exit 11
fi

# Build target list.
if [[ "${fork}" == 1 ]]; then
  [[ -n "${main_wiki}" ]] || exit 12
  echo "${wiki_root}"
  if [[ "${main_wiki}" != "${wiki_root}" ]]; then
    echo "${main_wiki}"
  fi
else
  echo "${wiki_root}"
fi

exit 0
