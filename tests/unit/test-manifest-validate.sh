#!/bin/bash
# Test: wiki-manifest.py validate catches empty origin and bad-shape origin.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${REPO_ROOT}/scripts/wiki-manifest.py"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/raw"
touch "${tmp}/wiki/.wiki-config"
cat > "${tmp}/wiki/.manifest.json" <<'EOF'
{
  "raw/good-path.md": {
    "sha256": "abc123",
    "origin": "/Users/x/research/good.md",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": ["concepts/good.md"]
  },
  "raw/good-conv.md": {
    "sha256": "def456",
    "origin": "conversation",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": ["concepts/good.md"]
  },
  "raw/bad-empty.md": {
    "sha256": "ghi789",
    "origin": "",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  },
  "raw/bad-typename.md": {
    "sha256": "jkl012",
    "origin": "file",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  },
  "raw/bad-relpath.md": {
    "sha256": "mno345",
    "origin": "research/foo.md",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  }
}
EOF

# Run validate; expect exit 1 with violations for the 3 bad entries.
output="$(python3 "${MANIFEST}" validate "${tmp}/wiki" 2>&1 || true)"

# Should mention all 3 bad entries.
if ! echo "${output}" | grep -q "bad-empty.md.*empty origin"; then
  echo "FAIL: expected bad-empty.md flagged. Output: ${output}"
  exit 1
fi
if ! echo "${output}" | grep -q "bad-typename.md.*literal evidence_type"; then
  echo "FAIL: expected bad-typename.md flagged. Output: ${output}"
  exit 1
fi
if ! echo "${output}" | grep -q "bad-relpath.md.*absolute path"; then
  echo "FAIL: expected bad-relpath.md flagged. Output: ${output}"
  exit 1
fi
# Should NOT flag the two good entries.
if echo "${output}" | grep -q "good-path.md\|good-conv.md"; then
  echo "FAIL: validator falsely flagged a good entry. Output: ${output}"
  exit 1
fi

# Final exit code check.
python3 "${MANIFEST}" validate "${tmp}/wiki" >/dev/null 2>&1 && {
  echo "FAIL: expected non-zero exit on bad manifest"
  exit 1
}

echo "PASS: wiki-manifest.py validate catches empty / typename / relative-path origins"
echo "ALL PASS"
