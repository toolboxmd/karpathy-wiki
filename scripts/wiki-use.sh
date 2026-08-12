#!/bin/bash
# wiki-use.sh — change per-cwd wiki mode.
#
# Subcommands:
#   wiki-use.sh project   — write .wiki-config (project-pointer, fork=false)
#   wiki-use.sh main      — write .wiki-mode = main-only (refuses if cwd has .wiki-config)
#   wiki-use.sh both      — enable selective project-to-main promotion
#
# Idempotent: re-running with the current state is a no-op.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"
CONFIG_TOOL="${SCRIPT_DIR}/wiki_config.py"

mode="${1:-}"
[[ -n "${mode}" ]] || { echo >&2 "usage: wiki use project|main|both"; exit 1; }

read_main_wiki() {
  if [[ ! -f "${POINTER_FILE}" ]]; then
    echo "none"
    return
  fi
  cat "${POINTER_FILE}" | tr -d '[:space:]'
}

validate_main_wiki() {
  local main="$1"
  [[ -d "${main}" && -f "${main}/.wiki-config" ]] || return 1
  grep -q '^role = "main"' "${main}/.wiki-config" || return 1
  for required in schema.md index.md .wiki-pending; do
    [[ -e "${main}/${required}" ]] || return 1
  done
}

write_project_pointer_config() {
  local fork="$1"
  local cwd_config="$(pwd)/.wiki-config"
  local today="$(date +%Y-%m-%d)"
  {
    echo "role = \"project-pointer\""
    echo "wiki = \"./wiki\""
    echo "created = \"${today}\""
    echo "fork_to_main = ${fork}"
  } > "${cwd_config}"
}

set_runtime_fork() {
  local root="$1"
  local enabled="$2"
  local flag="--no-fork-to-main"
  [[ "${enabled}" == "true" ]] && flag="--fork-to-main"
  python3 "${CONFIG_TOOL}" update-runtime --wiki "${root}" "${flag}" >/dev/null
}

case "${mode}" in
  project)
    main="$(read_main_wiki)"
    if [[ -f "$(pwd)/.wiki-config" ]]; then
      role=$(grep '^role = ' "$(pwd)/.wiki-config" | head -1 | sed 's/^role = "\(.*\)"/\1/')
      case "${role}" in
        main|project)
          if ! set_runtime_fork "$(pwd)" false; then
            echo >&2 "wiki use project: could not update per-user routing; configure this wiki with 'wiki config init-local $(pwd)' first"
            exit 1
          fi
          rm -f "$(pwd)/.wiki-mode"
          echo "wiki use project: fork_to_main = false in trusted runtime config (role=${role})"
          exit 0
          ;;
        project-pointer)
          ;;
        *)
          echo >&2 "wiki use project: unknown role '${role}' in existing .wiki-config"
          exit 1
          ;;
      esac
    elif [[ ! -d "$(pwd)/wiki" ]]; then
      if [[ "${main}" == "none" ]]; then
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" >/dev/null
      else
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" "${main}" >/dev/null
      fi
    fi
    write_project_pointer_config "false"
    rm -f "$(pwd)/.wiki-mode"
    echo "wiki use project: $(pwd)/wiki/ (fork_to_main = false)"
    ;;

  main)
    if [[ -f "$(pwd)/.wiki-config" ]]; then
      cat >&2 <<EOF
wiki use main: refused — cwd already has .wiki-config (cwd is itself a wiki).
'main-only' mode would orphan the local wiki. To stop using this wiki,
'cd' out of it first. Got role: $(grep '^role = ' "$(pwd)/.wiki-config" | head -1)
EOF
      exit 1
    fi
    echo "main-only" > "$(pwd)/.wiki-mode"
    if [[ -d "$(pwd)/wiki" ]]; then
      cat >&2 <<EOF
wiki use main: warning — local ./wiki/ exists from a prior project mode.
Captures will no longer go there. To remove it: rm -rf ./wiki/
EOF
    fi
    echo "wiki use main: captures go to main wiki"
    ;;

  both)
    main="$(read_main_wiki)"
    if [[ "${main}" == "none" || -z "${main}" ]]; then
      cat >&2 <<EOF
wiki use both: refused — \$WIKI_POINTER_FILE is 'none' or missing.
'both' mode requires a main wiki for selective promotion. Run 'wiki init-main' first
or 'wiki use project' for a project-only setup.
EOF
      exit 1
    fi
    if ! validate_main_wiki "${main}"; then
      echo >&2 "wiki use both: refused — main wiki pointer is broken or does not target role=main"
      exit 1
    fi
    if [[ -f "$(pwd)/.wiki-config" ]]; then
      role=$(grep '^role = ' "$(pwd)/.wiki-config" | head -1 | sed 's/^role = "\(.*\)"/\1/')
      case "${role}" in
        project-pointer)
          # Set fork_to_main = true in place
          if grep -q '^fork_to_main = ' "$(pwd)/.wiki-config"; then
            sed -i.bak 's/^fork_to_main = .*/fork_to_main = true/' "$(pwd)/.wiki-config"
            rm -f "$(pwd)/.wiki-config.bak"
          else
            echo "fork_to_main = true" >> "$(pwd)/.wiki-config"
          fi
          sed -i.bak '/^main = /d' "$(pwd)/.wiki-config"
          rm -f "$(pwd)/.wiki-config.bak"
          rm -f "$(pwd)/.wiki-mode"
          echo "wiki use both: fork_to_main = true on existing config (role=${role})"
          ;;
        project)
          if ! set_runtime_fork "$(pwd)" true; then
            echo >&2 "wiki use both: could not update per-user routing; configure this wiki with 'wiki config init-local $(pwd)' first"
            exit 1
          fi
          rm -f "$(pwd)/.wiki-mode"
          echo "wiki use both: fork_to_main = true in trusted runtime config (role=${role})"
          ;;
        main)
          echo >&2 "wiki use both: refused — selective promotion requires a project wiki"
          exit 1
          ;;
        *)
          echo >&2 "wiki use both: unknown role '${role}' in existing .wiki-config"
          exit 1
          ;;
      esac
    else
      # Fresh cwd
      if [[ ! -d "$(pwd)/wiki" ]]; then
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" "${main}" >/dev/null
      fi
      write_project_pointer_config "true"
      rm -f "$(pwd)/.wiki-mode"
      echo "wiki use both: created project wiki + fork_to_main = true"
    fi
    ;;

  *)
    echo >&2 "wiki use: unknown mode '${mode}'; valid: project|main|both"
    exit 1
    ;;
esac
