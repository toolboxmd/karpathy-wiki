#!/bin/bash
# Doctor complete fails closed when a 6+ cluster or catalog entity has no job.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
BUILD="${REPO_ROOT}/scripts/wiki-build-index.py"
PATCH="${REPO_ROOT}/scripts/wiki-schema-patch.py"
COMPLETE="${REPO_ROOT}/scripts/wiki-complete-doctor.sh"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-doctor/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

setup() {
  TESTDIR="$(mktemp -d)"
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

write_concept() {
  local path="$1" title="$2"
  cat > "${path}" <<EOF
---
title: "${title}"
type: concepts
tags: [homepage]
sources: []
summary: "${title}"
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
}

write_catalog_entity() {
  cat > "${TESTDIR}/wiki/entities/carl-weische.md" <<'EOF'
---
title: "Carl Weische"
type: entities
tags: [carl-weische]
sources:
  - raw/a.md
  - raw/b.md
  - raw/c.md
  - raw/d.md
  - raw/e.md
  - raw/f.md
summary: "Catalog entity"
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
Catalog body.
EOF
}

test_missing_cluster_job_fails_complete() {
  setup
  local i
  for i in 1 2 3 4 5 6; do
    write_concept "${TESTDIR}/wiki/concepts/home-${i}.md" "Homepage layout ${i}"
  done
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  if WIKI_ROOT="${TESTDIR}/wiki" WIKI_RUN_ID="doc-test-missing" bash "${COMPLETE}"; then
    echo "FAIL: complete succeeded without homepage job"
    teardown
    exit 1
  fi
  echo "PASS: test_missing_cluster_job_fails_complete"
  teardown
}

test_missing_catalog_entity_job_fails_complete() {
  setup
  write_catalog_entity
  if WIKI_ROOT="${TESTDIR}/wiki" WIKI_RUN_ID="doc-test-entity" bash "${COMPLETE}"; then
    echo "FAIL: complete succeeded without catalog entity job"
    teardown
    exit 1
  fi
  echo "PASS: test_missing_catalog_entity_job_fails_complete"
  teardown
}

test_jobs_present_complete_succeeds() {
  setup
  local i
  for i in 1 2 3 4 5 6; do
    write_concept "${TESTDIR}/wiki/concepts/home-${i}.md" "Homepage layout ${i}"
  done
  write_catalog_entity
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  mkdir -p "${TESTDIR}/wiki/.wiki-pending/rewrite-jobs"
  python3 "${REPO_ROOT}/scripts/wiki-required-rewrite-jobs.py" --wiki-root "${TESTDIR}/wiki" \
    | while IFS= read -r token; do
        [[ -n "${token}" ]] || continue
        printf 'job\n' > "${TESTDIR}/wiki/.wiki-pending/rewrite-jobs/${token}.md"
      done
  WIKI_ROOT="${TESTDIR}/wiki" WIKI_RUN_ID="doc-test-ok" bash "${COMPLETE}" \
    || { echo "FAIL: complete failed with jobs present"; teardown; exit 1; }
  echo "PASS: test_jobs_present_complete_succeeds"
  teardown
}

test_skill_names_required_jobs() {
  grep -q 'wiki-required-rewrite-jobs.py' "${SKILL}" \
    || fail "doctor skill must name required-jobs helper"
  echo "PASS: test_skill_names_required_jobs"
}

test_missing_cluster_job_fails_complete
test_missing_catalog_entity_job_fails_complete
test_jobs_present_complete_succeeds
test_skill_names_required_jobs
echo "ALL PASS"
