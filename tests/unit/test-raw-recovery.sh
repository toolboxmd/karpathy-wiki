#!/bin/bash
# Verify raw/ recovery: an unmanifested file in raw/ is moved to inbox/
# and processed via the standard queue.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAN="${REPO_ROOT}/scripts/wiki-scan.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'sleep 0.3; rm -rf "${TESTDIR}" 2>/dev/null || true' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Drop a file directly in raw/ (simulating user accident)
echo "user accidentally dropped this here" > "${WIKI}/raw/accident.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/accident.md"

# Verify file is NOT in manifest (it was created outside the ingester)
python3 -c "
import json
with open('${WIKI}/.manifest.json') as f:
    data = json.load(f)
assert 'raw/accident.md' not in data, 'precondition failed: accident.md is already in manifest'
"

# Run scanner — should recover
bash "${SCAN}" "${WIKI}" >/dev/null

# After recovery, accident.md should be in inbox/, not raw/
[[ -f "${WIKI}/inbox/accident.md" ]] || fail "raw recovery did not move file to inbox/"
[[ ! -f "${WIKI}/raw/accident.md" ]] || fail "raw recovery left file in raw/"

# A drift capture should exist for the inbox/ file
found=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] && found="${f}" && break
done
[[ -n "${found}" ]] || fail "raw recovery did not produce drift capture"

# .ingest.log should have a WARN line
grep -q 'raw-recovery' "${WIKI}/.ingest.log" \
  || fail ".ingest.log missing raw-recovery WARN"

# Collision case: drop another file with the same basename in raw/, and one
# already in inbox/ from the prior recovery.
echo "second collision" > "${WIKI}/raw/accident.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/accident.md"
bash "${SCAN}" "${WIKI}" >/dev/null
[[ -f "${WIKI}/inbox/accident.1.md" ]] || fail "collision-suffix accident.1.md missing"

# A failed move must not publish a capture for a path that does not exist.
WIKI_FAIL="${TESTDIR}/move-failure"
bash "${INIT}" main "${WIKI_FAIL}" >/dev/null
echo "must remain in raw" > "${WIKI_FAIL}/raw/stays.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${WIKI_FAIL}/raw/stays.md"
FAKE_BIN="${TESTDIR}/fake-bin"
mkdir -p "${FAKE_BIN}"
cat > "${FAKE_BIN}/mv" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "${FAKE_BIN}/mv"
PATH="${FAKE_BIN}:${PATH}" bash "${SCAN}" "${WIKI_FAIL}" >/dev/null 2>&1 \
  && fail "scanner reported success after raw recovery move failure"
[[ -f "${WIKI_FAIL}/raw/stays.md" ]] || fail "failed recovery lost the source file"
[[ ! -e "${WIKI_FAIL}/inbox/stays.md" ]] || fail "failed recovery created an inbox target"
find "${WIKI_FAIL}/.wiki-pending" -maxdepth 1 -type f -name 'drift-*' | grep -q . \
  && fail "failed recovery published a capture for a missing target"

echo "PASS: raw/ recovery"
