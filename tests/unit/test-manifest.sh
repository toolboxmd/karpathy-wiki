#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-manifest.py"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/raw"
  echo "alpha" > "${WIKI}/raw/a.md"
  echo "beta"  > "${WIKI}/raw/b.md"
}

teardown() { rm -rf "${TESTDIR}"; }

test_build_manifest_fresh() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  [[ -f "${WIKI}/.manifest.json" ]] || { echo "FAIL: manifest not created"; teardown; exit 1; }
  grep -q 'raw/a.md' "${WIKI}/.manifest.json" || { echo "FAIL: a.md missing"; teardown; exit 1; }
  grep -q 'raw/b.md' "${WIKI}/.manifest.json" || { echo "FAIL: b.md missing"; teardown; exit 1; }
  echo "PASS: test_build_manifest_fresh"
  teardown
}

test_build_includes_sha256() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  python3 -c "
import json, sys
m = json.load(open('${WIKI}/.manifest.json'))
for rel, entry in m.items():
    assert 'sha256' in entry, f'sha256 missing for {rel}'
    assert len(entry['sha256']) == 64, f'sha256 wrong length for {rel}: {entry[\"sha256\"]!r}'
    assert all(c in '0123456789abcdef' for c in entry['sha256']), f'sha256 not hex for {rel}'
print('ok')
" || { echo "FAIL: sha256 check"; teardown; exit 1; }
  echo "PASS: test_build_includes_sha256"
  teardown
}

test_build_preserves_origin_and_referenced_by() {
  setup
  # Seed an existing manifest with origin + referenced_by; build should preserve them.
  cat > "${WIKI}/.manifest.json" <<'EOF'
{
  "raw/a.md": {
    "sha256": "deadbeef",
    "origin": "/tmp/some/source.md",
    "copied_at": "2026-04-20T00:00:00Z",
    "last_ingested": "2026-04-20T00:00:00Z",
    "referenced_by": ["concepts/a-page.md"]
  }
}
EOF
  python3 "${TOOL}" build "${WIKI}"
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
entry = m['raw/a.md']
assert entry['origin'] == '/tmp/some/source.md', f'origin lost: {entry}'
assert entry['referenced_by'] == ['concepts/a-page.md'], f'referenced_by lost: {entry}'
# sha256 should be rewritten to actual hash of alpha + newline
import hashlib
expected = hashlib.sha256(b'alpha\n').hexdigest()
assert entry['sha256'] == expected, f'sha256 wrong: {entry[\"sha256\"]} vs {expected}'
# copied_at should be preserved (it's historical)
assert entry['copied_at'] == '2026-04-20T00:00:00Z', f'copied_at lost: {entry}'
print('ok')
" || { echo "FAIL: preserve check"; teardown; exit 1; }
  echo "PASS: test_build_preserves_origin_and_referenced_by"
  teardown
}

test_diff_clean() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  [[ "${result}" == "CLEAN" ]] || { echo "FAIL: expected CLEAN, got '${result}'"; teardown; exit 1; }
  echo "PASS: test_diff_clean"
  teardown
}

test_diff_detects_new_file() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  echo "gamma" > "${WIKI}/raw/c.md"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  echo "${result}" | grep -q "NEW: raw/c.md" || {
    echo "FAIL: expected NEW detection, got: ${result}"; teardown; exit 1
  }
  echo "PASS: test_diff_detects_new_file"
  teardown
}

test_diff_detects_modified_file() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  echo "ALPHA CHANGED" > "${WIKI}/raw/a.md"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  echo "${result}" | grep -q "MODIFIED: raw/a.md" || {
    echo "FAIL: expected MODIFIED detection, got: ${result}"; teardown; exit 1
  }
  echo "PASS: test_diff_detects_modified_file"
  teardown
}

test_migrate_consolidates_two_manifests() {
  setup
  # Old-style outer manifest (what Phase-A live ~/wiki had).
  cat > "${WIKI}/.manifest.json" <<'EOF'
{
  "raw/a.md": {
    "copied_at": "2026-04-20T00:00:00Z",
    "origin": "/tmp/origin/a.md"
  }
}
EOF
  # Old-style inner manifest (the parallel one we're killing).
  cat > "${WIKI}/raw/.manifest.json" <<'EOF'
{
  "a.md": {
    "source": "/tmp/origin/a.md",
    "added": "2026-04-20T00:00:00Z",
    "referenced_by": ["concepts/a-from-raw.md"]
  },
  "b.md": {
    "source": "/tmp/origin/b.md",
    "added": "2026-04-21T00:00:00Z",
    "referenced_by": ["concepts/b-from-raw.md"]
  }
}
EOF
  python3 "${TOOL}" migrate "${WIKI}"
  # After migrate: one manifest at root, inner deleted, both entries present, sha256 populated.
  [[ ! -f "${WIKI}/raw/.manifest.json" ]] || { echo "FAIL: inner manifest not deleted"; teardown; exit 1; }
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
for rel in ('raw/a.md', 'raw/b.md'):
    assert rel in m, f'{rel} missing after migrate: {list(m.keys())}'
    e = m[rel]
    assert 'sha256' in e and len(e['sha256']) == 64, f'{rel}: sha256 bad {e.get(\"sha256\")!r}'
    assert e['origin'] == '/tmp/origin/' + rel.split('/')[1], f'{rel}: origin {e[\"origin\"]!r}'
    assert 'copied_at' in e, f'{rel}: copied_at missing'
    assert 'last_ingested' in e, f'{rel}: last_ingested missing'
    assert isinstance(e['referenced_by'], list), f'{rel}: referenced_by not a list'
assert 'concepts/a-from-raw.md' in m['raw/a.md']['referenced_by']
assert 'concepts/b-from-raw.md' in m['raw/b.md']['referenced_by']
print('ok')
" || { echo "FAIL: migrate content check"; teardown; exit 1; }
  echo "PASS: test_migrate_consolidates_two_manifests"
  teardown
}

test_migrate_strips_dead_references() {
  setup
  # Inner manifest references a page that does NOT exist on disk.
  cat > "${WIKI}/.manifest.json" <<'EOF'
{}
EOF
  cat > "${WIKI}/raw/.manifest.json" <<'EOF'
{
  "a.md": {
    "source": "/tmp/origin/a.md",
    "added": "2026-04-20T00:00:00Z",
    "referenced_by": ["concepts/real.md", "concepts/dead-ref.md"]
  }
}
EOF
  mkdir -p "${WIKI}/concepts"
  touch "${WIKI}/concepts/real.md"
  python3 "${TOOL}" migrate "${WIKI}"
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
refs = m['raw/a.md']['referenced_by']
assert 'concepts/real.md' in refs, f'real.md dropped: {refs}'
assert 'concepts/dead-ref.md' not in refs, f'dead-ref.md not stripped: {refs}'
print('ok')
" || { echo "FAIL: dead-ref strip check"; teardown; exit 1; }
  echo "PASS: test_migrate_strips_dead_references"
  teardown
}

test_build_manifest_fresh
test_build_includes_sha256
test_build_preserves_origin_and_referenced_by
test_diff_clean
test_diff_detects_new_file
test_diff_detects_modified_file
test_migrate_consolidates_two_manifests
test_migrate_strips_dead_references
echo "ALL PASS"
