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

frontmatter_raw_value() {
  local key="$1"
  local file="$2"
  awk -v wanted="${key}" '
    { line = $0; sub(/\r$/, "", line) }
    NR == 1 { if (line != "---") exit; next }
    line == "---" { exit }
    line ~ ("^" wanted "[[:space:]]*:") {
      sub("^" wanted "[[:space:]]*:", "", line)
      print "present:" line
      exit
    }
  ' "${file}"
}

parse_frontmatter_value() {
  local field="$1"
  local value parsed
  [[ "${field}" == present:* ]] || return 3
  value="${field#present:}"
  value="$(printf '%s\n' "${value}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "${value}" in
    \"*) parsed="$(printf '%s\n' "${value}" \
      | sed -n 's/^"\([^"]*\)"[[:space:]]*\(#.*\)\{0,1\}$/\1/p')" ;;
    \'*) parsed="$(printf '%s\n' "${value}" \
      | sed -n "s/^'\([^']*\)'[[:space:]]*\(#.*\)\{0,1\}$/\1/p")" ;;
    *) parsed="$(printf '%s\n' "${value}" \
      | sed 's/[[:space:]][[:space:]]*#.*$//; s/[[:space:]]*$//')" ;;
  esac
  [[ -n "${parsed}" ]] || return 2
  printf '%s\n' "${parsed}"
}

parse_promotion_policy() {
  local parsed
  parsed="$(parse_frontmatter_value "$1")" || return $?
  case "${parsed}" in
    none|selective) printf '%s\n' "${parsed}" ;;
    *) return 2 ;;
  esac
}

parse_promotion_decision() {
  local parsed
  parsed="$(parse_frontmatter_value "$1")" || return $?
  case "${parsed}" in
    keep-local|promoted) printf '%s\n' "${parsed}" ;;
    *) return 2 ;;
  esac
}

if ! awk '
  { line = $0; sub(/\r$/, "", line) }
  NR == 1 { if (line != "---") exit 1; next }
  line == "---" { closed = 1; exit }
  line ~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/ {
    key = line
    sub(/:.*/, "", key)
    sub(/[[:space:]]*$/, "", key)
    if (key == "capture_id" || key == "promotion_policy" ||
        key == "promotion_decision" || key == "promotion_id" ||
        key == "promotion_main_wiki" || key == "propagated_from") {
      if (++seen[key] > 1) exit 2
    }
  }
  END { if (!closed) exit 1 }
' "${processing}"; then
  echo >&2 "wiki complete: duplicate or invalid authoritative frontmatter"
  exit 1
fi

policy_field="$(frontmatter_raw_value promotion_policy "${processing}")"
promotion_policy="none"
if [[ -n "${policy_field}" ]]; then
  if ! promotion_policy="$(parse_promotion_policy "${policy_field}")"; then
    echo >&2 "wiki complete: unsupported or malformed promotion_policy"
    exit 1
  fi
fi
if [[ "${promotion_policy}" == "selective" ]]; then
  decision_field="$(frontmatter_raw_value promotion_decision "${processing}")"
  if [[ -z "${decision_field}" ]]; then
    echo >&2 "wiki complete: selective capture requires a promotion decision"
    exit 1
  fi
  if ! promotion_decision="$(parse_promotion_decision "${decision_field}")"; then
    echo >&2 "wiki complete: selective capture requires keep-local or promoted decision"
    exit 1
  fi
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
