#!/bin/bash
# RED: bin/wiki capture must accept --evidence-path and write the path
# (not the literal string "conversation") into capture frontmatter for
# chat-attached and raw-direct kinds.
#
# Bug (0.2.8 #1): bin/wiki:237-258 hardcodes `evidence: "conversation"` for
# all kinds. The skill's iron rule is: capture's `evidence` is the canonical
# source path (or the literal "conversation" only when capture_kind=chat-only
# AND no real path exists). The manifest then carries `origin = capture's
# evidence`. With "conversation" baked in for every kind, the manifest can't
# trace evidence for chat-attached or raw-direct captures.
#
# Test:
#   1. chat-only without --evidence-path → frontmatter has
#      evidence: "conversation" (correct; sanity check)
#   2. chat-attached with --evidence-path /abs → frontmatter has
#      evidence: "/abs"
#   3. chat-attached with NO --evidence-path → exit non-zero with a clear
#      message about chat-attached requiring evidence-path.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${WIKI}" ]] || fail "bin/wiki missing"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FAKE_HOME="${TMP}/home"
mkdir -p "${FAKE_HOME}"
MAIN="${FAKE_HOME}/wiki"
bash "${INIT}" main "${MAIN}" >/dev/null
echo "${MAIN}" > "${FAKE_HOME}/.wiki-pointer"

# Disable spawn so the test doesn't fork actual headless ingesters AND so
# the capture file isn't renamed to .processing before we inspect it. The
# spawner claims (link + unlink) the capture before launching headless.
# Simplest: configure the wiki to use a no-op headless_command, then the
# spawner still claims (which we don't want) but we read the .processing
# file. Cleaner: replace spawn-ingester.sh in the bin/wiki call site by
# putting a stub on $PATH ahead. bin/wiki invokes via "bash <repo>/scripts/
# wiki-spawn-ingester.sh" with absolute path though, so PATH won't catch it.
# Cheapest reliable path: skim either {capture}.md OR {capture}.md.processing.
:

WORKDIR="${TMP}/work"
mkdir -p "${WORKDIR}"
# 0.2.9: bin/wiki capture aborts on unconfigured headless cwd. Configure
# the workdir explicitly so the cases below exercise the evidence-path
# branch, not the unconfigured-cwd abort branch.
echo "main-only" > "${WORKDIR}/.wiki-mode"

run_capture() {
  # Args: extra capture flags via positional. Body via stdin.
  HOME="${FAKE_HOME}" \
  WIKI_POINTER_FILE="${FAKE_HOME}/.wiki-pointer" \
  WIKI_CAPTURE=1 \
  bash -c "cd '${WORKDIR}' && cat | '${WIKI}' capture $* 2>&1"
}

# Find newest capture in pending dir (handles the spawner's .processing rename).
newest_capture() {
  ls -t "${MAIN}/.wiki-pending/" 2>/dev/null \
    | grep -v '^archive$' \
    | grep -v '^schema-proposals$' \
    | head -1
}

# Body: must clear the kind-specific floor. Use 1600+ bytes to clear chat-only.
body_chat=$(python3 -c "print('x ' * 900)")
# chat-attached floor is 1000.
body_attached=$(python3 -c "print('x ' * 600)")

# Case 1: chat-only — evidence must be "conversation".
out=$(echo "${body_chat}" | run_capture --title "T1" --kind chat-only --suggested-action create || true)
echo "${out}" | grep -q "wiki capture: 1 target" || \
  fail "case 1 (chat-only) did not run cleanly: ${out}"

cap1=$(newest_capture)
[[ -n "${cap1}" ]] || fail "case 1: no capture written"
grep -q '^evidence: "conversation"$' "${MAIN}/.wiki-pending/${cap1}" || {
  echo "case 1 frontmatter:"
  head -15 "${MAIN}/.wiki-pending/${cap1}"
  fail "case 1 (chat-only) evidence != \"conversation\""
}

# Case 2: chat-attached with --evidence-path /abs/path
EV="${TMP}/some-evidence.md"
echo "evidence content" > "${EV}"
sleep 1  # ensure unique timestamp slug
out=$(echo "${body_attached}" | run_capture --title "T2" --kind chat-attached --suggested-action create --evidence-path "${EV}" || true)
echo "${out}" | grep -q "wiki capture: 1 target" || \
  fail "case 2 (chat-attached + path) did not run cleanly: ${out}"

cap2=$(newest_capture)
[[ "${cap2}" != "${cap1}" ]] || fail "case 2: same capture as case 1 (timestamp collision?)"
grep -qF "evidence: \"${EV}\"" "${MAIN}/.wiki-pending/${cap2}" || {
  echo "case 2 frontmatter:"
  head -15 "${MAIN}/.wiki-pending/${cap2}"
  fail "case 2 (chat-attached) evidence != ${EV}"
}

# Case 3: chat-attached with NO --evidence-path → must fail.
sleep 1
out=$(echo "${body_attached}" | run_capture --title "T3" --kind chat-attached --suggested-action create) && rc=0 || rc=$?
[[ "${rc}" != 0 ]] || fail "case 3 (chat-attached, no evidence-path) should fail, exit=0"
echo "${out}" | grep -qi "evidence-path" || \
  fail "case 3 error message should mention evidence-path. Got: ${out}"

echo "PASS: bin/wiki capture honors --evidence-path; chat-attached requires it"
