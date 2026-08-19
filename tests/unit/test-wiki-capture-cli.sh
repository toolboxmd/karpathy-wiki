#!/bin/bash
# Verify bin/wiki capture body-input contract, headless fallback,
# orphan preservation. Runtime config is intentionally absent so captures stay
# durable and inspectable while dispatcher setup is reported separately.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null

# Hermetic $HOME — required so bin/wiki capture's silent-bootstrap branch
# (added in 0.2.7) doesn't read the developer's real ~/wiki when this test
# unsets WIKI_POINTER_FILE.
FAKE_HOME="${TESTDIR}/home"
mkdir -p "${FAKE_HOME}"
export HOME="${FAKE_HOME}"
export XDG_CONFIG_HOME="${TESTDIR}/config-home"
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
export HOME_FOR_ORPHANS="${FAKE_HOME}"
export WIKI_ORPHANS_DIR="${HOME_FOR_ORPHANS}/.wiki-orphans"
export CLAUDE_HEADLESS=1  # Force headless mode in tests

# Case 1: chat-only via stdin
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
python3 "${CONFIG}" route-set --workspace "${PROJ}" --mode main \
  --main-wiki "${MAIN}" >/dev/null
BODY=$(printf 'A real chat-only body that exceeds 1500 bytes.\n%.0s' {1..40})
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "Test" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  || fail "chat-only via stdin failed"
ls "${MAIN}/.wiki-pending/" | grep -q '\.md$' || fail "no capture appeared in main pending"
first_capture="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*.md' -print -quit)"
grep -Eq '^capture_id: "cap-[a-f0-9]+"$' "${first_capture}" || fail "capture lacks portable capture_id"
grep -q '^promotion_policy: "none"$' "${first_capture}" || fail "main capture should not be promotable"

# The public CLI accepts each canonical action and rejects injected scalars.
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "AutoAction" --kind chat-only --suggested-action auto ) >/dev/null 2>&1 \
  || fail "documented auto suggested action was rejected"
auto_capture="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -iname '*autoaction*.md' -print -quit)"
[[ -n "${auto_capture}" ]] || fail "auto suggested action did not publish a capture"
[[ "$(grep -c '^suggested_action: "auto"$' "${auto_capture}")" -eq 1 ]] \
  || fail "auto capture did not emit exactly one canonical action scalar"

unsupported_err="${TESTDIR}/unsupported-action.err"
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "UnsupportedAction" --kind chat-only --suggested-action delete ) \
    >/dev/null 2>"${unsupported_err}" \
  && fail "unsupported suggested action unexpectedly succeeded"
grep -q '^wiki capture: --suggested-action must be create, update, augment, or auto$' "${unsupported_err}" \
  || fail "unsupported suggested action validation message is incomplete"

BOTH_WORKSPACE="${TESTDIR}/both-workspace"
BOTH_WIKI="${BOTH_WORKSPACE}/wiki"
mkdir -p "${BOTH_WORKSPACE}"
bash "${INIT}" project "${BOTH_WIKI}" "${MAIN}" >/dev/null
python3 "${CONFIG}" route-set --workspace "${BOTH_WORKSPACE}" --mode both \
  --project-wiki "${BOTH_WIKI}" --main-wiki "${MAIN}" >/dev/null
forged_action=$'create"\npromotion_policy: "none'
( cd "${BOTH_WORKSPACE}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "Injected routing" --kind chat-only \
    --suggested-action "${forged_action}" ) >/dev/null 2>&1 \
  && fail "newline-bearing suggested action unexpectedly succeeded"
if find "${BOTH_WIKI}/.wiki-pending" -type f -name '*.md*' -print -quit | grep -q .; then
  fail "rejected suggested action published a capture"
fi

# Both writes one project capture with selective promotion metadata. It does
# not copy the raw capture into main before the ingester chooses publication.
main_before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
( cd "${BOTH_WORKSPACE}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "SelectiveBoth" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  || fail "both-mode capture failed"
both_capture="$(find "${BOTH_WIKI}/.wiki-pending" -maxdepth 1 -type f -iname '*selectiveboth*.md' -print -quit)"
[[ -n "${both_capture}" ]] || fail "both mode wrote no project capture"
grep -q '^promotion_policy: "selective"$' "${both_capture}" \
  || fail "both-mode project capture lacks selective promotion policy"
grep -q '^promotion_decision: null$' "${both_capture}" \
  || fail "both-mode project capture lacks undecided promotion state"
[[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" -eq "${main_before}" ]] \
  || fail "both mode copied the raw capture directly into main"

# Case 2: chat-only via --body-file
TMPBODY="$(mktemp)"
echo "${BODY}" > "${TMPBODY}"
( cd "${PROJ}" && bash "${WIKI_BIN}" capture --title "Test2" --kind chat-only --suggested-action create --body-file "${TMPBODY}" ) >/dev/null 2>&1 \
  || fail "chat-only via --body-file failed"

# Invalid UTF-8 is rejected before any queue write and without a traceback.
INVALID_BODY="${TESTDIR}/invalid-utf8.bin"
perl -e 'print "x" x 1600; print chr(255)' > "${INVALID_BODY}"
pending_before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
invalid_err="${TESTDIR}/invalid-utf8.err"
( cd "${PROJ}" && bash "${WIKI_BIN}" capture --title "InvalidUtf8" \
    --kind chat-only --suggested-action create --body-file "${INVALID_BODY}" ) \
    >/dev/null 2>"${invalid_err}" \
  && fail "invalid UTF-8 body unexpectedly succeeded"
grep -qi 'valid UTF-8' "${invalid_err}" || fail "invalid UTF-8 error is not actionable"
! grep -q 'Traceback' "${invalid_err}" || fail "invalid UTF-8 leaked a traceback"
[[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" -eq "${pending_before}" ]] \
  || fail "invalid UTF-8 changed the pending queue"

# Case 3: missing body (no stdin, no --body-file) → error
( cd "${PROJ}" && bash "${WIKI_BIN}" capture --title "Test3" --kind chat-only --suggested-action create < /dev/null ) 2>/dev/null \
  && fail "missing body should error"

# Case 4: max-body limit (256 KB)
HUGE_BODY=$(yes "x" | head -c 270000)
( cd "${PROJ}" && echo "${HUGE_BODY}" | bash "${WIKI_BIN}" capture --title "Huge" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "body > 256 KB should error"

# Case 5: headless + unconfigured cwd + no pointer → orphan-preserve
rm -f "${WIKI_POINTER_FILE}"
LOCAL_ONLY_WORKSPACE="${TESTDIR}/local-only-workspace"
LOCAL_ONLY="${LOCAL_ONLY_WORKSPACE}/wiki"
mkdir -p "${LOCAL_ONLY_WORKSPACE}"
bash "${INIT}" project "${LOCAL_ONLY}" >/dev/null
python3 "${CONFIG}" route-set --workspace "${LOCAL_ONLY_WORKSPACE}" --mode project \
  --project-wiki "${LOCAL_ONLY}" >/dev/null
( cd "${LOCAL_ONLY_WORKSPACE}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "LocalOnly" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  || fail "configured project-only capture failed without main pointer"
local_capture="$(find "${LOCAL_ONLY}/.wiki-pending" -maxdepth 1 -type f -iname '*localonly*.md' -print -quit)"
grep -q '^promotion_policy: "none"$' "${local_capture}" \
  || fail "project-only capture has wrong promotion policy"

SCRATCH="${TESTDIR}/scratch"
mkdir -p "${SCRATCH}"
( cd "${SCRATCH}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "OrphanTest" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "headless + no pointer + unconfigured cwd should abort"
[[ -d "${WIKI_ORPHANS_DIR}" ]] || fail "no orphan dir created"
ls "${WIKI_ORPHANS_DIR}/" | grep -q '\.md$' || fail "no orphan file in $WIKI_ORPHANS_DIR/"

# Case 6: headless + unconfigured cwd + valid pointer → abort with orphan
# (0.2.9 — was silent auto-select main-only pre-0.2.9; now the user must
# explicitly choose project|main|both via `wiki use`).
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
SCRATCH2="${TESTDIR}/scratch2"
mkdir -p "${SCRATCH2}"
( cd "${SCRATCH2}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "AutoMain" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  && fail "headless + valid pointer + unconfigured should abort, not silently auto-select main-only"
[[ ! -f "${SCRATCH2}/.wiki-mode" ]] || fail "abort path must not write .wiki-mode (was: $(cat "${SCRATCH2}/.wiki-mode" 2>/dev/null))"
ls "${WIKI_ORPHANS_DIR}/" | grep -q '\.md$' || fail "no orphan written for unconfigured-cwd abort"

echo "PASS: bin/wiki capture body input + headless fallback + orphan preservation"
