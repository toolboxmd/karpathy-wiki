#!/bin/bash
# Verify wiki-manifest-lock.sh serializes two concurrent manifest writers.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/scripts/wiki-manifest-lock.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${LOCK}" ]] || fail "wiki-manifest-lock.sh missing or not executable"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Write fixture raw files
echo "content A" > "${WIKI}/raw/file-a.md"
echo "content B" > "${WIKI}/raw/file-b.md"

# Run two concurrent register-via-build operations.
# wiki-manifest.py build re-scans raw/ and writes the entire manifest
# wholesale; with the lock, the two runs must serialize.
( bash "${LOCK}" python3 "${REPO_ROOT}/scripts/wiki-manifest.py" build "${WIKI}" ) &
( bash "${LOCK}" python3 "${REPO_ROOT}/scripts/wiki-manifest.py" build "${WIKI}" ) &
wait

# Assert the final manifest is well-formed JSON and contains both files
python3 -c "
import json
with open('${WIKI}/.manifest.json') as f:
    data = json.load(f)
assert 'raw/file-a.md' in data, f'file-a.md missing: {list(data.keys())}'
assert 'raw/file-b.md' in data, f'file-b.md missing: {list(data.keys())}'
print('PASS: both files registered, manifest well-formed')
" || fail "manifest after concurrent writers is corrupted"

echo "PASS: wiki-manifest-lock.sh serializes concurrent writers"
