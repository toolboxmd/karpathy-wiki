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

test_status_on_empty_wiki
test_status_counts_pending
test_status_reports_quality_rollup
test_status_reports_tag_synonyms
echo "ALL PASS"
