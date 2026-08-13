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
  # Walks up from cwd looking for a dir containing .wiki-config.
  # Prints absolute path or exits 1. A found config with role
  # "project-pointer" is dereferenced to its pointed wiki (see
  # _wiki_deref_pointer) — the pointer dir itself is never a wiki.
  #
  # Walk-up rules (paired #11/#9 fix, 0.2.8):
  #   - At leaf cwd: probe BOTH ${dir}/.wiki-config AND ${dir}/wiki/.wiki-config.
  #     The nested-wiki/ probe lets a user `cd ~/proj` and have their
  #     ~/proj/wiki/ project wiki resolve.
  #   - During walk-up: probe ONLY ${dir}/.wiki-config. Probing
  #     ${dir}/wiki/.wiki-config at every level lets cwd inside an unrelated
  #     project leak into ${HOME}/wiki/ (cross-project leak).
  #   - Stop walking when ${dir} == ${HOME}. The user's home dir itself is
  #     not a project root; if the main wiki lives at ${HOME}/wiki/ it must
  #     be reached via the explicit pointer, not by accidental walk-up.
  local dir
  dir="$(pwd)"

  # Leaf probe: nested wiki/ allowed.
  if [[ -f "${dir}/.wiki-config" ]]; then
    _wiki_deref_pointer "${dir}"
    return 0
  fi
  if [[ -f "${dir}/wiki/.wiki-config" ]]; then
    _wiki_deref_pointer "${dir}/wiki"
    return 0
  fi

  # Walk up. Stop at $HOME (exclusive) and at /.
  dir="$(dirname "${dir}")"
  while [[ "${dir}" != "/" && "${dir}" != "${HOME}" ]]; do
    if [[ -f "${dir}/.wiki-config" ]]; then
      _wiki_deref_pointer "${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  return 1
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
  _wiki_config_read_file "${root}/.wiki-config.local" "${key}"
}

wiki_config_get() {
  # Backward-compatible structural reader. Runtime call sites must use
  # wiki_runtime_config_get explicitly; there is no silent cross-file fallback.
  wiki_structural_config_get "$@"
}
