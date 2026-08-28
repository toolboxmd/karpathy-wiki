#!/bin/bash
# Complete one rewrite job: cluster compact or entity map, archive, commit.
#
# Required environment: WIKI_ROOT, WIKI_RUN_ID, WIKI_REWRITE_JOB

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

wiki="${WIKI_ROOT:-}"
run_id="${WIKI_RUN_ID:-}"
job="${WIKI_REWRITE_JOB:-}"

[[ -n "${wiki}" ]] || { echo >&2 "wiki complete-rewrite: WIKI_ROOT is required"; exit 1; }
[[ -n "${run_id}" ]] || { echo >&2 "wiki complete-rewrite: WIKI_RUN_ID is required"; exit 1; }
[[ -n "${job}" ]] || { echo >&2 "wiki complete-rewrite: WIKI_REWRITE_JOB is required"; exit 1; }
wiki="$(cd "${wiki}" 2>/dev/null && pwd -P)" || {
  echo >&2 "wiki complete-rewrite: WIKI_ROOT does not exist"
  exit 1
}
[[ -f "${job}" ]] || { echo >&2 "wiki complete-rewrite: job missing: ${job}"; exit 1; }

kind="$(
  python3 "${SCRIPT_DIR}/wiki-compact-cluster.py" --wiki-root "${wiki}" --job-file "${job}" --job-kind
)" || exit 1
if [[ "${kind}" == "entity" ]]; then
  token="$(
    python3 "${SCRIPT_DIR}/wiki-rewrite-entity.py" --wiki-root "${wiki}" --job-file "${job}"
  )" || exit 1
else
  token="$(
    python3 "${SCRIPT_DIR}/wiki-compact-cluster.py" --wiki-root "${wiki}" --job-file "${job}"
  )" || exit 1
fi

archive_dir="${wiki}/.wiki-pending/archive/rewrite-jobs"
mkdir -p "${archive_dir}" "${wiki}/.locks"
mv "${job}" "${archive_dir}/$(basename "${job}")"

lock="${wiki}/.locks/rewrite-runs.lock"
log="${wiki}/.rewrite-runs.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
line="$(
  WIKI_REW_TS="${ts}" WIKI_REW_RUN="${run_id}" WIKI_REW_JOB="${token}" python3 <<'PY'
import json, os
print(json.dumps({
    "run_id": os.environ["WIKI_REW_RUN"],
    "status": "completed",
    "job": os.environ["WIKI_REW_JOB"],
    "at": os.environ["WIKI_REW_TS"],
}, separators=(",", ":")))
PY
)"

if command -v flock >/dev/null 2>&1; then
  flock "${lock}" bash -c "printf '%s\\n' \"\$1\" >> \"\$2\"" _ "${line}" "${log}"
else
  printf '%s\n' "${line}" >> "${log}"
fi

bash "${SCRIPT_DIR}/wiki-commit.sh" "${wiki}" "rewrite: ${token}" || {
  echo >&2 "wiki complete-rewrite: commit failed"
  exit 1
}
exit 0
