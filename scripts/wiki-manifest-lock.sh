#!/bin/bash
# wiki-manifest-lock.sh — exclusive lock wrapper for manifest mutations.
#
# Usage: wiki-manifest-lock.sh <command> [args...]
#
# The command's first reference to a wiki must be discoverable so we can
# locate the lock file. Convention: the first arg that looks like a path
# AND contains .wiki-config is treated as the wiki root.
#
# Cross-platform: prefers flock(1) when available (Linux); on macOS where
# flock(1) is absent, falls back to set -o noclobber + polling. Either
# path provides exclusive serialization across processes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

# Find the wiki root by inspecting args for a path containing .wiki-config.
wiki=""
for arg in "$@"; do
  if [[ -d "${arg}" && -f "${arg}/.wiki-config" ]]; then
    wiki="${arg}"
    break
  fi
done

if [[ -z "${wiki}" ]]; then
  echo >&2 "wiki-manifest-lock: cannot locate wiki root in args"
  exit 1
fi

lock_dir="${wiki}/.locks"
mkdir -p "${lock_dir}"
lock_file="${lock_dir}/manifest.lock"

# Stale-lock reclaim threshold (seconds). Matches WIKI_LOCK_STALE_SECONDS
# in wiki-lock.sh; manifest mutations finish in < 100 ms, so anything older
# than 5 minutes is a crashed holder.
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
  # Linux path: flock(1) gives blocking advisory FD lock.
  exec 9>"${lock_file}"
  flock 9
  "$@"
  status=$?
  exit "${status}"
else
  # macOS / no-flock path: spin on atomic create.
  poll=0.05
  elapsed=0
  max_wait=120  # 2 minutes; manifest writes finish in < 1s
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
      echo >&2 "wiki-manifest-lock: timeout waiting for ${lock_file}"
      exit 1
    fi
  done

  trap 'rm -f "${lock_file}"' EXIT
  "$@"
  status=$?
  rm -f "${lock_file}"
  trap - EXIT
  exit "${status}"
fi
