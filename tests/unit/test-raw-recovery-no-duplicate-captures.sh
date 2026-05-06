#!/bin/bash
# RED: two parallel SessionStarts on the same wiki with the same
# unmanifested file in raw/ must produce at most one capture for that file.
#
# Bug (0.2.8 #8): hooks/session-start::_raw_recovery acquires the manifest
# lock, re-checks manifest membership, mv's the file from raw/ → inbox/,
# releases the lock, THEN calls _emit_raw_direct_capture. The window between
# lock release and capture emit lets a concurrent SessionStart see the file
# in inbox during ITS inbox-scan phase and also emit a capture. Even though
# the capture filename hash happens to converge in the inbox-scan path
# (both processes hash inbox/<basename>), the lock-window contract says
# the recovery's capture emit should be ATOMIC with the move under the
# manifest lock — not "atomic by accident of filename hashing."
#
# This test asserts the user-visible property: exactly one capture per
# unmanifested raw file, regardless of how many SessionStarts race.
#
# NOTE: this test exercises the user-visible contract, not the source-line
# location. If the bug fix moves _emit_raw_direct_capture inside the lock
# window, the test still passes by construction. If the implementation drift
# breaks atomicity (e.g. a future change uses a non-deterministic capture
# filename), this test catches it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${HOOK}" ]] || fail "hook missing"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

WIKI="${TMP}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Drop an unmanifested file in raw/ with mtime older than 5 seconds (so the
# mtime-defer in the hook doesn't skip it).
RAW_FILE="${WIKI}/raw/orphan.md"
printf '%s\n' "raw orphan content" > "${RAW_FILE}"
# Backdate by 60s — Linux/macOS portable.
touch -t "$(date -v-60S +%Y%m%d%H%M.%S 2>/dev/null || date -d '60 seconds ago' +%Y%m%d%H%M.%S)" "${RAW_FILE}"

# Run the hook twice in parallel from inside the wiki cwd. The hook resolves
# its target wiki via wiki_root_from_cwd. Drop the loader-injection stdout
# (we don't care about JSON output here).
run_hook() {
  ( cd "${WIKI}" && \
    env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT \
        CLAUDE_PLUGIN_ROOT="${REPO_ROOT}" \
        bash "${HOOK}" >/dev/null 2>&1 )
}

run_hook &
PID1=$!
run_hook &
PID2=$!

wait "${PID1}" "${PID2}" 2>/dev/null || true

# Count captures referencing this raw file. The capture filename is
# deterministic on the file path; we look for the substring "orphan" in
# names AND for evidence: pointing at either raw/orphan.md or
# inbox/orphan.md (the recovery rewrites the path).
orphan_count=0
matched=()
while IFS= read -r c; do
  [[ -f "${c}" ]] || continue
  if grep -qE '^evidence: ".*orphan\.md"' "${c}"; then
    orphan_count=$((orphan_count + 1))
    matched+=("${c}")
  fi
done < <(find "${WIKI}/.wiki-pending" -maxdepth 1 -type f \( -name '*.md' -o -name '*.md.processing' \) 2>/dev/null)

if [[ "${orphan_count}" -gt 1 ]]; then
  echo "Captures found referencing orphan.md:"
  for c in "${matched[@]}"; do
    echo "  - $(basename "${c}")"
    grep '^evidence:' "${c}"
  done
  fail "expected at most 1 capture for orphan.md, got ${orphan_count}"
fi

if [[ "${orphan_count}" -lt 1 ]]; then
  echo "Pending captures:"
  ls -la "${WIKI}/.wiki-pending/" 2>&1
  fail "expected exactly 1 capture for orphan.md, got 0"
fi

echo "Runtime check: parallel SessionStarts produce exactly one raw-recovery capture (orphan_count=${orphan_count})"

# Structural check: inside _raw_recovery, the capture emit must happen
# BEFORE the manifest lock release. The runtime convergence above is robust
# (deterministic capture filenames + atomic create), so the runtime test
# can pass even with the race window open. The structural test verifies
# the iron rule: lock-window covers manifest-check + mv + capture-emit.
python3 - "${HOOK}" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'_raw_recovery\(\)\s*\{(.*?)\n\}\n', src, re.DOTALL)
if not m:
    print("FAIL: could not locate _raw_recovery function body", file=sys.stderr)
    sys.exit(1)
body = m.group(1)

# Find positions of key calls.
emit_idx = body.find("_emit_raw_direct_capture")
release_idx_first = body.find("_manifest_lock_release")
# Allow early-release branches (manifest-membership and missing-source guards
# release and return). Check the LAST release in the function — that's the
# normal-path release after mv.
release_idx_last = body.rfind("_manifest_lock_release")

if emit_idx < 0:
    print("FAIL: _raw_recovery does not call _emit_raw_direct_capture at all",
          file=sys.stderr)
    sys.exit(1)

if release_idx_last < 0:
    print("FAIL: _raw_recovery does not call _manifest_lock_release",
          file=sys.stderr)
    sys.exit(1)

# In the normal path (post-mv), emit must precede the final release.
if emit_idx > release_idx_last:
    print("FAIL: _emit_raw_direct_capture is called AFTER the final "
          "_manifest_lock_release. Capture emit must be inside the lock "
          "window so manifest-check + mv + capture-emit are atomic.",
          file=sys.stderr)
    sys.exit(1)

print("PASS: _raw_recovery emits capture before releasing manifest lock")
PY
