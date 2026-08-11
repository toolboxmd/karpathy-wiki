#!/bin/bash
# Source scans run only for the activation that owns them and happen before
# provider availability checks, so new source material is never invisible.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
WIKI="${TMP}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "missing"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.missing]
provider = "codex"
executable = "/definitely/not/a/wiki-provider"
model = "test"
reasoning_effort = "low"
EOF

printf '%s\n' "source material" > "${WIKI}/inbox/source.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${WIKI}/inbox/source.md"

# Scheduled mode ignores a SessionStart activation entirely, including scan.
python3 "${DISPATCH}" tick --wiki "${WIKI}" --source session_start --scan \
  || fail "inactive automatic source should be a no-op"
if compgen -G "${WIKI}/.wiki-pending/drift-*" >/dev/null; then
  fail "inactive SessionStart source unexpectedly scanned the wiki"
fi

# Capture activation never owns source scanning.
set +e
capture_error="$(python3 "${DISPATCH}" tick --wiki "${WIKI}" --source capture --scan 2>&1)"
capture_rc=$?
set -e
[[ "${capture_rc}" -ne 0 ]] || fail "capture --scan should be rejected"
grep -Fq "cannot request a source scan" <<< "${capture_error}" \
  || fail "capture --scan error is not actionable"
if compgen -G "${WIKI}/.wiki-pending/drift-*" >/dev/null; then
  fail "rejected capture activation unexpectedly scanned the wiki"
fi

# Manual scan creates the durable capture even though no provider executable
# is available afterward.
set +e
manual_error="$(python3 "${DISPATCH}" tick --wiki "${WIKI}" --source manual --scan 2>&1)"
manual_rc=$?
set -e
[[ "${manual_rc}" -ne 0 ]] || fail "missing provider should fail after manual scan"
grep -Fq "no configured ingest profile has an available executable" <<< "${manual_error}" \
  || fail "manual provider error is not actionable"
compgen -G "${WIKI}/.wiki-pending/drift-*" >/dev/null \
  || fail "manual scan did not preserve a source capture before provider failure"

echo "PASS: activation mode gates scans and scanning precedes provider checks"
