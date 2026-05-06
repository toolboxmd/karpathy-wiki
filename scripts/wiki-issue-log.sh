#!/bin/bash
# wiki-issue-log.sh — append a structured issue line to <wiki>/.ingest-issues.jsonl.
#
# Usage:
#   wiki-issue-log.sh --wiki <path> --ingester-run <id> --capture <relpath> \
#       --page <relpath> --type <enum> --severity <info|warn|error> \
#       --detail "<prose>" [--suggested-action "<prose>"]
#
# Enum for --type: broken-cross-link | contradiction | schema-drift |
#                  stale-claim | tag-drift | quality-concern | orphan | other
#
# Concurrency: appends are serialized via flock on
# <wiki>/.locks/ingest-issues.lock. Atomic per line.
#
# Truncation: total JSON line size capped at 4096 bytes; --detail is
# truncated with "... [truncated]" suffix if needed.

set -uo pipefail

VALID_TYPES="broken-cross-link contradiction schema-drift stale-claim tag-drift quality-concern orphan other"
VALID_SEVERITIES="info warn error"
MAX_LINE=4096

wiki=""; run=""; capture=""; page=""; itype=""; severity=""; detail=""; action=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wiki) wiki="$2"; shift 2 ;;
    --ingester-run) run="$2"; shift 2 ;;
    --capture) capture="$2"; shift 2 ;;
    --page) page="$2"; shift 2 ;;
    --type) itype="$2"; shift 2 ;;
    --severity) severity="$2"; shift 2 ;;
    --detail) detail="$2"; shift 2 ;;
    --suggested-action) action="$2"; shift 2 ;;
    *) echo >&2 "wiki-issue-log: unknown arg: $1"; exit 1 ;;
  esac
done

# Required args
for v in wiki run capture page itype severity detail; do
  eval "[[ -n \"\${${v}}\" ]]" || { echo >&2 "wiki-issue-log: --${v} required"; exit 1; }
done

# Validate enums
echo " ${VALID_TYPES} " | grep -q " ${itype} " \
  || { echo >&2 "wiki-issue-log: invalid --type '${itype}'; valid: ${VALID_TYPES}"; exit 1; }
echo " ${VALID_SEVERITIES} " | grep -q " ${severity} " \
  || { echo >&2 "wiki-issue-log: invalid --severity '${severity}'; valid: ${VALID_SEVERITIES}"; exit 1; }

[[ -d "${wiki}" ]] || { echo >&2 "wiki-issue-log: wiki path missing: ${wiki}"; exit 1; }

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log_file="${wiki}/.ingest-issues.jsonl"
lock_dir="${wiki}/.locks"
mkdir -p "${lock_dir}"
lock_file="${lock_dir}/ingest-issues.lock"

# Build the JSON line via Python (handles all escaping correctly + truncation).
# Pass fields via environment variables so we don't have to thread them through
# multiple layers of shell quoting.
line=$(
  WIKI_ISSUE_TS="${ts}" \
  WIKI_ISSUE_RUN="${run}" \
  WIKI_ISSUE_CAPTURE="${capture}" \
  WIKI_ISSUE_PAGE="${page}" \
  WIKI_ISSUE_TYPE="${itype}" \
  WIKI_ISSUE_SEV="${severity}" \
  WIKI_ISSUE_DETAIL="${detail}" \
  WIKI_ISSUE_ACTION="${action}" \
  WIKI_ISSUE_MAX="${MAX_LINE}" \
  python3 <<'PYEOF'
import json, os

max_line = int(os.environ["WIKI_ISSUE_MAX"])
obj = {
    "reported_at":   os.environ["WIKI_ISSUE_TS"],
    "ingester_run":  os.environ["WIKI_ISSUE_RUN"],
    "capture":       os.environ["WIKI_ISSUE_CAPTURE"],
    "page":          os.environ["WIKI_ISSUE_PAGE"],
    "issue_type":    os.environ["WIKI_ISSUE_TYPE"],
    "severity":      os.environ["WIKI_ISSUE_SEV"],
    "detail":        os.environ["WIKI_ISSUE_DETAIL"],
}
action = os.environ.get("WIKI_ISSUE_ACTION", "")
if action:
    obj["suggested_action"] = action

line = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
if len(line) > max_line:
    suffix = "... [truncated]"
    overflow = len(line) - max_line + len(suffix)
    detail_trim_len = max(0, len(obj["detail"]) - overflow)
    obj["detail"] = obj["detail"][:detail_trim_len] + suffix
    line = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
print(line)
PYEOF
) || { echo >&2 "wiki-issue-log: failed to encode JSON line"; exit 1; }

# Append under exclusive lock. Cross-platform: prefers flock(1) on Linux;
# on macOS (no flock) falls back to set -o noclobber + polling, mirroring
# scripts/wiki-manifest-lock.sh.
STALE_SECONDS="${WIKI_LOCK_STALE_SECONDS:-300}"

_lock_is_stale() {
  local f="$1"
  [[ -f "${f}" ]] || return 1
  local mtime now age
  mtime="$(stat -f %m "${f}" 2>/dev/null || stat -c %Y "${f}" 2>/dev/null)"
  now="$(date +%s)"
  age=$((now - mtime))
  [[ "${age}" -gt "${STALE_SECONDS}" ]]
}

if command -v flock >/dev/null 2>&1; then
  exec 9>"${lock_file}"
  flock 9
  printf '%s\n' "${line}" >> "${log_file}"
  exec 9>&-
else
  poll=0.05
  elapsed=0
  max_wait=30
  while true; do
    if _lock_is_stale "${lock_file}"; then
      rm -f "${lock_file}"
    fi
    if { set -o noclobber; printf '%d\n' "$$" > "${lock_file}"; } 2>/dev/null; then
      break
    fi
    sleep "${poll}"
    elapsed=$(awk -v e="${elapsed}" -v p="${poll}" 'BEGIN{print e+p}')
    if awk -v e="${elapsed}" -v m="${max_wait}" 'BEGIN{exit !(e>m)}'; then
      echo >&2 "wiki-issue-log: timeout waiting for ${lock_file}"
      exit 1
    fi
  done
  trap 'rm -f "${lock_file}"' EXIT
  printf '%s\n' "${line}" >> "${log_file}"
  rm -f "${lock_file}"
  trap - EXIT
fi

exit 0
