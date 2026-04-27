#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATE="${REPO_ROOT}/scripts/wiki-migrate-v2.3.sh"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"

setup_fixture() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/queries" "${WIKI}/ideas" "${WIKI}/raw" "${WIKI}/.wiki-pending" "${WIKI}/.locks"
  touch "${WIKI}/.wiki-config"
  cat > "${WIKI}/concepts/karpathy-wiki-v2.2-architectural-cut.md" <<'EOF'
---
title: "v2.2 Cut"
type: concepts
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  cat > "${WIKI}/concepts/related.md" <<'EOF'
---
title: "Related"
type: concepts
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
See [v2.2](karpathy-wiki-v2.2-architectural-cut.md).
EOF
  ( cd "${WIKI}" && git init -q && git add . && git commit -q -m "fixture" )
}
teardown_fixture() { rm -rf "${TMP}"; }

test_dry_run_lists_planned_mutations() {
  setup_fixture
  out="$(bash "${MIGRATE}" --dry-run --wiki-root "${WIKI}" 2>&1)"
  echo "${out}" | grep -q "would mkdir.*projects/toolboxmd/karpathy-wiki" || { echo "FAIL: missing mkdir plan"; echo "${out}"; teardown_fixture; exit 1; }
  echo "${out}" | grep -q "would git mv.*v2.2-architectural-cut" || { echo "FAIL: missing mv plan"; echo "${out}"; teardown_fixture; exit 1; }
  teardown_fixture
}

test_phase_moves_and_relinks_atomic() {
  setup_fixture
  bash "${MIGRATE}" --phase=moves-and-relinks --wiki-root "${WIKI}" >/dev/null
  [[ -f "${WIKI}/projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.2-architectural-cut.md" ]] || {
    echo "FAIL: page not moved"; teardown_fixture; exit 1
  }
  grep -q "/projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.2-architectural-cut.md" "${WIKI}/concepts/related.md" || {
    echo "FAIL: link not rewritten"
    cat "${WIKI}/concepts/related.md"
    teardown_fixture; exit 1
  }
  teardown_fixture
}

test_idempotent_phase_moves_and_relinks() {
  setup_fixture
  bash "${MIGRATE}" --phase=moves-and-relinks --wiki-root "${WIKI}" >/dev/null
  ( cd "${WIKI}" && git add -A && git commit -q -m "phase moves+relinks" )
  out="$(bash "${MIGRATE}" --phase=moves-and-relinks --wiki-root "${WIKI}" 2>&1)"
  echo "${out}" | grep -qiE "already migrated|skipped|no-op" || {
    echo "FAIL: re-run did not detect already-migrated state"
    echo "${out}"
    teardown_fixture; exit 1
  }
  teardown_fixture
}

test_phase_index_rebuild_creates_index_md() {
  setup_fixture
  bash "${MIGRATE}" --phase=moves-and-relinks --wiki-root "${WIKI}" >/dev/null
  ( cd "${WIKI}" && git add -A && git commit -q -m "phase moves+relinks" )
  bash "${MIGRATE}" --phase=index-rebuild --wiki-root "${WIKI}" >/dev/null
  [[ -f "${WIKI}/index.md" ]] || { echo "FAIL: root index.md not generated"; teardown_fixture; exit 1; }
  [[ -f "${WIKI}/projects/_index.md" ]] || { echo "FAIL: projects/_index.md not generated"; teardown_fixture; exit 1; }
  teardown_fixture
}

test_validator_passes_after_atomic_phase() {
  # CRITICAL: the atomic moves+relinks phase must leave the wiki in a state
  # where the validator passes (no broken links). This is corrigendum C-G's
  # whole point -- splitting moves and relinks would produce broken state.
  setup_fixture
  bash "${MIGRATE}" --phase=moves-and-relinks --wiki-root "${WIKI}" >/dev/null
  for p in $(find "${WIKI}" -name "*.md" -not -path "*/raw/*" -not -path "*/.wiki-pending/*"); do
    python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${p}" || {
      echo "FAIL: validator failed on ${p}"
      python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${p}" 2>&1 | head
      teardown_fixture; exit 1
    }
  done
  teardown_fixture
}

test_dry_run_lists_planned_mutations
test_phase_moves_and_relinks_atomic
test_idempotent_phase_moves_and_relinks
test_phase_index_rebuild_creates_index_md
test_validator_passes_after_atomic_phase
echo "all tests passed"
