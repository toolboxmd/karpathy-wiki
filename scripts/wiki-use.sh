#!/bin/bash
# wiki-use.sh: make one complete local project|main|both routing choice.
# The authoritative record is a private workspace runtime outside the checkout.
# Tracked pointers and legacy .wiki-mode files never authorize routing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"
CONFIG_TOOL="${SCRIPT_DIR}/wiki_config.py"

mode="${1:-}"
[[ -n "${mode}" ]] || { echo >&2 "usage: wiki use project|main|both"; exit 1; }

canonical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

read_main_wiki() {
  local value
  value="$(head -1 "${POINTER_FILE}" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -n "${value}" && "${value}" != "none" ]] || return 1
  canonical_dir "${value}" || return 1
}

wiki_role() {
  sed -n 's/^role = "\([^"]*\)"$/\1/p' "$1/.wiki-config" 2>/dev/null | head -1
}

valid_wiki_role() {
  local root="$1" expected="$2" required
  [[ "$(wiki_role "${root}")" == "${expected}" ]] || return 1
  for required in schema.md index.md .wiki-pending; do
    [[ -e "${root}/${required}" ]] || return 1
  done
}

cwd="$(pwd -P)"
workspace="${cwd}"
existing_plan="$(python3 "${CONFIG_TOOL}" route-find --cwd "${cwd}" --json 2>/dev/null || true)"
if [[ -n "${existing_plan}" ]]; then
  workspace="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["workspace_root"])' <<< "${existing_plan}")"
elif [[ "$(wiki_role "${cwd}")" == "project" ]]; then
  workspace="$(git -C "${cwd}" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "${cwd}")"
  workspace="$(canonical_dir "${workspace}")"
fi

project=""
if [[ "$(wiki_role "${cwd}")" == "project" ]]; then
  project="${cwd}"
elif valid_wiki_role "${workspace}/wiki" project; then
  project="$(canonical_dir "${workspace}/wiki")"
fi

main=""
if [[ "${mode}" == "main" || "${mode}" == "both" ]]; then
  main="$(read_main_wiki)" || {
    echo >&2 "wiki use ${mode}: main wiki pointer is missing or invalid"
    exit 1
  }
  valid_wiki_role "${main}" main || {
    echo >&2 "wiki use ${mode}: main wiki pointer does not target a complete role=main wiki"
    exit 1
  }
fi

if [[ "${mode}" == "project" || "${mode}" == "both" ]]; then
  if [[ -z "${project}" ]]; then
    project="${workspace}/wiki"
    bash "${SCRIPT_DIR}/wiki-init.sh" project "${project}" "${main}" >/dev/null || {
      echo >&2 "wiki use ${mode}: could not initialize ${project}"
      exit 1
    }
    project="$(canonical_dir "${project}")"
  fi
  valid_wiki_role "${project}" project || {
    echo >&2 "wiki use ${mode}: project target is not a complete role=project wiki"
    exit 1
  }
fi

route_args=(route-set --workspace "${workspace}" --mode "${mode}")
[[ -n "${project}" ]] && route_args+=(--project-wiki "${project}")
[[ -n "${main}" ]] && route_args+=(--main-wiki "${main}")
python3 "${CONFIG_TOOL}" "${route_args[@]}" >/dev/null || {
  echo >&2 "wiki use ${mode}: could not persist the local workspace runtime"
  exit 1
}

case "${mode}" in
  project) echo "wiki use project: captures go to ${project}" ;;
  main) echo "wiki use main: captures go to ${main}" ;;
  both) echo "wiki use both: captures go to ${project}; reusable knowledge may promote to ${main}" ;;
  *)
    echo >&2 "wiki use: unknown mode '${mode}'; valid: project|main|both"
    exit 1
    ;;
esac
