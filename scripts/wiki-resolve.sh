#!/bin/bash
# wiki-resolve.sh — non-interactive wiki resolver.
#
# Determines which wiki a chat-driven capture should target based on
# cwd's .wiki-config or .wiki-mode and the user's main-wiki pointer.
# Returns the one initial target on stdout and exit 0. With --plan, returns a
# JSON routing plan including selective-promotion metadata. Otherwise it exits
# with one of these specific codes signaling user input is needed:
#
#   10 — pointer missing or broken (need bootstrap or re-init)
#   11 — cwd unconfigured (need per-cwd prompt)
#   12 — config requires main but pointer is none/missing
#   13 — both .wiki-config AND .wiki-mode present at cwd (conflict)
#   14 — half-built wiki (cwd or pointer target missing required files)
#
# Walks up from cwd looking for the first dir containing .wiki-config or
# .wiki-mode (project-config marker). Stops at ${HOME} (exclusive) and at
# /. If no marker is found in the walk-up range, falls back to pwd and
# returns exit 11 (unconfigured).
#
# Walk-up is bounded to the user tree so a project wiki at ~/proj/A is
# discovered from ~/proj/A/sub/dir/, but a cwd inside an unrelated project
# does not leak into ${HOME}/wiki/ (paired #11/#9 fix, 0.2.8).
#
# Override $WIKI_POINTER_FILE for testing (default: ~/.wiki-pointer).

set -uo pipefail

output_format="targets"
if [[ "${1:-}" == "--plan" ]]; then
  output_format="plan"
  shift
fi
[[ "$#" -eq 0 ]] || { echo >&2 "usage: wiki-resolve.sh [--plan]"; exit 2; }

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

# Walk up from pwd looking for a dir with .wiki-config or .wiki-mode.
# Stop at ${HOME} (exclusive) and at /. cwd_base is where we found a
# marker (or pwd if no marker found in range — falls through to exit 11).
cwd_base="$(pwd)"
_scan="$(pwd)"
while [[ "${_scan}" != "/" && "${_scan}" != "${HOME}" ]]; do
  if [[ -f "${_scan}/.wiki-config" || -f "${_scan}/.wiki-mode" ]]; then
    cwd_base="${_scan}"
    break
  fi
  _scan="$(dirname "${_scan}")"
done

config_present=0
mode_present=0
[[ -f "${cwd_base}/.wiki-config" ]] && config_present=1
[[ -f "${cwd_base}/.wiki-mode" ]] && mode_present=1

# Conflict: both files present.
if [[ "${config_present}" == 1 && "${mode_present}" == 1 ]]; then
  exit 13
fi

wiki_root=""
fork=0
resolved_role=""

if [[ "${config_present}" == 1 ]]; then
  config="${cwd_base}/.wiki-config"
  role=$(grep '^role = ' "${config}" | head -1 | sed 's/^role = "\(.*\)"/\1/')

  case "${role}" in
    main|project)
      resolved_role="${role}"
      wiki_root="${cwd_base}"
      # Validate structure
      for required in schema.md index.md .wiki-pending; do
        if [[ ! -e "${wiki_root}/${required}" ]]; then
          exit 14
        fi
      done
      # Routing for an actual wiki root is per user/machine. A legacy
      # tracked value is honored only until that wiki is explicitly migrated.
      if [[ "$(wiki_runtime_config_get "${wiki_root}" routing.fork_to_main 2>/dev/null || true)" == "true" ]]; then
        fork=1
      elif grep -q '^fork_to_main = true' "${config}"; then
        fork=1
      fi
      ;;
    project-pointer)
      resolved_role="project"
      sub=$(grep '^wiki = ' "${config}" | head -1 | sed 's/^wiki = "\(.*\)"/\1/')
      [[ -n "${sub}" ]] || exit 14
      # Resolve relative path against cwd_base (the dir holding .wiki-config)
      if [[ "${sub}" == /* ]]; then
        wiki_root="${sub}"
      else
        wiki_root="${cwd_base}/${sub#./}"
      fi
      # Validate structure
      [[ -f "${wiki_root}/.wiki-config" ]] || exit 14
      for required in schema.md index.md .wiki-pending; do
        if [[ ! -e "${wiki_root}/${required}" ]]; then
          exit 14
        fi
      done
      # A project pointer belongs to the project checkout, so its routing
      # choice intentionally remains in the tracked pointer file.
      if grep -q '^fork_to_main = true' "${config}"; then
        fork=1
      fi
      ;;
    *)
      # Unknown role — treat as conflict-equivalent
      exit 13
      ;;
  esac

elif [[ "${mode_present}" == 1 ]]; then
  mode_value=$(head -1 "${cwd_base}/.wiki-mode" | tr -d '[:space:]')
  case "${mode_value}" in
    main-only)
      [[ -n "${main_wiki}" ]] || exit 12
      wiki_root="${main_wiki}"
      resolved_role="main"
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

# Validate the promotion target, but never fan out the original capture.
if [[ "${fork}" == 1 ]]; then
  [[ -n "${main_wiki}" ]] || exit 12
  [[ "${resolved_role}" == "project" ]] || exit 13
fi

if [[ "${output_format}" == "plan" ]]; then
  promotion_policy="none"
  mode="${resolved_role}"
  plan_main=""
  if [[ "${fork}" == 1 ]]; then
    promotion_policy="selective"
    mode="both"
    plan_main="${main_wiki}"
  fi
  python3 - "${mode}" "${wiki_root}" "${promotion_policy}" "${plan_main}" <<'PYEOF'
import json
import sys

mode, primary, policy, main = sys.argv[1:]
print(json.dumps({
    "mode": mode,
    "primary_wiki": primary,
    "promotion_policy": policy,
    "main_wiki": main or None,
}))
PYEOF
else
  echo "${wiki_root}"
fi

exit 0
