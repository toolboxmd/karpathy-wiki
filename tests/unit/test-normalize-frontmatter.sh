#!/bin/bash
# Tests for wiki-normalize-frontmatter.py -- a per-page frontmatter fixer.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-normalize-frontmatter.py"

setup() { TESTDIR="$(mktemp -d)"; }
teardown() { rm -rf "${TESTDIR}"; }

test_adds_type_concept_for_concepts_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^type: concept$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: type: concept not added"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_concept_for_concepts_path"
  teardown
}

test_adds_type_entity_for_entities_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/entities"
  cat > "${TESTDIR}/wiki/entities/x.md" <<'EOF'
---
title: "Entity X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/entities/x.md"
  grep -q '^type: entity$' "${TESTDIR}/wiki/entities/x.md" || {
    echo "FAIL: type: entity not added"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_entity_for_entities_path"
  teardown
}

test_adds_type_source_for_sources_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/sources"
  cat > "${TESTDIR}/wiki/sources/x.md" <<'EOF'
---
title: "Source X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/sources/x.md"
  grep -q '^type: source$' "${TESTDIR}/wiki/sources/x.md" || {
    echo "FAIL: type: source not added"; cat "${TESTDIR}/wiki/sources/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_source_for_sources_path"
  teardown
}

test_expands_short_date_to_iso_utc() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: 2026-04-24
updated: 2026-04-24
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^created: "2026-04-24T00:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: created not expanded"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  grep -q '^updated: "2026-04-24T00:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: updated not expanded"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_expands_short_date_to_iso_utc"
  teardown
}

test_adds_updated_when_missing() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^updated: "2026-04-24T12:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: updated not added"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_updated_when_missing"
  teardown
}

test_flattens_nested_sources() {
  setup
  mkdir -p "${TESTDIR}/wiki/entities"
  cat > "${TESTDIR}/wiki/entities/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - conversation: "2026-04-24 chat"
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/entities/x.md"
  grep -q '^  - conversation$' "${TESTDIR}/wiki/entities/x.md" || {
    echo "FAIL: nested sources not flattened"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  }
  if grep -q 'conversation: "2026-04-24 chat"' "${TESTDIR}/wiki/entities/x.md"; then
    echo "FAIL: nested mapping still present"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  fi
  echo "PASS: test_flattens_nested_sources"
  teardown
}

test_is_idempotent() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
type: concept
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  sha_before="$(shasum -a 256 "${TESTDIR}/wiki/concepts/x.md" | awk '{print $1}')"
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  sha_after="$(shasum -a 256 "${TESTDIR}/wiki/concepts/x.md" | awk '{print $1}')"
  [[ "${sha_before}" == "${sha_after}" ]] || {
    echo "FAIL: not idempotent"; teardown; exit 1
  }
  echo "PASS: test_is_idempotent"
  teardown
}

test_migrates_legacy_source_page_schema() {
  # Mirrors the live wiki's sources/2026-04-24-claude-code-dotclaude-sync-plan.md:
  # has raw:, captured_at:, pages_derived: but none of type/tags/sources/created/updated.
  # Normalizer must translate the legacy fields and add the required ones.
  setup
  mkdir -p "${TESTDIR}/wiki/sources" "${TESTDIR}/wiki/raw"
  touch "${TESTDIR}/wiki/raw/2026-04-24-sample.md"
  cat > "${TESTDIR}/wiki/sources/legacy.md" <<'EOF'
---
title: "Source: Legacy"
raw: raw/2026-04-24-sample.md
captured_at: "2026-04-24T13:00:00Z"
pages_derived:
  - concepts/foo.md
---

Legacy body.
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/sources/legacy.md"
  local out
  out="$(cat "${TESTDIR}/wiki/sources/legacy.md")"
  echo "${out}" | grep -q "^type: source$" || {
    echo "FAIL: type missing"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  }
  echo "${out}" | grep -q "^sources:$" || {
    echo "FAIL: sources: block not emitted"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  }
  echo "${out}" | grep -q "^  - raw/2026-04-24-sample.md$" || {
    echo "FAIL: raw:-field not translated to sources:"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  }
  echo "${out}" | grep -q "^created: \"2026-04-24T13:00:00Z\"$" || {
    echo "FAIL: captured_at:-field not translated to created:"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  }
  echo "${out}" | grep -q "^updated: \"2026-04-24T13:00:00Z\"$" || {
    echo "FAIL: updated missing"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  }
  echo "${out}" | grep -q "^tags: " || {
    echo "FAIL: tags missing (stub not added)"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  }
  if echo "${out}" | grep -q "^raw: "; then
    echo "FAIL: raw: key should have been removed"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  fi
  if echo "${out}" | grep -q "^captured_at:"; then
    echo "FAIL: captured_at: key should have been removed"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  fi
  if echo "${out}" | grep -q "^pages_derived:"; then
    echo "FAIL: pages_derived: key should have been removed"; cat "${TESTDIR}/wiki/sources/legacy.md"; teardown; exit 1
  fi
  echo "PASS: test_migrates_legacy_source_page_schema"
  teardown
}

test_adds_type_concept_for_concepts_path
test_adds_type_entity_for_entities_path
test_adds_type_source_for_sources_path
test_expands_short_date_to_iso_utc
test_adds_updated_when_missing
test_flattens_nested_sources
test_migrates_legacy_source_page_schema
test_is_idempotent
echo "ALL PASS"
