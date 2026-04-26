#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-backfill-quality.py"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/sources" "${WIKI}/queries"
  cat > "${WIKI}/concepts/no-quality.md" <<'EOF'
---
title: "No Quality"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
EOF
  cat > "${WIKI}/concepts/already-has-quality.md" <<'EOF'
---
title: "Already Rated"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: human
---

Body.
EOF
}

teardown() { rm -rf "${TESTDIR}"; }

test_adds_default_quality_block() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  grep -q '^quality:$' "${WIKI}/concepts/no-quality.md" || { echo "FAIL: no-quality.md not patched"; teardown; exit 1; }
  grep -q 'rated_by: ingester' "${WIKI}/concepts/no-quality.md" || { echo "FAIL: rated_by missing"; teardown; exit 1; }
  grep -q 'overall: 3.00' "${WIKI}/concepts/no-quality.md" || { echo "FAIL: overall wrong"; teardown; exit 1; }
  echo "PASS: test_adds_default_quality_block"
  teardown
}

test_preserves_human_rated() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  grep -q 'rated_by: human' "${WIKI}/concepts/already-has-quality.md" || { echo "FAIL: human rating lost"; teardown; exit 1; }
  grep -q 'accuracy: 5' "${WIKI}/concepts/already-has-quality.md" || { echo "FAIL: scores lost"; teardown; exit 1; }
  echo "PASS: test_preserves_human_rated"
  teardown
}

test_is_idempotent() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  sha_before="$(shasum -a 256 "${WIKI}/concepts/no-quality.md" | awk '{print $1}')"
  python3 "${TOOL}" --wiki-root "${WIKI}"
  sha_after="$(shasum -a 256 "${WIKI}/concepts/no-quality.md" | awk '{print $1}')"
  [[ "${sha_before}" == "${sha_after}" ]] || { echo "FAIL: not idempotent"; teardown; exit 1; }
  echo "PASS: test_is_idempotent"
  teardown
}

test_validator_passes_after_backfill() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  python3 "${REPO_ROOT}/scripts/wiki-validate-page.py" --wiki-root "${WIKI}" "${WIKI}/concepts/no-quality.md" 2>/dev/null || {
    # The page references raw/x.md which doesn't exist -- so the other source-check would fail.
    # Create a stub raw file.
    mkdir -p "${WIKI}/raw"
    touch "${WIKI}/raw/x.md"
    python3 "${REPO_ROOT}/scripts/wiki-validate-page.py" --wiki-root "${WIKI}" "${WIKI}/concepts/no-quality.md" || {
      echo "FAIL: validator still failing after backfill"; teardown; exit 1
    }
  }
  echo "PASS: test_validator_passes_after_backfill"
  teardown
}

test_backfill_walks_discovered_categories() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/ideas" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/ideas/foo.md" <<'EOF'
---
title: "Foo"
type: idea
status: open
priority: p2
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---
body
EOF
  python3 "${REPO_ROOT}/scripts/wiki-backfill-quality.py" --wiki-root "${tmp}/wiki"
  grep -q "rated_by: ingester" "${tmp}/wiki/ideas/foo.md" || { echo "FAIL: backfill skipped ideas/"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_backfill_walks_discovered_categories"
}

test_backfill_skips_reserved_directories() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/Clippings" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/Clippings/Post.md" <<'EOF'
some clipping content with no frontmatter
EOF
  python3 "${REPO_ROOT}/scripts/wiki-backfill-quality.py" --wiki-root "${tmp}/wiki"
  if grep -q "rated_by:" "${tmp}/wiki/Clippings/Post.md" 2>/dev/null; then
    echo "FAIL: backfill modified Clippings/"
    rm -rf "${tmp}"
    exit 1
  fi
  rm -rf "${tmp}"
  echo "PASS: test_backfill_skips_reserved_directories"
}

test_backfill_no_longer_walks_sources_when_absent() {
  # Verify the script no longer hardcodes 'sources' — if the dir doesn't exist,
  # there's no error message about it.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  out="$(python3 "${REPO_ROOT}/scripts/wiki-backfill-quality.py" --wiki-root "${tmp}/wiki" 2>&1)"
  # Should not mention 'sources' — there's no sources/ category
  if echo "${out}" | grep -q "sources"; then
    echo "FAIL: output mentions 'sources' when no such category exists"
    rm -rf "${tmp}"; exit 1
  fi
  rm -rf "${tmp}"
  echo "PASS: test_backfill_no_longer_walks_sources_when_absent"
}

test_adds_default_quality_block
test_preserves_human_rated
test_is_idempotent
test_validator_passes_after_backfill
test_backfill_walks_discovered_categories
test_backfill_skips_reserved_directories
test_backfill_no_longer_walks_sources_when_absent
echo "ALL PASS"
