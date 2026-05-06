#!/bin/bash
# RED: bin/wiki capture must abort with an orphan + stderr nudge when cwd
# is unconfigured AND running headless.
#
# Bug (0.2.9 field-test, 2026-05-06): bin/wiki:207-210 silently writes
# `main-only` into <cwd>/.wiki-mode and proceeds when:
#   - resolver returns exit 11 (cwd unconfigured), AND
#   - headless mode is detected (no TTY / WIKI_CAPTURE / CLAUDE_AGENT_PARENT).
#
# Symptom: agent in any project dir captures silently to ~/wiki/, the user
# never gets to choose project|main|both. The stale `.wiki-mode` file is
# left behind in the project dir, so future captures continue routing to
# main without prompting.
#
# Fix: mirror the three existing orphan-on-abort paths (pointer-missing,
# fork-to-main + no pointer, exit 12/13/14). Headless + cwd-unconfigured
# becomes a fourth orphan path: write body to ~/.wiki-orphans/, print a
# `wiki use project|main|both` nudge to stderr, exit non-zero. The agent
# reads stderr and surfaces the choice to the user.
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

# Project-like cwd with NO .wiki-config and NO .wiki-mode.
WORKDIR="${TMP}/proj"
mkdir -p "${WORKDIR}"

# Body must clear the chat-only floor (1500 bytes).
body=$(python3 -c "print('x ' * 900)")

# Run capture in headless mode (WIKI_CAPTURE set), with overridden HOME so
# the orphans dir lands inside TMP.
out=$(echo "${body}" | \
  HOME="${FAKE_HOME}" \
  WIKI_POINTER_FILE="${FAKE_HOME}/.wiki-pointer" \
  WIKI_ORPHANS_DIR="${TMP}/orphans" \
  WIKI_CAPTURE=1 \
  bash -c "cd '${WORKDIR}' && '${WIKI}' capture --title 'T' --kind chat-only --suggested-action create" 2>&1 || true)
rc=$?

# Must exit non-zero (today's bug: silent auto-select makes it exit 0).
if [[ "${rc}" == 0 ]]; then
  fail "capture exited 0 in unconfigured cwd; expected abort with non-zero exit. Output:\n${out}"
fi

# Must NOT have created a .wiki-mode in the project dir (today's bug: it
# persists `main-only` here, polluting future captures).
if [[ -f "${WORKDIR}/.wiki-mode" ]]; then
  fail "capture wrote ${WORKDIR}/.wiki-mode; abort path must not pollute cwd. Contents:\n$(cat "${WORKDIR}/.wiki-mode")"
fi

# Must have saved an orphan (the body must not be lost).
orphans=$(find "${TMP}/orphans" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [[ "${orphans}" -lt 1 ]]; then
  fail "capture did not write an orphan; body would be lost. Output:\n${out}"
fi

# Stderr must include a nudge mentioning `wiki use` so the agent knows how
# to route the user.
if ! echo "${out}" | grep -qE 'wiki use (project|main|both)'; then
  fail "capture stderr did not mention 'wiki use project|main|both' nudge. Output:\n${out}"
fi

echo "PASS: bin/wiki capture aborts with orphan + nudge in unconfigured headless cwd"
