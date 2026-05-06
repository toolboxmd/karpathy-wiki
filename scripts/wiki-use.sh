#!/bin/bash
# wiki-use.sh — change per-cwd wiki mode.
#
# Subcommands:
#   wiki-use.sh project   — write .wiki-config (project-pointer, fork=false)
#   wiki-use.sh main      — write .wiki-mode = main-only (refuses if cwd has .wiki-config)
#   wiki-use.sh both      — write .wiki-config with fork_to_main = true (refuses if pointer = none)
#
# Idempotent: re-running with the current state is a no-op.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"

mode="${1:-}"
[[ -n "${mode}" ]] || { echo >&2 "usage: wiki use project|main|both"; exit 1; }

read_main_wiki() {
  if [[ ! -f "${POINTER_FILE}" ]]; then
    echo "none"
    return
  fi
  cat "${POINTER_FILE}" | tr -d '[:space:]'
}

write_project_pointer_config() {
  local fork="$1"
  local main="$2"
  local cwd_config="$(pwd)/.wiki-config"
  local today="$(date +%Y-%m-%d)"
  {
    echo "role = \"project-pointer\""
    echo "wiki = \"./wiki\""
    echo "created = \"${today}\""
    if [[ -n "${main}" && "${main}" != "none" ]]; then
      echo "main = \"${main}\""
    fi
    echo "fork_to_main = ${fork}"
  } > "${cwd_config}"
}

case "${mode}" in
  project)
    main="$(read_main_wiki)"
    if [[ ! -d "$(pwd)/wiki" ]]; then
      if [[ "${main}" == "none" ]]; then
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" >/dev/null
      else
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" "${main}" >/dev/null
      fi
    fi
    write_project_pointer_config "false" "${main}"
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
'both' mode requires a main wiki to fork to. Run 'wiki init-main' first
or 'wiki use project' for a project-only setup.
EOF
      exit 1
    fi
    if [[ -f "$(pwd)/.wiki-config" ]]; then
      role=$(grep '^role = ' "$(pwd)/.wiki-config" | head -1 | sed 's/^role = "\(.*\)"/\1/')
      case "${role}" in
        project-pointer|main|project)
          # Set fork_to_main = true in place
          if grep -q '^fork_to_main = ' "$(pwd)/.wiki-config"; then
            sed -i.bak 's/^fork_to_main = .*/fork_to_main = true/' "$(pwd)/.wiki-config"
            rm -f "$(pwd)/.wiki-config.bak"
          else
            echo "fork_to_main = true" >> "$(pwd)/.wiki-config"
          fi
          rm -f "$(pwd)/.wiki-mode"
          echo "wiki use both: fork_to_main = true on existing config (role=${role})"
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
      write_project_pointer_config "true" "${main}"
      rm -f "$(pwd)/.wiki-mode"
      echo "wiki use both: created project wiki + fork_to_main = true"
    fi
    ;;

  *)
    echo >&2 "wiki use: unknown mode '${mode}'; valid: project|main|both"
    exit 1
    ;;
esac
