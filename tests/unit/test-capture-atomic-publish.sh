#!/bin/bash
# Concurrent same-title captures are complete, unique, and never published as
# partially written .md files.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}" "${TMP}/work"
MAIN="${TMP}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
export WIKI_POINTER_FILE="${TMP}/.wiki-pointer"
printf '%s\n' "${MAIN}" > "${WIKI_POINTER_FILE}"
printf '%s\n' "main-only" > "${TMP}/work/.wiki-mode"
BODY="${TMP}/body.md"
python3 - "${BODY}" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text("durable knowledge " * 150, encoding="utf-8")
PY

pids=()
for _ in $(seq 1 10); do
  (
    cd "${TMP}/work"
    WIKI_CAPTURE=1 bash "${WIKI_BIN}" capture \
      --title "Atomic Same Title" --kind chat-only \
      --suggested-action create --body-file "${BODY}" >/dev/null 2>&1
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "${pid}"; done

count="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*atomic-same-title*.md' | wc -l | tr -d ' ')"
[[ "${count}" == 10 ]] || fail "expected 10 unique captures, got ${count}"
while IFS= read -r capture; do
  [[ "$(grep -c '^---$' "${capture}")" -ge 2 ]] || fail "partial frontmatter published: ${capture}"
  [[ "$(wc -c < "${capture}")" -gt 1500 ]] || fail "partial body published: ${capture}"
done < <(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*atomic-same-title*.md')
if find "${MAIN}/.wiki-pending" -maxdepth 1 -name '.capture.*' -print -quit | grep -q .; then
  fail "capture temporary file leaked"
fi

echo "PASS: concurrent captures publish ten complete unique files"
