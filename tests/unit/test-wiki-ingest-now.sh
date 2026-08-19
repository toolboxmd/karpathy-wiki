#!/bin/bash
# Verify wiki-ingest-now CLI argument contract.
set -e
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INGEST_NOW="${REPO_ROOT}/scripts/wiki-ingest-now.sh"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${INGEST_NOW}" ]] || fail "wiki-ingest-now.sh missing"

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
trap 'sleep 0.3; rm -rf "${TESTDIR}" 2>/dev/null || true' EXIT
export XDG_CONFIG_HOME="${TESTDIR}/config-home"

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "test"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test]
provider = "codex"
model = "test"
reasoning_effort = "low"

[settings]
auto_commit = false
EOF
export WIKI_DISPATCH_TEST_MODE=1
export WIKI_DISPATCH_TEST_PROVIDER_MODE=success_no_complete
export WIKI_DISPATCH_TEST_NO_REFILL=1

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
python3 "${CONFIG}" route-set --workspace "${PROJ}" --mode main \
  --main-wiki "${WIKI}" >/dev/null
echo "noarg content" > "${WIKI}/inbox/noarg.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/noarg.md"
( cd "${PROJ}" && bash "${WIKI_BIN}" ingest-now ) >/dev/null \
  || fail "wiki ingest-now (no arg) failed"
# The authoritative main route resolves to WIKI.
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
