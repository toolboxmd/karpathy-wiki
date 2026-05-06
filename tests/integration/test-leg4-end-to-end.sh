#!/bin/bash
# Integration test for Leg 4: ingester emits issue lines, wiki status
# summarizes them, wiki issues renders them.
#
# Note: this test does NOT spawn a real `claude -p` ingester. Instead,
# it directly invokes wiki-issue-log.sh to simulate issue emission,
# and verifies the read surface (status + issues render) consumes the
# log correctly.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
LOG="${REPO_ROOT}/scripts/wiki-issue-log.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Simulate 5 issue emissions across 3 types
for i in {1..3}; do
  bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-${i}" \
    --capture ".wiki-pending/c${i}.md" --page "concepts/p${i}.md" \
    --type broken-cross-link --severity warn \
    --detail "Links to /concepts/missing-${i}.md which does not exist."
done

bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-x" \
  --capture ".wiki-pending/cx.md" --page "concepts/x.md" \
  --type contradiction --severity error \
  --detail "Page x.md claims X but page y.md says not-X."

bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-y" \
  --capture ".wiki-pending/cy.md" --page "concepts/y.md" \
  --type schema-drift --severity info \
  --detail "Has type: concept (singular); should be type: concepts."

# 1. wiki issues renders all 5
output=$(cd "${WIKI}" && bash "${WIKI_BIN}" issues)
echo "${output}" | grep -q '5 reported' || fail "wiki issues missing total"
echo "${output}" | grep -q '## Broken' || fail "wiki issues missing broken-cross-link group"
echo "${output}" | grep -q '## Contradictions' || fail "wiki issues missing contradictions group"
echo "${output}" | grep -q '## Schema' || fail "wiki issues missing schema-drift group"

# 2. wiki status shows the count summary
output=$(cd "${WIKI}" && bash "${WIKI_BIN}" status)
echo "${output}" | grep -q -i 'issues' || fail "wiki status missing Issues section"
echo "${output}" | grep -q '3 broken' || fail "wiki status missing broken-link count"

# 3. Concurrent flock works under load
for i in {1..10}; do
  ( bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-conc-${i}" \
      --capture "c.md" --page "p.md" --type orphan --severity info \
      --detail "concurrent ${i}" ) &
done
wait
final_count=$(wc -l < "${WIKI}/.ingest-issues.jsonl")
[[ "${final_count}" -eq 15 ]] || fail "concurrent appends produced wrong line count: ${final_count}"

# All 15 lines must be valid JSON
python3 -c "
import json
with open('${WIKI}/.ingest-issues.jsonl') as f:
    for i, line in enumerate(f):
        try:
            json.loads(line.strip())
        except json.JSONDecodeError as e:
            print(f'line {i+1} corrupted: {e}'); exit(1)
print('all 15 lines valid')
" || fail "concurrent appends corrupted JSONL"

echo "PASS: Leg 4 end-to-end (issue log + render + status)"
