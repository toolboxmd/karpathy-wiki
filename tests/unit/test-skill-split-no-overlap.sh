#!/bin/bash
# Verify capture and ingest skills don't duplicate rules.
# Specifically: no >80 contiguous-word substring overlap between them
# (excluding files under references/, which are explicitly shared).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CAPTURE="${REPO_ROOT}/skills/karpathy-wiki-capture/SKILL.md"
INGEST="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${CAPTURE}" ]] || fail "capture skill missing"
[[ -f "${INGEST}" ]] || fail "ingest skill missing"

# Use python to find any contiguous 80-word substring that appears in both files.
python3 - "${CAPTURE}" "${INGEST}" <<'PYEOF'
import sys, re

def words(path):
    with open(path) as f:
        text = f.read()
    # Strip code blocks (the canonical schema reference may legitimately appear in both as a fenced ref)
    text = re.sub(r'```.*?```', '', text, flags=re.DOTALL)
    return re.findall(r'\S+', text)

WIN = 80
a = words(sys.argv[1])
b_text = ' '.join(words(sys.argv[2]))

# For every 80-word window in a, check if it appears in b
overlap = None
for i in range(len(a) - WIN + 1):
    window = ' '.join(a[i:i + WIN])
    if window in b_text:
        overlap = window
        break

if overlap:
    print(f"FAIL: 80-word overlap between capture and ingest skills:")
    print(f"  ...{overlap[:200]}...")
    sys.exit(1)
else:
    print("PASS: no >80-word substring overlap")
PYEOF
