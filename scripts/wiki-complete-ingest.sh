#!/bin/bash
# Deterministically validate, archive, and optionally commit one ingest.
#
# Required environment:
#   WIKI_ROOT, WIKI_CAPTURE (.md.processing), WIKI_RUN_ID

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-capture.sh"

wiki="${WIKI_ROOT:-}"
processing="${WIKI_CAPTURE:-}"
run_id="${WIKI_RUN_ID:-}"

[[ -n "${wiki}" ]] || { echo >&2 "wiki complete: WIKI_ROOT is required"; exit 1; }
[[ -n "${processing}" ]] || { echo >&2 "wiki complete: WIKI_CAPTURE is required"; exit 1; }
[[ -n "${run_id}" ]] || { echo >&2 "wiki complete: WIKI_RUN_ID is required"; exit 1; }

wiki="$(cd "${wiki}" 2>/dev/null && pwd -P)" || {
  echo >&2 "wiki complete: WIKI_ROOT does not exist"
  exit 1
}

capture_parent="$(cd "$(dirname "${processing}")" 2>/dev/null && pwd -P)" || {
  echo >&2 "wiki complete: capture parent does not exist"
  exit 1
}
capture_name="$(basename "${processing}")"
if [[ "${capture_parent}" != "${wiki}/.wiki-pending" || "${capture_name}" != *.md.processing ]]; then
  echo >&2 "wiki complete: WIKI_CAPTURE must be a .md.processing file directly under .wiki-pending"
  exit 1
fi
processing="${capture_parent}/${capture_name}"

archive_name="${capture_name%.processing}"
archive_dir="${wiki}/.wiki-pending/archive/$(date +%Y-%m)"
archived="${archive_dir}/${archive_name}"

# A repeated helper call after a verified move is a successful no-op.
if [[ ! -e "${processing}" ]]; then
  if [[ -f "${archived}" ]]; then
    exit 0
  fi
  echo >&2 "wiki complete: processing capture is missing and no matching archive exists"
  exit 1
fi
if [[ -e "${archived}" ]]; then
  echo >&2 "wiki complete: refusing to overwrite existing archive ${archived}"
  exit 1
fi

frontmatter_scalar() {
  local key="$1"
  local file="$2"
  awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }' "${file}" \
    | sed -n "s/^${key}:[[:space:]]*[\"']\\{0,1\\}\\([^\"']*\\)[\"']\\{0,1\\}[[:space:]]*$/\\1/p" \
    | head -n 1
}

promotion_policy="$(frontmatter_scalar promotion_policy "${processing}")"
if [[ "${promotion_policy}" == "selective" ]]; then
  promotion_decision="$(frontmatter_scalar promotion_decision "${processing}")"
  case "${promotion_decision}" in
    keep-local|promoted) ;;
    *)
      echo >&2 "wiki complete: selective capture requires keep-local or promoted decision"
      exit 1
      ;;
  esac
  if ! WIKI_PLUGIN_ROOT="${WIKI_PLUGIN_ROOT:-${SCRIPT_DIR}/..}" \
    python3 "${SCRIPT_DIR}/wiki-promote-capture.py" verify >&2; then
    echo >&2 "wiki complete: selective promotion decision verification failed"
    exit 1
  fi
fi

if ! python3 "${SCRIPT_DIR}/wiki-manifest.py" validate "${wiki}" >&2; then
  echo >&2 "wiki complete: manifest validation failed"
  exit 1
fi

title="$(sed -n 's/^title:[[:space:]]*["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}[[:space:]]*$/\1/p' "${processing}" | head -n 1)"
[[ -n "${title}" ]] || title="${archive_name%.md}"
title="${title//$'\n'/ }"
title="${title:0:160}"

wiki_capture_archive "${wiki}" "${processing}" || {
  echo >&2 "wiki complete: archive move failed"
  exit 1
}

rollback_archive() {
  if [[ -f "${archived}" && ! -e "${processing}" ]]; then
    mv "${archived}" "${processing}" 2>/dev/null || true
  fi
}

if [[ "${WIKI_COMPLETE_TEST_MODE:-0}" == "1" && "${WIKI_COMPLETE_TEST_FAIL_AFTER_ARCHIVE:-0}" == "1" ]]; then
  rollback_archive
  echo >&2 "wiki complete: injected post-archive failure"
  exit 1
fi

if ! bash "${SCRIPT_DIR}/wiki-commit.sh" "${wiki}" "ingest: ${title}"; then
  rollback_archive
  echo >&2 "wiki complete: commit failed; capture restored to processing"
  exit 1
fi

exit 0
