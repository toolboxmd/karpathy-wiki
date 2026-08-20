#!/bin/bash
# Shared helpers for karpathy-wiki scripts.
# Source this file; don't execute.

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Writes structured log lines to $WIKI_INGEST_LOG (default: .ingest.log in wiki root).
# Format: ISO8601 LEVEL message

_wiki_log() {
  local level="$1"
  shift
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local logfile="${WIKI_INGEST_LOG:-}"
  if [[ -z "${logfile}" ]]; then
    local root
    root="$(wiki_root_from_cwd 2>/dev/null || echo "")"
    if [[ -n "${root}" ]]; then
      logfile="${root}/.ingest.log"
    else
      logfile="/dev/null"
    fi
  fi
  printf '%s %-5s %s\n' "${ts}" "${level}" "$*" >> "${logfile}"
}

log_info()  { _wiki_log "INFO"  "$@"; }
log_warn()  { _wiki_log "WARN"  "$@"; }
log_error() { _wiki_log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Slug / path helpers
# ---------------------------------------------------------------------------

slugify() {
  # Lowercase, replace non-alphanumerics with -, collapse repeats, trim edges.
  local input="$1"
  echo "${input}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//'
}

wiki_file_mtime() {
  # GNU and BSD stat accept overlapping flags with different meanings. Select
  # the platform syntax before invoking stat so a failed probe cannot leak
  # filesystem-description text into arithmetic command substitutions.
  local path="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f %m "${path}"
  else
    stat -c %Y "${path}"
  fi
}

_wiki_deref_pointer() {
  # If <dir>/.wiki-config has role "project-pointer", print the pointed wiki
  # path (the config's `wiki = "..."` value, resolved against <dir>);
  # otherwise print <dir> unchanged.
  #
  # A project-pointer config marks a PROJECT ROOT, not a wiki. Callers that
  # treated the pointer dir as the wiki measured the wrong directory —
  # wiki-status reported no manifest / no git / empty index, and the
  # session-start/stop hooks ran their drift-scan and drain as silent no-ops.
  # Parsing mirrors wiki-resolve.sh's project-pointer case (grep + sed, no
  # python dependency). Target validation stays with the caller so a
  # half-built pointer target fails loudly instead of silently re-pointing.
  local dir="$1"
  local config="${dir}/.wiki-config"
  local role sub
  role="$(grep '^role = ' "${config}" 2>/dev/null | head -1 | sed 's/^role = "\(.*\)"/\1/')"
  if [[ "${role}" == "project-pointer" ]]; then
    sub="$(grep '^wiki = ' "${config}" 2>/dev/null | head -1 | sed 's/^wiki = "\(.*\)"/\1/')"
    [[ -n "${sub}" ]] || sub="./wiki"
    if [[ "${sub}" == /* ]]; then
      echo "${sub}"
    else
      echo "${dir}/${sub#./}"
    fi
    return 0
  fi
  echo "${dir}"
}

wiki_root_from_cwd() {
  # The external workspace runtime is the only routing authority. Tracked
  # project pointers remain structural hints and cannot select main or both.
  local script plan
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wiki_config.py"
  plan="$(python3 "${script}" route-find --cwd "$(pwd -P)" --json 2>/dev/null)" \
    || return 1
  python3 -c 'import json,sys; print(json.load(sys.stdin)["primary_wiki"])' \
    <<< "${plan}"
}

wiki_promotion_policy() {
  # Scanner-created captures are promotable only when the nearest trusted
  # workspace runtime currently selects both and binds this exact project
  # wiki. Missing, malformed, or tracked-only routing always narrows to none.
  local wiki script plan
  wiki="$(cd "$1" 2>/dev/null && pwd -P)" || { printf 'none\n'; return 0; }
  [[ "$(wiki_structural_config_get "${wiki}" role 2>/dev/null || true)" == "project" ]] \
    || { printf 'none\n'; return 0; }
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wiki_config.py"
  plan="$(python3 "${script}" route-find --cwd "${wiki}" --json 2>/dev/null)" \
    || { printf 'none\n'; return 0; }
  python3 - "${wiki}" "${plan}" <<'PY'
import json
import os
import sys

wiki = os.path.realpath(sys.argv[1])
try:
    plan = json.loads(sys.argv[2])
except (OSError, ValueError):
    print("none")
    raise SystemExit
if plan.get("mode") == "both" and plan.get("project_wiki") == wiki:
    print("selective")
else:
    print("none")
PY
}

# ---------------------------------------------------------------------------
# Config read
# ---------------------------------------------------------------------------

_wiki_config_read_file() {
  # _wiki_config_read_file <config_path> <key.subkey>
  local root="$1"
  local key="$2"
  local script
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wiki-config-read.py"
  python3 "${script}" "${root}" "${key}"
}

wiki_structural_config_get() {
  # wiki_structural_config_get <wiki_root> <key.subkey>
  local root="$1"
  local key="$2"
  _wiki_config_read_file "${root}/.wiki-config" "${key}"
}

wiki_runtime_config_get() {
  # wiki_runtime_config_get <wiki_root> <key.subkey>
  local root="$1"
  local key="$2"
  local script
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wiki_config.py"
  python3 "${script}" get --wiki "${root}" --key "${key}"
}

wiki_config_get() {
  # Backward-compatible structural reader. Runtime call sites must use
  # wiki_runtime_config_get explicitly; there is no silent cross-file fallback.
  wiki_structural_config_get "$@"
}
