#!/bin/bash
# Resolve the one authoritative local workspace routing plan.
#
# Success returns one primary capture target. --plan returns the complete JSON
# snapshot used by the caller, including selective-promotion metadata.
#
# Exit codes:
#   11 - cwd has no local workspace runtime (unconfigured)
#   13 - workspace runtime is malformed or conflicts with its trust binding
#   14 - a configured project/main target is missing or incomplete

set -uo pipefail

output_format="targets"
if [[ "${1:-}" == "--plan" ]]; then
  output_format="plan"
  shift
fi
[[ "$#" -eq 0 ]] || { echo >&2 "usage: wiki-resolve.sh [--plan]"; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_TOOL="${SCRIPT_DIR}/wiki_config.py"

set +e
error_file="$(mktemp)"
plan="$(python3 "${CONFIG_TOOL}" route-find --cwd "$(pwd -P)" --json 2>"${error_file}")"
rc=$?
set -e
if [[ "${rc}" -ne 0 ]]; then
  error="$(cat "${error_file}")"
  rm -f "${error_file}"
  printf '%s\n' "${error}" >&2
  if [[ "${rc}" -eq 3 ]]; then
    exit 11
  fi
  if grep -Eq 'not a complete wiki root|structural configuration not found|routing\.(project|main)_wiki' <<< "${error}"; then
    exit 14
  fi
  exit 13
fi
rm -f "${error_file}"

if [[ "${output_format}" == "plan" ]]; then
  printf '%s\n' "${plan}"
else
  python3 -c 'import json,sys; print(json.load(sys.stdin)["primary_wiki"])' <<< "${plan}"
fi
