#!/bin/bash
# Tests for wiki-migrate-v2-hardening.sh against the pre-hardening fixture.
# Does NOT touch ~/wiki/. Only runs against a copy of the fixture.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATE="${REPO_ROOT}/scripts/wiki-migrate-v2-hardening.sh"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"
FIXTURE="${REPO_ROOT}/tests/fixtures/pre-hardening-wiki"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  cp -R "${FIXTURE}" "${WIKI}"
}

teardown() { rm -rf "${TESTDIR}"; }

test_migrate_produces_validator_green_wiki() {
  setup
  # Run with --yes so the prompt is skipped.
  "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  # Every page under concepts/entities/sources/queries must pass validator.
  local failures=0
  while IFS= read -r page; do
    if ! python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${page}" 2>/dev/null; then
      echo "validator failure: ${page}"
      python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${page}" 2>&1 || true
      failures=$((failures + 1))
    fi
  done < <(find "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/sources" "${WIKI}/queries" -type f -name "*.md" 2>/dev/null)
  [[ "${failures}" -eq 0 ]] || { echo "FAIL: ${failures} pages failed validator"; teardown; exit 1; }
  echo "PASS: test_migrate_produces_validator_green_wiki"
  teardown
}

test_migrate_consolidates_manifest() {
  setup
  "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  [[ -f "${WIKI}/.manifest.json" ]] || { echo "FAIL: unified manifest missing"; teardown; exit 1; }
  [[ ! -f "${WIKI}/raw/.manifest.json" ]] || { echo "FAIL: legacy inner manifest still present"; teardown; exit 1; }
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
entry = m['raw/2026-04-24-sample.md']
assert 'sha256' in entry and len(entry['sha256']) == 64, f'sha256 bad: {entry}'
refs = entry['referenced_by']
# 'concepts/never-existed.md' was a dead ref in the fixture; must be gone.
assert 'concepts/never-existed.md' not in refs, f'dead ref leaked: {refs}'
# Live refs should be preserved.
assert 'concepts/short-date.md' in refs, f'live ref dropped: {refs}'
assert 'entities/nested-sources.md' in refs, f'live ref dropped: {refs}'
print('ok')
" || { echo "FAIL: manifest content check"; teardown; exit 1; }
  echo "PASS: test_migrate_consolidates_manifest"
  teardown
}

test_migrate_preserves_body_content() {
  setup
  "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  grep -q "^Body\.$" "${WIKI}/concepts/short-date.md" || {
    echo "FAIL: body content clobbered"; teardown; exit 1
  }
  echo "PASS: test_migrate_preserves_body_content"
  teardown
}

test_migrate_creates_backup_when_run_against_live_like_path() {
  setup
  # Pass --backup-dir to control where the backup goes.
  local backup_dir
  backup_dir="${TESTDIR}/backups"
  mkdir -p "${backup_dir}"
  "${MIGRATE}" --yes --wiki-root "${WIKI}" --backup-dir "${backup_dir}" >/dev/null
  local count
  count="$(find "${backup_dir}" -maxdepth 1 -type d -name "wiki.backup-*" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${count}" -eq 1 ]] || { echo "FAIL: expected 1 backup, got ${count}"; teardown; exit 1; }
  echo "PASS: test_migrate_creates_backup_when_run_against_live_like_path"
  teardown
}

test_migrate_rolls_back_on_validator_failure() {
  setup
  # Inject a deliberately-unfixable page that will still fail validator after
  # normalization (e.g. unknown type that doesn't match any directory heuristic).
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/broken.md" <<'EOF'
# No frontmatter at all
Body only.
EOF
  # Expect migration to fail and restore from backup.
  if "${MIGRATE}" --yes --wiki-root "${WIKI}" --backup-dir "${TESTDIR}/b" 2>/dev/null; then
    echo "FAIL: migrate should have failed"; teardown; exit 1
  fi
  # The WIKI should have been restored from backup.
  [[ -f "${WIKI}/concepts/broken.md" ]] || {
    echo "FAIL: restored wiki missing broken.md"; teardown; exit 1
  }
  # And crucially, short-date.md should STILL have its short date (migration rolled back).
  grep -q '^created: 2026-04-24$' "${WIKI}/concepts/short-date.md" || {
    echo "FAIL: short-date.md was not restored to pre-migration state"
    cat "${WIKI}/concepts/short-date.md"
    teardown; exit 1
  }
  echo "PASS: test_migrate_rolls_back_on_validator_failure"
  teardown
}

test_migrate_produces_validator_green_wiki
test_migrate_consolidates_manifest
test_migrate_preserves_body_content
test_migrate_creates_backup_when_run_against_live_like_path
test_migrate_rolls_back_on_validator_failure
echo "ALL PASS"
