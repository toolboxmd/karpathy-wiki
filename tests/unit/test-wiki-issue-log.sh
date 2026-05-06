#!/bin/bash
# Verify wiki-issue-log.sh:
# - validates --type against the 8-value enum
# - serializes concurrent appends via flock
# - truncates over-length lines to 4 KB total
# - escapes JSON correctly (special chars in detail)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG="${REPO_ROOT}/scripts/wiki-issue-log.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${LOG}" ]] || fail "wiki-issue-log.sh missing"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Case 1: enum validation — invalid type rejected
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-1" --capture "c.md" \
  --page "concepts/foo.md" --type bad-type --severity warn --detail "x" 2>/dev/null \
  && fail "invalid --type should reject"

# Case 2: valid append
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-1" --capture "c.md" \
  --page "concepts/foo.md" --type broken-cross-link --severity warn \
  --detail "Links to /concepts/missing.md which does not exist." \
  --suggested-action "Remove link or create stub" \
  || fail "valid append failed"
[[ -f "${WIKI}/.ingest-issues.jsonl" ]] || fail "issues log not created"

# Verify the line is valid JSON
python3 -c "
import json
with open('${WIKI}/.ingest-issues.jsonl') as f:
    line = f.readline().strip()
data = json.loads(line)
assert data['issue_type'] == 'broken-cross-link', f'bad issue_type: {data}'
assert data['severity'] == 'warn'
assert data['detail'].startswith('Links to')
"

# Case 3: special chars in detail (quotes, newlines, backslashes)
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-2" --capture "c.md" \
  --page "concepts/bar.md" --type contradiction --severity info \
  --detail 'Page X claims "foo\nis bar" but page Y says \\backslash "no it'"'"'s not"' \
  || fail "special-chars append failed"
python3 -c "
import json
lines = open('${WIKI}/.ingest-issues.jsonl').readlines()
assert len(lines) == 2, f'expected 2 lines, got {len(lines)}'
data = json.loads(lines[1].strip())
assert 'foo' in data['detail'], f'detail mangled: {data[\"detail\"]}'
assert 'backslash' in data['detail']
"

# Case 4: over-length truncation (5 KB detail → ≤ 4 KB total line)
LARGE_DETAIL=$(python3 -c "print('x' * 5000)")
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-3" --capture "c.md" \
  --page "concepts/baz.md" --type stale-claim --severity warn \
  --detail "${LARGE_DETAIL}" \
  || fail "large-detail append failed"

last_line=$(tail -1 "${WIKI}/.ingest-issues.jsonl")
line_size=$(echo -n "${last_line}" | wc -c)
[[ "${line_size}" -le 4096 ]] || fail "over-length line not truncated: ${line_size} bytes"
echo "${last_line}" | grep -q '\[truncated\]' || fail "truncated line missing marker"

# Case 5: concurrent flock-serialized appends
TMPLINES="${TESTDIR}/.tmplines"
> "${TMPLINES}"
for i in {1..5}; do
  ( bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-conc-${i}" --capture "c.md" \
      --page "concepts/conc-${i}.md" --type orphan --severity info \
      --detail "concurrent ${i}" ) &
done
wait

# Verify all 5 appended lines are well-formed JSON
final_lines=$(wc -l < "${WIKI}/.ingest-issues.jsonl")
[[ "${final_lines}" -eq 8 ]] || fail "expected 8 lines after 5 concurrent appends + 3 prior, got ${final_lines}"

# Each line must parse as JSON
python3 -c "
import json
with open('${WIKI}/.ingest-issues.jsonl') as f:
    for i, line in enumerate(f):
        try:
            json.loads(line.strip())
        except json.JSONDecodeError as e:
            print(f'line {i+1} corrupted: {e}'); exit(1)
print('PASS: all lines parse')
" || fail "concurrent appends corrupted JSONL"

echo "PASS: wiki-issue-log.sh"
