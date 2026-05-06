#!/bin/bash
# Verify wiki-ingest-now CLI argument contract.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INGEST_NOW="${REPO_ROOT}/scripts/wiki-ingest-now.sh"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${INGEST_NOW}" ]] || fail "wiki-ingest-now.sh missing"

TESTDIR="$(mktemp -d)"
trap 'sleep 0.3; rm -rf "${TESTDIR}" 2>/dev/null || true' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${WIKI}" > "${WIKI_POINTER_FILE}"
export CLAUDE_HEADLESS=1

# Case 1: explicit path bypasses resolver
echo "explicit content" > "${WIKI}/inbox/explicit.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/explicit.md"
bash "${WIKI_BIN}" ingest-now "${WIKI}" >/dev/null \
  || fail "wiki ingest-now <path> failed"
found=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] && found="${f}" && break
done
[[ -n "${found}" ]] || fail "explicit-path ingest-now did not produce drift capture"

# Case 2: no-arg uses cwd-resolved wiki
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
echo "main-only" > "${PROJ}/.wiki-mode"
echo "noarg content" > "${WIKI}/inbox/noarg.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/noarg.md"
( cd "${PROJ}" && bash "${WIKI_BIN}" ingest-now ) >/dev/null \
  || fail "wiki ingest-now (no arg) failed"
# .wiki-mode = main-only resolves to WIKI; noarg.md should produce a drift capture
ls "${WIKI}/.wiki-pending/" | grep noarg >/dev/null \
  || fail "no-arg ingest-now did not pick up noarg.md from cwd-resolved wiki"

# Case 3: explicit path to half-built wiki → exit non-zero
HALF="${TESTDIR}/half"
mkdir -p "${HALF}/.wiki-pending"
echo 'role = "main"' > "${HALF}/.wiki-config"
# schema.md and index.md missing
bash "${WIKI_BIN}" ingest-now "${HALF}" 2>/dev/null \
  && fail "ingest-now on half-built wiki should exit non-zero"

# Case 4: headless + resolver error (cwd unconfigured + pointer = none) → exit non-zero, no orphan
echo "none" > "${WIKI_POINTER_FILE}"
SCRATCH="${TESTDIR}/scratch"
mkdir -p "${SCRATCH}"
( cd "${SCRATCH}" && bash "${WIKI_BIN}" ingest-now ) 2>/dev/null \
  && fail "ingest-now headless + unconfigured + pointer=none should exit non-zero"

echo "PASS: wiki ingest-now argument contract"
