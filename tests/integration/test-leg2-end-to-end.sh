#!/bin/bash
# Integration test for Leg 2: bootstrap → per-cwd prompt → capture →
# ingester spawn (mocked). Three modes: project / main / both.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${MAIN}/.wiki-config"
rm -f "${MAIN}/.wiki-config.bak"

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
export WIKI_ORPHANS_DIR="${TESTDIR}/.wiki-orphans"
export CLAUDE_HEADLESS=1
# Isolate $HOME so .wiki-forks.jsonl writes land inside TESTDIR.
export HOME="${TESTDIR}/home"
mkdir -p "${HOME}"

BODY=$(printf 'Real chat-only body that easily exceeds the 1500-byte floor.\n%.0s' {1..40})

# Project mode: pre-configure cwd
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
( cd "${PROJ}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" project ) >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${PROJ}/wiki/.wiki-config"
rm -f "${PROJ}/wiki/.wiki-config.bak"
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "ProjTest" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "project mode capture failed"
# Spawn-ingester runs async; settle.
sleep 0.3
ls "${PROJ}/wiki/.wiki-pending/" | grep -qi projtest || fail "project capture not in proj/wiki/.wiki-pending"
if ls "${MAIN}/.wiki-pending/" 2>/dev/null | grep -qi projtest; then
  fail "project mode leaked capture to main wiki"
fi

# Both mode: pre-configure cwd with fork_to_main = true
BOTH="${TESTDIR}/both"
mkdir -p "${BOTH}"
( cd "${BOTH}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" both ) >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${BOTH}/wiki/.wiki-config"
rm -f "${BOTH}/wiki/.wiki-config.bak"
( cd "${BOTH}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "BothTest" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "both mode capture failed"
sleep 0.3
ls "${BOTH}/wiki/.wiki-pending/" | grep -qi bothtest || fail "both mode: project capture missing"
ls "${MAIN}/.wiki-pending/" | grep -qi bothtest || fail "both mode: main capture missing"
[[ -f "${HOME}/.wiki-forks.jsonl" ]] || fail "both mode: fork-coordination record missing"

# Main-only mode: pre-configure cwd with .wiki-mode
MAIN_ONLY="${TESTDIR}/main-only"
mkdir -p "${MAIN_ONLY}"
( cd "${MAIN_ONLY}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" main ) >/dev/null
( cd "${MAIN_ONLY}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "MainOnlyTest" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "main-only capture failed"
sleep 0.3
ls "${MAIN}/.wiki-pending/" | grep -qi mainonlytest || fail "main-only: capture not in main"

echo "PASS: Leg 2 end-to-end (project / main / both modes)"
