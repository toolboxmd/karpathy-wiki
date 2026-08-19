#!/bin/bash
# Verify the shared scanner scans inbox/ and creates raw-direct captures.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAN="${REPO_ROOT}/scripts/wiki-scan.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
trap 'rm -rf "${TESTDIR}"' EXIT
export XDG_CONFIG_HOME="${TESTDIR}/config-home"

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
grep -q '^promotion_policy: "none"$' "${capture}" \
  || fail "main-wiki scanner capture should not be promotable"

# Scanner policy comes from the same authoritative workspace route as the CLI.
PROJECT_WORKSPACE="${TESTDIR}/project-workspace"
PROJECT_WIKI="${PROJECT_WORKSPACE}/wiki"
mkdir -p "${PROJECT_WORKSPACE}"
bash "${INIT}" project "${PROJECT_WIKI}" "${WIKI}" >/dev/null
python3 "${CONFIG}" route-set --workspace "${PROJECT_WORKSPACE}" --mode both \
  --project-wiki "${PROJECT_WIKI}" --main-wiki "${WIKI}" >/dev/null
printf 'selectively reusable source\n' > "${PROJECT_WIKI}/inbox/selective.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${PROJECT_WIKI}/inbox/selective.md"
bash "${SCAN}" "${PROJECT_WIKI}" >/dev/null
selective_capture="$(find "${PROJECT_WIKI}/.wiki-pending" -maxdepth 1 -type f -name 'drift-*.md' -print -quit)"
grep -q '^promotion_policy: "selective"$' "${selective_capture}" \
  || fail "both-mode scanner capture is not selective"

# A tracked legacy fork flag cannot authorize promotion without a local route.
TRACKED_WORKSPACE="${TESTDIR}/tracked-marker-workspace"
TRACKED_WIKI="${TRACKED_WORKSPACE}/wiki"
mkdir -p "${TRACKED_WORKSPACE}"
bash "${INIT}" project "${TRACKED_WIKI}" "${WIKI}" >/dev/null
cat > "${TRACKED_WORKSPACE}/.wiki-config" <<'EOF'
role = "project-pointer"
wiki = "./wiki"
fork_to_main = true
main = "/tmp/forged-main"
EOF
printf 'must stay local\n' > "${TRACKED_WIKI}/inbox/local.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${TRACKED_WIKI}/inbox/local.md"
bash "${SCAN}" "${TRACKED_WIKI}" >/dev/null
local_capture="$(find "${TRACKED_WIKI}/.wiki-pending" -maxdepth 1 -type f -name 'drift-*.md' -print -quit)"
grep -q '^promotion_policy: "none"$' "${local_capture}" \
  || fail "tracked routing marker authorized scanner promotion"

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
