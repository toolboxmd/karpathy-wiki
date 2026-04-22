#!/bin/bash
# Capture lifecycle: claim, archive, list.
# Source this file.

wiki_capture_claim() {
  # wiki_capture_claim <wiki_root>
  # Atomically claims a pending capture by renaming to .processing.
  # Prints the claimed path on success.
  # Exits 1 if no pending captures or another claimant won.
  #
  # Atomicity approach: `ln` creates a hard link exclusively (fails if target
  # exists). Then `unlink` removes the original. If two racers call ln+unlink,
  # only one ln succeeds; the loser sees "File exists" and retries the scan.
  # This is stricter than `mv -n` which on macOS BSD silently no-ops on collision.
  local root="$1"
  local pending="${root}/.wiki-pending"
  [[ -d "${pending}" ]] || return 1

  local f claimed
  for f in "${pending}"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && continue
    claimed="${f}.processing"
    # Exclusive hard link. Fails if claimed already exists.
    if ln "${f}" "${claimed}" 2>/dev/null; then
      # We own it. Remove the original. If the unlink fails (another racer
      # already unlinked), that's still OK — we have the .processing handle.
      unlink "${f}" 2>/dev/null || true
      echo "${claimed}"
      return 0
    fi
    # Someone else claimed this one; try the next file.
  done
  return 1
}

wiki_capture_archive() {
  # wiki_capture_archive <wiki_root> <processing-file-path>
  # Moves a successfully-processed capture to .wiki-pending/archive/YYYY-MM/
  local root="$1"
  local processing="$2"
  local date_dir
  date_dir="$(date +%Y-%m)"
  local archive="${root}/.wiki-pending/archive/${date_dir}"
  mkdir -p "${archive}"
  local base
  base="$(basename "${processing}" .processing)"
  mv "${processing}" "${archive}/${base}"
  log_info "archived capture: ${base}"
}

wiki_capture_count_pending() {
  # wiki_capture_count_pending <wiki_root>
  local root="$1"
  local pending="${root}/.wiki-pending"
  [[ -d "${pending}" ]] || { echo 0; return; }
  local count=0
  for f in "${pending}"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && continue
    count=$((count + 1))
  done
  echo "${count}"
}
