#!/bin/bash
# Integration test for Leg 2: bootstrap → per-cwd prompt → capture →
# durable queue write. Three modes: project / main / both. Project-pointer
# targets carry test-only runtime trust; no real provider is invoked.
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

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
export WIKI_ORPHANS_DIR="${TESTDIR}/.wiki-orphans"
export CLAUDE_HEADLESS=1
export HOME="${TESTDIR}/home"
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1
mkdir -p "${HOME}"
# Capture dispatch is part of this integration path, but provider execution is
# not. Keep the detached worker local and deterministic instead of invoking a
# real Codex process that can outlive this fixture's temporary HOME.
export WIKI_DISPATCH_TEST_MODE=1
export WIKI_DISPATCH_TEST_PROVIDER_MODE=hold
export WIKI_DISPATCH_TEST_PROVIDER_SECONDS=2
export WIKI_DISPATCH_TEST_NO_REFILL=1

BODY=$(printf 'Real chat-only body that easily exceeds the 1500-byte floor.\n%.0s' {1..40})

write_test_runtime() {
  local fork="${2:-false}"
  cat > "$1/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "codex_medium"

[ingest.profiles.codex_medium]
provider = "codex"
model = "gpt-test"
reasoning_effort = "medium"

[routing]
fork_to_main = ${fork}
EOF
}

# Project mode: pre-configure cwd
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
( cd "${PROJ}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" project ) >/dev/null
write_test_runtime "${PROJ}/wiki"
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "ProjTest" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  || fail "project mode capture failed"
# Capture is durable even though this fixture has no local dispatcher profile.
ls "${PROJ}/wiki/.wiki-pending/" | grep -qi projtest || fail "project capture not in proj/wiki/.wiki-pending"
if ls "${MAIN}/.wiki-pending/" 2>/dev/null | grep -qi projtest; then
  fail "project mode leaked capture to main wiki"
fi

# Both mode: initial capture is project-only. The project ingester later makes
# the selective promotion decision.
BOTH="${TESTDIR}/both"
mkdir -p "${BOTH}"
( cd "${BOTH}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" both ) >/dev/null
write_test_runtime "${BOTH}/wiki" true
( cd "${BOTH}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "BothTest" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  || fail "both mode capture failed"
ls "${BOTH}/wiki/.wiki-pending/" | grep -qi bothtest || fail "both mode: project capture missing"
if ls "${MAIN}/.wiki-pending/" 2>/dev/null | grep -qi bothtest; then
  fail "both mode published the original capture to main before semantic judgment"
fi
# The dispatcher may be holding the capture as .processing. Wait for the
# unsuccessful test worker to durably requeue the original .md before reading
# it, rather than assuming the accepted name remains stable between commands.
both_capture=""
for _ in $(seq 1 200); do
  both_capture="$(find "${BOTH}/wiki/.wiki-pending" -maxdepth 1 -type f -iname '*bothtest*.md' -print -quit)"
  [[ -n "${both_capture}" ]] && break
  sleep 0.05
done
[[ -n "${both_capture}" ]] || {
  [[ -f "${BOTH}/wiki/.ingest-runs.jsonl" ]] && cat "${BOTH}/wiki/.ingest-runs.jsonl" >&2
  fail "both mode capture was not durably requeued after worker exit"
}
grep -q '^promotion_policy: "selective"' "${both_capture}" \
  || fail "both mode capture lacks selective promotion policy"
[[ ! -e "${HOME}/.wiki-forks.jsonl" ]] \
  || fail "both mode wrote a legacy simultaneous-fork record"

# Main-only mode: pre-configure cwd with .wiki-mode
MAIN_ONLY="${TESTDIR}/main-only"
mkdir -p "${MAIN_ONLY}"
( cd "${MAIN_ONLY}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" main ) >/dev/null
( cd "${MAIN_ONLY}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "MainOnlyTest" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  || fail "main-only capture failed"
sleep 0.3
ls "${MAIN}/.wiki-pending/" | grep -qi mainonlytest || fail "main-only: capture not in main"

echo "PASS: Leg 2 end-to-end (project / main / both modes)"
