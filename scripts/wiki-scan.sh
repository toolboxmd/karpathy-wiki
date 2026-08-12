#!/bin/bash
# Scan inbox/ and raw/ for sources that need an ingest capture.
#
# Queue dispatch is deliberately outside this script. SessionStart, a
# scheduler, and `wiki ingest-now` all call this same scanner before asking
# the bounded dispatcher to drain .wiki-pending/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

wiki="${1:-}"
[[ -n "${wiki}" ]] || { echo >&2 "wiki scan: <wiki-path> required"; exit 1; }
[[ -d "${wiki}" ]] || { echo >&2 "wiki scan: wiki path does not exist: ${wiki}"; exit 1; }
wiki="$(cd "${wiki}" && pwd -P)"
export WIKI_INGEST_LOG="${WIKI_INGEST_LOG:-${wiki}/.ingest.log}"
for required in .wiki-config schema.md index.md .wiki-pending inbox raw; do
  [[ -e "${wiki}/${required}" ]] || {
    echo >&2 "wiki scan: incomplete wiki — missing ${wiki}/${required}"
    exit 1
  }
done

promotion_policy="$(wiki_promotion_policy "${wiki}")"

_emit_raw_direct_capture() {
  local file_path="$1"
  local basename
  basename="$(basename "${file_path}")"

  local src_hash capture_base capture_name capture_path
  src_hash="$(printf '%s' "${file_path}" | shasum | cut -c1-12)"
  capture_base="drift-${src_hash}-$(slugify "${basename}")"
  capture_name="${capture_base:0:200}.md"
  capture_path="${wiki}/.wiki-pending/${capture_name}"

  local capture_temp
  local capture_id
  capture_id="cap-$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
  capture_temp="$(mktemp "${wiki}/.wiki-pending/.scan-capture.XXXXXX")" || return 1
  if ! cat > "${capture_temp}" <<EOF
---
title: "Drop: ${basename}"
evidence: "${file_path}"
evidence_type: "file"
capture_kind: "raw-direct"
suggested_action: "auto"
suggested_pages: []
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
captured_by: "wiki-scan-drop"
capture_id: "${capture_id}"
promotion_policy: "${promotion_policy}"
promotion_decision: null
promotion_id: null
propagated_from: null
---

Auto-ingest of file in <inbox|raw>/. The raw file named by the evidence field is the
canonical source; this body is auto-generated and intentionally
minimal. Action for the ingester: read the raw file, infer category
from content, decide create vs augment, file under appropriate
category. If the raw file looks like an Obsidian Web Clipper export
(has source/created/published frontmatter), preserve those fields.
EOF
  then
    rm -f "${capture_temp}"
    return 1
  fi
  chmod 0644 "${capture_temp}" || { rm -f "${capture_temp}"; return 1; }
  if ln "${capture_temp}" "${capture_path}" 2>/dev/null; then
    log_info "scan: raw-direct capture created: ${capture_name}"
  fi
  rm -f "${capture_temp}"
}

_emit_legacy_drift_capture() {
  local src="$1"
  local src_hash capture_base capture_name capture_path
  src_hash="$(printf '%s' "${src}" | shasum | cut -c1-12)"
  capture_base="drift-${src_hash}-$(slugify "${src}")"
  capture_name="${capture_base:0:200}.md"
  capture_path="${wiki}/.wiki-pending/${capture_name}"
  local capture_temp
  local capture_id
  capture_id="cap-$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
  capture_temp="$(mktemp "${wiki}/.wiki-pending/.scan-capture.XXXXXX")" || return 1
  if ! cat > "${capture_temp}" <<EOF
---
title: "Drift: ${src}"
evidence: "${wiki}/${src}"
evidence_type: "file"
capture_kind: "raw-direct"
suggested_action: "update"
suggested_pages: []
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
captured_by: "wiki-scan-drift"
capture_id: "${capture_id}"
promotion_policy: "${promotion_policy}"
promotion_decision: null
promotion_id: null
propagated_from: null
---

Auto-generated drift capture. The raw source file at ${src} has a
sha mismatch against the manifest entry. Re-ingest to bring the wiki
back in sync. The ingester should read the raw file at `evidence`,
decide which existing page (if any) it augments based on its content,
and either update that page or create a new one in the appropriate
category. Update the manifest entry once done so this drift doesn't
re-fire on the next scan.
EOF
  then
    rm -f "${capture_temp}"
    return 1
  fi
  chmod 0644 "${capture_temp}" || { rm -f "${capture_temp}"; return 1; }
  if ln "${capture_temp}" "${capture_path}" 2>/dev/null; then
    log_info "scan: legacy drift capture created: ${capture_name}"
  fi
  rm -f "${capture_temp}"
}

_manifest_lock_acquire() {
  local lock_dir="${wiki}/.locks"
  mkdir -p "${lock_dir}"
  local lock_file="${lock_dir}/manifest.lock"

  if command -v flock >/dev/null 2>&1; then
    exec 8>"${lock_file}"
    flock 8
    _MANIFEST_LOCK_MODE="flock"
  else
    local poll=0.05 elapsed=0
    while true; do
      if [[ -f "${lock_file}" ]]; then
        local mtime now age
        mtime="$(stat -f %m "${lock_file}" 2>/dev/null || stat -c %Y "${lock_file}" 2>/dev/null || echo 0)"
        now="$(date +%s)"; age=$((now - mtime))
        [[ "${age}" -gt 300 ]] && rm -f "${lock_file}"
      fi
      if ( set -o noclobber; printf '%d\n' "$$" > "${lock_file}" ) 2>/dev/null; then
        _MANIFEST_LOCK_MODE="noclobber"
        _MANIFEST_LOCK_FILE="${lock_file}"
        break
      fi
      sleep "${poll}"
      elapsed=$(awk -v e="${elapsed}" -v p="${poll}" 'BEGIN{print e+p}')
      if awk -v e="${elapsed}" 'BEGIN{exit !(e>30)}'; then
        log_warn "scan: manifest lock acquire timeout"
        return 1
      fi
    done
  fi
  return 0
}

_manifest_lock_release() {
  case "${_MANIFEST_LOCK_MODE:-}" in
    flock) exec 8>&- ;;
    noclobber) rm -f "${_MANIFEST_LOCK_FILE}" ;;
  esac
  unset _MANIFEST_LOCK_MODE _MANIFEST_LOCK_FILE
}

_raw_recovery() {
  local abs_src="$1"
  local basename
  basename="$(basename "${abs_src}")"

  if ! _manifest_lock_acquire; then
    log_warn "scan: raw-recovery skipped (lock unavailable): ${basename}"
    return 0
  fi

  if python3 - "${wiki}/.manifest.json" "raw/${basename}" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
    raise SystemExit(0 if sys.argv[2] in data else 1)
except Exception:
    raise SystemExit(1)
PY
  then
    _manifest_lock_release
    log_info "scan: raw/${basename} now in manifest; recovery aborted"
    return 0
  fi

  if [[ ! -f "${abs_src}" ]]; then
    _manifest_lock_release
    log_info "scan: raw/${basename} already recovered by concurrent scan"
    return 0
  fi

  local target="${wiki}/inbox/${basename}"
  if [[ -e "${target}" ]]; then
    local stem ext n
    if [[ "${basename}" == *.* ]]; then
      stem="${basename%.*}"; ext="${basename##*.}"; n=1
      while [[ -e "${wiki}/inbox/${stem}.${n}.${ext}" ]]; do n=$((n+1)); done
      target="${wiki}/inbox/${stem}.${n}.${ext}"
    else
      n=1
      while [[ -e "${wiki}/inbox/${basename}.${n}" ]]; do n=$((n+1)); done
      target="${wiki}/inbox/${basename}.${n}"
    fi
  fi

  if ! mv "${abs_src}" "${target}"; then
    _manifest_lock_release
    log_warn "scan: raw-recovery move failed: ${basename}"
    return 1
  fi
  log_warn "scan: raw-recovery | unmanifested file moved raw/ -> inbox/: ${basename}"
  if ! _emit_raw_direct_capture "${target}"; then
    _manifest_lock_release
    log_warn "scan: raw-recovery capture publication failed: ${basename}"
    return 1
  fi
  _manifest_lock_release
}

_drift_scan() {
  local now mtime age
  now="$(date +%s)"

  local f
  for f in "${wiki}/inbox"/*; do
    [[ -f "${f}" ]] || continue
    mtime="$(stat -f %m "${f}" 2>/dev/null || stat -c %Y "${f}" 2>/dev/null || echo 0)"
    age=$((now - mtime))
    if [[ "${age}" -lt 5 ]]; then
      log_info "scan: inbox file mtime within last 5s, deferring: $(basename "${f}")"
      continue
    fi
    if ! _emit_raw_direct_capture "${f}"; then
      return 1
    fi
  done

  local drift_out
  if ! drift_out="$(python3 "${REPO_ROOT}/scripts/wiki-manifest.py" diff "${wiki}" 2>&1)"; then
    log_warn "scan: manifest diff failed | ${drift_out//$'\n'/ | }"
    return 1
  fi
  [[ "${drift_out}" == "CLEAN" ]] && return 0

  log_info "scan: drift detected"
  local line src abs_src
  while IFS= read -r line; do
    case "${line}" in
      NEW:\ *) src="${line#NEW: }" ;;
      MODIFIED:\ *) src="${line#MODIFIED: }" ;;
      *) continue ;;
    esac
    abs_src="${wiki}/${src}"
    mtime="$(stat -f %m "${abs_src}" 2>/dev/null || stat -c %Y "${abs_src}" 2>/dev/null || echo 0)"
    age=$((now - mtime))
    if [[ "${age}" -lt 5 ]]; then
      log_info "scan: raw file mtime within last 5s, deferring: ${src}"
      continue
    fi
    if [[ "${line}" == NEW:* ]]; then
      if ! _raw_recovery "${abs_src}"; then
        return 1
      fi
    else
      if ! _emit_legacy_drift_capture "${src}"; then
        return 1
      fi
    fi
  done <<< "${drift_out}"
}

_drift_scan || {
  log_warn "scan: drift scan failed"
  exit 1
}
exit 0
