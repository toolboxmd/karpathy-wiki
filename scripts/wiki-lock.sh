#!/bin/bash
# Page-level locking for wiki ingesters.
# Source this file; don't execute.

# Stale-lock age in seconds. Matches superpowers' short-timeout finding
# (see superpowers-skill-style-guide.md, issue #1237 lesson).
WIKI_LOCK_STALE_SECONDS="${WIKI_LOCK_STALE_SECONDS:-300}"  # 5 minutes

_wiki_lock_path() {
  # _wiki_lock_path <wiki_root> <page-relative-path>
  # Returns absolute path of the lockfile for that page.
  local root="$1"
  local page="$2"
  local slug
  slug="$(echo "${page}" | tr '/' '-' | tr '.' '-')"
  echo "${root}/.locks/${slug}.lock"
}

_wiki_lock_is_stale() {
  # _wiki_lock_is_stale <lockfile-path>
  # Exits 0 if file mtime is older than WIKI_LOCK_STALE_SECONDS.
  local lockfile="$1"
  [[ -f "${lockfile}" ]] || return 1
  local mtime now age
  mtime="$(stat -f %m "${lockfile}" 2>/dev/null || stat -c %Y "${lockfile}" 2>/dev/null)"
  now="$(date +%s)"
  age=$((now - mtime))
  [[ "${age}" -gt "${WIKI_LOCK_STALE_SECONDS}" ]]
}

wiki_lock_acquire() {
  # wiki_lock_acquire <wiki_root> <page-relative-path> <capture_id>
  # Returns 0 on success, 1 on held-by-another.
  # Reclaims stale locks before acquiring.
  local root="$1"
  local page="$2"
  local capture_id="$3"

  mkdir -p "${root}/.locks"
  local lockfile
  lockfile="$(_wiki_lock_path "${root}" "${page}")"

  # Reclaim stale lock if present.
  if _wiki_lock_is_stale "${lockfile}"; then
    log_warn "reclaiming stale lock: ${lockfile}"
    rm -f "${lockfile}"
  fi

  # Atomic create-exclusive. `set -o noclobber` makes `>` refuse to overwrite
  # an existing file — that is the exclusivity guarantee. Brace groups do NOT
  # scope shell options, so noclobber persists after this block; that is
  # intentional (we want subsequent plain `>` in this function to honor it).
  # The write below uses `>|` which is bash's explicit "force-override
  # noclobber for this one redirect" — required because the lockfile now
  # exists (we just created it) and plain `>` would be refused.
  if { set -o noclobber; > "${lockfile}"; } 2>/dev/null; then
    local pid="$$"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"pid":%d,"started_at":"%s","capture_id":"%s"}\n' \
      "${pid}" "${ts}" "${capture_id}" >| "${lockfile}"
    log_info "acquired lock: ${page} (capture=${capture_id})"
    return 0
  fi
  return 1
}

wiki_lock_release() {
  # wiki_lock_release <wiki_root> <page-relative-path>
  local root="$1"
  local page="$2"
  local lockfile
  lockfile="$(_wiki_lock_path "${root}" "${page}")"
  rm -f "${lockfile}"
  log_info "released lock: ${page}"
}

wiki_lock_wait_and_acquire() {
  # wiki_lock_wait_and_acquire <wiki_root> <page-relative-path> <capture_id> [timeout_seconds]
  # Polls until free or timeout. Default timeout 30 seconds.
  local root="$1"
  local page="$2"
  local capture_id="$3"
  local timeout="${4:-30}"
  local elapsed=0
  local poll=1  # seconds between checks

  while ! wiki_lock_acquire "${root}" "${page}" "${capture_id}" 2>/dev/null; do
    sleep "${poll}"
    elapsed=$((elapsed + poll))
    if [[ "${elapsed}" -ge "${timeout}" ]]; then
      log_error "lock acquire timeout: ${page}"
      return 1
    fi
  done
  return 0
}
