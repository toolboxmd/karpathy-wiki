#!/bin/bash
# On-demand detached rewrite drain (one cluster job).
#
# Usage:
#   wiki-rewrite.sh              — cwd-resolved wiki
#   wiki-rewrite.sh <wiki-path>  — explicit wiki

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

first_job() {
  local wiki="$1"
  python3 "${SCRIPT_DIR}/wiki-compact-cluster.py" --wiki-root "${wiki}" --next-job
}

rewrite_one_wiki() {
  local wiki="$1"
  [[ -d "${wiki}" ]] || { echo >&2 "wiki rewrite: wiki path does not exist: ${wiki}"; return 1; }
  [[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "wiki rewrite: not a wiki (no .wiki-config): ${wiki}"; return 1; }
  mkdir -p "${wiki}/.locks" "${wiki}/.wiki-pending/rewrite-jobs"
  local job
  job="$(first_job "${wiki}")"
  if [[ -z "${job}" ]]; then
    echo "wiki rewrite: nothing pending"
    return 0
  fi
  local run_id
  run_id="rew-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  export WIKI_ROOT="${wiki}"
  export WIKI_RUN_ID="${run_id}"
  export WIKI_PLUGIN_ROOT="${REPO_ROOT}"
  export WIKI_JOB="rewrite"
  export WIKI_REWRITE_JOB="${job}"
  if [[ "${WIKI_REWRITE_TEST:-}" == "1" ]]; then
    bash "${SCRIPT_DIR}/wiki-complete-rewrite.sh" || return 1
    echo "wiki rewrite: completed ${run_id}"
    return 0
  fi
  python3 "${SCRIPT_DIR}/wiki_dispatch.py" rewrite --wiki "${wiki}" --run-id "${run_id}" \
    || return 1
}

if [[ $# -eq 0 ]]; then
  resolver_out="$(bash "${SCRIPT_DIR}/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0 || resolver_exit=$?
  if [[ "${resolver_exit}" != 0 ]]; then
    echo >&2 "wiki rewrite: resolver exit ${resolver_exit}; cannot determine target wiki."
    exit 1
  fi
  while IFS= read -r wiki_path; do
    [[ -n "${wiki_path}" ]] || continue
    rewrite_one_wiki "${wiki_path}" || exit 1
  done <<< "${resolver_out}"
else
  rewrite_one_wiki "$1" || exit 1
fi

exit 0
