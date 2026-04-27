#!/bin/bash
# wiki-migrate-v2.3.sh — Live wiki page-migration orchestrator for v2.3 Phase D.
#
# Two phases, each commits to the wiki repo separately (operator commits
# between calls). Per corrigendum C-G: atomic moves+relinks in phase 1,
# index rebuild in phase 2, with a verification gate between them.
#
# Usage:
#   wiki-migrate-v2.3.sh --dry-run --wiki-root <root>
#   wiki-migrate-v2.3.sh --phase=moves-and-relinks --wiki-root <root>
#   wiki-migrate-v2.3.sh --phase=index-rebuild --wiki-root <root>
#   wiki-migrate-v2.3.sh --yes --wiki-root <root>  # runs phase 1 only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
PHASE=""
YES=0
WIKI_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --phase=*) PHASE="${1#--phase=}"; shift ;;
    --yes) YES=1; shift ;;
    --wiki-root) WIKI_ROOT="$2"; shift 2 ;;
    *) echo "usage: $0 (--dry-run | --phase=moves-and-relinks | --phase=index-rebuild | --yes) --wiki-root <root>" >&2; exit 1 ;;
  esac
done

[[ -z "${WIKI_ROOT}" ]] && { echo "missing --wiki-root" >&2; exit 1; }
[[ ! -d "${WIKI_ROOT}" ]] && { echo "not a directory: ${WIKI_ROOT}" >&2; exit 1; }

# Pages to move: <old-relative>:<new-relative>
declare -a MOVES=(
  "concepts/karpathy-wiki-v2.2-architectural-cut.md:projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.2-architectural-cut.md"
  "concepts/karpathy-wiki-v2.3-flexible-categories-design.md:projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.3-flexible-categories-design.md"
  "concepts/multi-stage-opus-pipeline-lessons.md:projects/toolboxmd/building-agentskills/multi-stage-opus-pipeline-lessons.md"
  "concepts/building-agentskills-repo-decision.md:projects/toolboxmd/building-agentskills/building-agentskills-repo-decision.md"
)

ensure_dirs() {
  for d in projects/toolboxmd/karpathy-wiki projects/toolboxmd/building-agentskills; do
    if [[ ! -d "${WIKI_ROOT}/${d}" ]]; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "would mkdir ${WIKI_ROOT}/${d}"
      else
        mkdir -p "${WIKI_ROOT}/${d}"
      fi
    fi
  done
}

phase_moves_and_relinks() {
  ensure_dirs
  local moved_args=()
  local any_moves=0
  for mv in "${MOVES[@]}"; do
    local old="${mv%%:*}"
    local new="${mv##*:}"
    local old_abs="${WIKI_ROOT}/${old}"
    local new_abs="${WIKI_ROOT}/${new}"
    if [[ ! -f "${old_abs}" ]]; then
      if [[ -f "${new_abs}" ]]; then
        echo "already migrated (no-op): ${new}"
        continue
      fi
      echo "skipped (not found): ${old}"
      continue
    fi
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "would git mv ${old} -> ${new}"
      any_moves=1
      continue
    fi
    if ! ( cd "${WIKI_ROOT}" && git mv "${old}" "${new}" ); then
      echo "FAIL: git mv ${old} -> ${new}; aborting before relink" >&2
      exit 1
    fi
    moved_args+=("--moved" "${old}=${new}")
    any_moves=1
  done

  if [[ "${DRY_RUN}" -eq 0 && "${#moved_args[@]}" -gt 0 ]]; then
    if ! python3 "${SCRIPT_DIR}/wiki-relink.py" --wiki-root "${WIKI_ROOT}" "${moved_args[@]}"; then
      echo "FAIL: wiki-relink.py errored; working tree has staged moves but UNSTAGED relinks may be inconsistent" >&2
      echo "Recovery: cd ${WIKI_ROOT} && git reset --hard HEAD && git clean -fd" >&2
      exit 1
    fi
  fi

  if [[ "${any_moves}" -eq 0 ]]; then
    echo "no-op: no pages required moving"
  else
    echo "phase moves-and-relinks complete; ready to commit"
  fi
}

phase_index_rebuild() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "would rebuild all _index.md via wiki-build-index.py --rebuild-all"
    return
  fi
  python3 "${SCRIPT_DIR}/wiki-build-index.py" --wiki-root "${WIKI_ROOT}" --rebuild-all
  echo "phase index-rebuild complete; ready to commit"
}

if [[ "${YES}" -eq 1 ]]; then
  # NOTE: --yes runs ONLY phase 'moves-and-relinks' (not the full migration).
  # The operator must commit, then re-run with --phase=index-rebuild for
  # the second phase. This is INTENTIONAL -- verification gate between phases.
  phase_moves_and_relinks
  echo "OPERATOR: now run 'cd ${WIKI_ROOT} && git add -A && git commit ...' for the moves+relinks commit, then re-run with --phase=index-rebuild"
elif [[ "${PHASE}" == "moves-and-relinks" ]]; then
  phase_moves_and_relinks
elif [[ "${PHASE}" == "index-rebuild" ]]; then
  phase_index_rebuild
elif [[ "${DRY_RUN}" -eq 1 ]]; then
  phase_moves_and_relinks
  echo "---"
  phase_index_rebuild
else
  echo "specify --dry-run, --yes, or --phase=..." >&2
  exit 1
fi
