#!/bin/bash
# Verify the shared scanner scans inbox/ and creates raw-direct captures.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAN="${REPO_ROOT}/scripts/wiki-scan.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
WIKI_CANONICAL="$(cd "${WIKI}" && pwd -P)"
# Drop a file in inbox/ with mtime in the past (so it's not deferred)
printf '# Test note\n\nSome content for ingestion.\n' > "${WIKI}/inbox/note.md"
# Make it 10 seconds old so the 5-second mtime defer doesn't apply
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/note.md"

# Run the shared source scanner directly; queue dispatch is tested separately.
bash "${SCAN}" "${WIKI}" >/dev/null

# Assert a raw-direct capture appeared in .wiki-pending/
capture=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] || continue
  capture="${f}"
  break
done
[[ -n "${capture}" ]] || fail "no drift- capture appeared in .wiki-pending/"

# Inspect the capture frontmatter for capture_kind: raw-direct
grep -q 'capture_kind: "raw-direct"' "${capture}" \
  || fail "drift capture missing capture_kind: raw-direct"
grep -q "evidence: \"${WIKI_CANONICAL}/inbox/note.md\"" "${capture}" \
  || fail "drift capture evidence path wrong: $(grep '^evidence:' "${capture}")"

# Publication failures must reach the caller instead of being swallowed by a
# later clean manifest check.
WIKI_FAIL="${TESTDIR}/publication-failure"
bash "${INIT}" main "${WIKI_FAIL}" >/dev/null
printf 'source remains durable\n' > "${WIKI_FAIL}/inbox/fail.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${WIKI_FAIL}/inbox/fail.md"
FAKE_BIN="${TESTDIR}/fake-bin"
mkdir -p "${FAKE_BIN}"
cat > "${FAKE_BIN}/mktemp" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "${FAKE_BIN}/mktemp"
PATH="${FAKE_BIN}:${PATH}" bash "${SCAN}" "${WIKI_FAIL}" >/dev/null 2>&1 \
  && fail "scanner swallowed capture publication failure"
[[ -f "${WIKI_FAIL}/inbox/fail.md" ]] || fail "publication failure lost inbox source"

WIKI_MANIFEST_FAIL="${TESTDIR}/manifest-failure"
bash "${INIT}" main "${WIKI_MANIFEST_FAIL}" >/dev/null
printf '{not valid json\n' > "${WIKI_MANIFEST_FAIL}/.manifest.json"
bash "${SCAN}" "${WIKI_MANIFEST_FAIL}" >/dev/null 2>&1 \
  && fail "scanner treated a failed manifest diff as clean"

echo "PASS: inbox/ drift scan creates raw-direct captures"
