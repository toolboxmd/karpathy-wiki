#!/bin/bash
# wiki-init-main.sh — interactive bootstrap of ~/.wiki-pointer.
#
# Behavior:
# 1. If $WIKI_POINTER_FILE already exists → no-op (do not re-prompt).
# 2. Find candidate main wikis at depth ≤ 2 in $HOME (or
#    $WIKI_INIT_MAIN_HOME for testing). A candidate is a directory
#    with .wiki-config containing role = "main".
# 3. If exactly ONE candidate → silent migration (write pointer; no prompt).
# 4. If MULTIPLE candidates → prompt user to pick.
# 5. If ZERO candidates → prompt user: yes (create new) | no (write 'none').
#
# Override $WIKI_POINTER_FILE for testing (default: ~/.wiki-pointer).
# Override $WIKI_INIT_MAIN_HOME for testing (default: $HOME).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"
SCAN_HOME="${WIKI_INIT_MAIN_HOME:-${HOME}}"

# Step 1: pointer already exists → no-op.
if [[ -f "${POINTER_FILE}" || -L "${POINTER_FILE}" ]]; then
  exit 0
fi

# Step 2: find candidate main wikis.
candidates=()
while IFS= read -r config; do
  if grep -q '^role = "main"' "${config}"; then
    candidates+=("$(dirname "${config}")")
  fi
done < <(find "${SCAN_HOME}" -maxdepth 3 -name '.wiki-config' -type f 2>/dev/null)

case "${#candidates[@]}" in
  1)
    # Silent migration.
    echo "${candidates[0]}" > "${POINTER_FILE}"
    echo "wiki-init-main: silent migration — pointer set to ${candidates[0]}" >&2
    exit 0
    ;;
  0)
    # No candidate — prompt for create vs none.
    cat <<'EOF'

You don't have a main (global) wiki yet.
A main wiki collects general patterns reusable across projects.
You can have project-only wikis without one.

  1) yes — create a main wiki (you'll be asked where)
  2) no  — project wikis only

EOF
    read -p "Reply with 1 or 2: " choice
    case "${choice}" in
      1)
        cat <<EOF

Where should the main wiki live?
  Default: \$HOME/wiki/

EOF
        read -p "Reply 'default' or a path: " path
        if [[ "${path}" == "default" || -z "${path}" ]]; then
          path="${SCAN_HOME}/wiki"
        fi
        bash "${SCRIPT_DIR}/wiki-init.sh" main "${path}"
        echo "${path}" > "${POINTER_FILE}"
        ;;
      2)
        echo "none" > "${POINTER_FILE}"
        ;;
      *)
        echo >&2 "wiki-init-main: invalid choice; aborting"
        exit 1
        ;;
    esac
    ;;
  *)
    # Multi-candidate — prompt.
    echo
    echo "Found existing main wiki(s):"
    i=1
    for c in "${candidates[@]}"; do
      echo "  ${i}) ${c}"
      i=$((i + 1))
    done
    nopt=$((${#candidates[@]} + 1))
    nopt2=$((nopt + 1))
    echo "  ${nopt}) other (enter a path)"
    echo "  ${nopt2}) none — project wikis only"
    echo
    read -p "Which one should be the main wiki for v2.4? " choice
    if [[ "${choice}" -ge 1 && "${choice}" -le "${#candidates[@]}" ]]; then
      echo "${candidates[$((choice - 1))]}" > "${POINTER_FILE}"
    elif [[ "${choice}" == "${nopt}" ]]; then
      read -p "Enter path: " path
      bash "${SCRIPT_DIR}/wiki-init.sh" main "${path}"
      echo "${path}" > "${POINTER_FILE}"
    elif [[ "${choice}" == "${nopt2}" ]]; then
      echo "none" > "${POINTER_FILE}"
    else
      echo >&2 "wiki-init-main: invalid choice; aborting"
      exit 1
    fi
    ;;
esac

exit 0
