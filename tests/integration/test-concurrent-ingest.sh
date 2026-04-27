#!/bin/bash
# Concurrency smoke test: two ingesters race on ONE shared page.
# We simulate the ingester's minimal work (claim + lock + append + release).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lock.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-capture.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  # Two captures, both targeting the same page.
  cat > "${WIKI}/.wiki-pending/c1.md" <<'EOF'
---
title: "from capture 1"
suggested_pages: [concepts/shared.md]
---
content-from-c1
EOF
  cat > "${WIKI}/.wiki-pending/c2.md" <<'EOF'
---
title: "from capture 2"
suggested_pages: [concepts/shared.md]
---
content-from-c2
EOF
  # Pre-create the shared page.
  mkdir -p "${WIKI}/concepts"
  echo "# Shared Page" > "${WIKI}/concepts/shared.md"
}

teardown() { rm -rf "${TESTDIR}"; }

# Simulated ingester: claim a capture, lock the target page, append its title,
# release, archive the capture. Uses wait-and-acquire to exercise the polling path.
fake_ingester() {
  local wiki="$1"
  local claimed
  claimed="$(wiki_capture_claim "${wiki}" 2>/dev/null)" || return 0  # nothing to claim
  local title
  title="$(grep -oE '^title:.*' "${claimed}" | head -1 | sed 's/title: *//; s/"//g')"
  # Acquire the shared page lock (wait if held).
  wiki_lock_wait_and_acquire "${wiki}" "concepts/shared.md" "$(basename "${claimed}")" 10 || return 1
  # Append (mimics read-before-write: append preserves existing content).
  printf "\n- ingest entry from: %s\n" "${title}" >> "${wiki}/concepts/shared.md"
  # Simulate minimal work time so races are real.
  sleep 0.1
  wiki_lock_release "${wiki}" "concepts/shared.md"
  # Archive.
  wiki_capture_archive "${wiki}" "${claimed}"
}

test_two_ingesters_no_data_loss() {
  setup
  # Start both in parallel. They should both complete successfully.
  (fake_ingester "${WIKI}") &
  local pid1=$!
  (fake_ingester "${WIKI}") &
  local pid2=$!
  wait "${pid1}"
  wait "${pid2}"

  # Both entries must be present in the page.
  local c1_present c2_present
  c1_present=$(grep -c "from capture 1" "${WIKI}/concepts/shared.md" || echo 0)
  c2_present=$(grep -c "from capture 2" "${WIKI}/concepts/shared.md" || echo 0)

  if [[ "${c1_present}" -eq 1 ]] && [[ "${c2_present}" -eq 1 ]]; then
    echo "PASS: test_two_ingesters_no_data_loss"
  else
    echo "FAIL: data loss. c1=${c1_present} c2=${c2_present}"
    cat "${WIKI}/concepts/shared.md"
    teardown; exit 1
  fi

  # Both captures must be archived (neither pending nor processing).
  local pending_n processing_n
  pending_n=$(find "${WIKI}/.wiki-pending" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  processing_n=$(find "${WIKI}/.wiki-pending" -maxdepth 1 -name "*.processing" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${pending_n}" -eq 0 ]] && [[ "${processing_n}" -eq 0 ]]; then
    echo "PASS: test_both_captures_archived"
  else
    echo "FAIL: leftover state. pending=${pending_n} processing=${processing_n}"
    teardown; exit 1
  fi

  # No stale locks.
  local locks_n
  locks_n=$(find "${WIKI}/.locks" -maxdepth 1 -name "*.lock" -type f 2>/dev/null | wc -l | tr -d ' ')
  [[ "${locks_n}" -eq 0 ]] || {
    echo "FAIL: stale locks remaining (${locks_n})"
    teardown; exit 1
  }
  echo "PASS: no_stale_locks"

  teardown
}

test_concurrent_build_index_same_subtree_serializes() {
  # Two background invocations of wiki-build-index.py on the same subtree
  # should not deadlock. Lock-slug matches wiki-lock.sh, so the lock
  # acquisition serializes both runs.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/projects/a" "${tmp}/wiki/raw" "${tmp}/wiki/.locks"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/projects/a/x.md" <<'EOF'
---
title: "X"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  # Background one, foreground the other
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all &
  BG_PID=$!
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all
  wait "${BG_PID}"
  [[ -f "${tmp}/wiki/projects/_index.md" ]] || { echo "FAIL: _index not generated"; rm -rf "${tmp}"; exit 1; }
  [[ -f "${tmp}/wiki/index.md" ]] || { echo "FAIL: root index.md not generated"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
}

test_ancestor_lock_path_ordering_no_deadlock() {
  # Two sequential build-index calls on a deep tree should release locks
  # cleanly between runs (no held-chain deadlock).
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/projects/a/b/c" "${tmp}/wiki/raw" "${tmp}/wiki/.locks"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/projects/a/b/c/x.md" <<'EOF'
---
title: "X"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all
  # No locks should remain after a clean run
  remaining_locks="$(ls "${tmp}/wiki/.locks" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${remaining_locks}" != "0" ]]; then
    echo "FAIL: ${remaining_locks} locks remained; expected 0"
    ls "${tmp}/wiki/.locks"
    rm -rf "${tmp}"; exit 1
  fi
  # Run again — should still work cleanly
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all
  rm -rf "${tmp}"
}

test_two_ingesters_no_data_loss
test_concurrent_build_index_same_subtree_serializes
echo "PASS: test_concurrent_build_index_same_subtree_serializes"
test_ancestor_lock_path_ordering_no_deadlock
echo "PASS: test_ancestor_lock_path_ordering_no_deadlock"
echo "ALL PASS"
