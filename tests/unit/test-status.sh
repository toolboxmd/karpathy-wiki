#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

test_status_on_empty_wiki() {
  setup
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "role: main" || { echo "FAIL: role missing"; teardown; exit 1; }
  echo "${output}" | grep -q "pending: 0" || { echo "FAIL: pending missing"; teardown; exit 1; }
  echo "${output}" | grep -q "total pages:" || { echo "FAIL: total pages missing"; teardown; exit 1; }
  echo "${output}" | grep -q "pages below 3.5 quality:" || { echo "FAIL: quality line missing"; teardown; exit 1; }
  echo "${output}" | grep -q "tag synonyms flagged:" || { echo "FAIL: synonyms line missing"; teardown; exit 1; }
  echo "${output}" | grep -q "^index.md:" || { echo "FAIL: status output missing index.md field"; teardown; exit 1; }
  echo "PASS: test_status_on_empty_wiki"
  teardown
}

test_status_counts_pending() {
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c1.md"
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c2.md"
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "pending: 2" || {
    echo "FAIL: expected 'pending: 2', got:"
    echo "${output}"
    teardown; exit 1
  }
  echo "PASS: test_status_counts_pending"
  teardown
}

test_status_reports_quality_rollup() {
  setup
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/low.md" <<'EOF'
---
title: "Low"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 2
  completeness: 2
  signal: 2
  interlinking: 2
  overall: 2.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

body
EOF
  cat > "${WIKI}/concepts/high.md" <<'EOF'
---
title: "High"
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
  rated_by: ingester
---

body
EOF
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "pages below 3.5 quality: 1" || {
    echo "FAIL: quality rollup wrong. output: ${output}"; teardown; exit 1
  }
  echo "PASS: test_status_reports_quality_rollup"
  teardown
}

test_status_reports_tag_synonyms() {
  setup
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/a.md" <<'EOF'
---
title: "A"
type: concept
tags: [dentistry]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---
body
EOF
  cat > "${WIKI}/concepts/b.md" <<'EOF'
---
title: "B"
type: concept
tags: [dentistries]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---
body
EOF
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -qE "tag synonyms flagged: [1-9]" || {
    echo "FAIL: tag synonym report missing. output: ${output}"; teardown; exit 1
  }
  echo "PASS: test_status_reports_tag_synonyms"
  teardown
}

test_status_walks_discovered_categories() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/ideas" "${tmp}/wiki/raw" "${tmp}/wiki/.wiki-pending"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/concepts/foo.md"
  echo "stub" > "${tmp}/wiki/ideas/bar.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1 || true)"
  echo "${out}" | grep -q "concepts" && echo "${out}" | grep -q "ideas" || { echo "FAIL: status missing categories"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_walks_discovered_categories"
}

test_status_includes_ideas_directory() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/ideas" "${tmp}/wiki/raw"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/ideas/foo.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "ideas" || { echo "FAIL: ideas/ not surfaced"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_includes_ideas_directory"
}

test_status_depth_violation_count() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts/a/b/c/d" "${tmp}/wiki/raw"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/concepts/a/b/c/d/deep.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "categories exceeding depth 4" || { echo "FAIL: depth-violation line absent"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_depth_violation_count"
}

test_status_soft_ceiling_line() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/raw"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  for c in a b c d e f g h i; do
    mkdir -p "${tmp}/wiki/${c}"
    echo "stub" > "${tmp}/wiki/${c}/x.md"
  done
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "category count vs soft-ceiling" || { echo "FAIL: soft-ceiling line absent"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_soft_ceiling_line"
}

test_status_on_empty_wiki
test_status_counts_pending
test_status_reports_quality_rollup
test_status_reports_tag_synonyms
test_status_walks_discovered_categories
test_status_includes_ideas_directory
test_status_depth_violation_count
test_status_soft_ceiling_line
echo "ALL PASS"
