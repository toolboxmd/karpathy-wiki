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
  # Trim surrounding whitespace only; preserve interior spaces in the path.
  cat "${POINTER_FILE}" | head -1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
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

pointer_target() {
  local config="$1" sub
  sub="$(sed -n 's/^wiki = "\(.*\)"/\1/p' "${config}" | head -1)"
  [[ -n "${sub}" ]] || sub="./wiki"
  if [[ "${sub}" == /* ]]; then
    printf '%s\n' "${sub}"
  else
    printf '%s\n' "$(dirname "${config}")/${sub#./}"
  fi
}

set_pointer_fork() {
  local config="$1" enabled="$2" target workspace runtime_path backup
  target="$(pointer_target "${config}")"
  workspace="$(dirname "${config}")"
  runtime_path="$(python3 "${CONFIG_TOOL}" path --wiki "${target}" 2>/dev/null || true)"
  if [[ -n "${runtime_path}" && -e "${runtime_path}" ]]; then
    python3 "${CONFIG_TOOL}" validate-pointer \
      --wiki "${target}" --workspace "${workspace}" >/dev/null 2>&1 \
      || return 1
  fi
  backup="${config}.wiki-use-backup.$$"
  cp "${config}" "${backup}" || return 1
  if grep -q '^fork_to_main = ' "${config}"; then
    sed -i.bak "s/^fork_to_main = .*/fork_to_main = ${enabled}/" "${config}" || {
      rm -f "${backup}" "${config}.bak"
      return 1
    }
    rm -f "${config}.bak"
  else
    printf 'fork_to_main = %s\n' "${enabled}" >> "${config}" || {
      mv "${backup}" "${config}"
      return 1
    }
  fi
  sed -i.bak '/^main = /d' "${config}" || {
    mv "${backup}" "${config}"
    rm -f "${config}.bak"
    return 1
  }
  rm -f "${config}.bak"

  if [[ -n "${runtime_path}" && -e "${runtime_path}" ]] \
    && ! set_runtime_fork "${target}" "${enabled}"; then
    mv "${backup}" "${config}"
    return 1
  fi
  rm -f "${backup}"
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
          if ! set_pointer_fork "$(pwd)/.wiki-config" false; then
            echo >&2 "wiki use project: could not synchronize project pointer routing"
            exit 1
          fi
          rm -f "$(pwd)/.wiki-mode"
          echo "wiki use project: $(pwd)/wiki/ (fork_to_main = false)"
          exit 0
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
          if ! set_pointer_fork "$(pwd)/.wiki-config" true; then
            echo >&2 "wiki use both: could not synchronize project pointer routing"
            exit 1
          fi
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
