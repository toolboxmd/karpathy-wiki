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
  # Should contain both files
  grep -q 'raw/a.md' "${WIKI}/.manifest.json" || { echo "FAIL: a.md missing"; teardown; exit 1; }
  grep -q 'raw/b.md' "${WIKI}/.manifest.json" || { echo "FAIL: b.md missing"; teardown; exit 1; }
  echo "PASS: test_build_manifest_fresh"
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

test_build_manifest_fresh
test_diff_clean
test_diff_detects_new_file
test_diff_detects_modified_file
echo "ALL PASS"
