#!/bin/bash
# Verify capture and ingest skills don't duplicate rules.
# Specifically: no >80 contiguous-word substring overlap between them
# (excluding files under references/, which are explicitly shared).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CAPTURE="${REPO_ROOT}/skills/karpathy-wiki-capture/SKILL.md"
INGEST="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"
DOCTOR="${REPO_ROOT}/skills/karpathy-wiki-doctor/SKILL.md"
REWRITE="${REPO_ROOT}/skills/karpathy-wiki-rewrite/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${CAPTURE}" ]] || fail "capture skill missing"
[[ -f "${INGEST}" ]] || fail "ingest skill missing"
[[ -f "${DOCTOR}" ]] || fail "doctor skill missing"
[[ -f "${REWRITE}" ]] || fail "rewrite skill missing"

# Use python to find any contiguous 80-word substring that appears in both files.
python3 - "${CAPTURE}" "${INGEST}" "${DOCTOR}" "${REWRITE}" <<'PYEOF'
import sys, re

def words(path):
    with open(path) as f:
        text = f.read()
    # Strip code blocks (the canonical schema reference may legitimately appear in both as a fenced ref)
    text = re.sub(r'```.*?```', '', text, flags=re.DOTALL)
    return re.findall(r'\S+', text)

WIN = 80

def overlap(path_a, path_b):
    a = words(path_a)
    b_text = ' '.join(words(path_b))
    for i in range(len(a) - WIN + 1):
        window = ' '.join(a[i:i + WIN])
        if window in b_text:
            return window
    return None

pairs = (
    ("capture", sys.argv[1], "ingest", sys.argv[2]),
    ("capture", sys.argv[1], "doctor", sys.argv[3]),
    ("ingest", sys.argv[2], "doctor", sys.argv[3]),
    ("capture", sys.argv[1], "rewrite", sys.argv[4]),
    ("ingest", sys.argv[2], "rewrite", sys.argv[4]),
    ("doctor", sys.argv[3], "rewrite", sys.argv[4]),
)
for label_a, path_a, label_b, path_b in pairs:
    found = overlap(path_a, path_b)
    if found:
        print(f"FAIL: 80-word overlap between {label_a} and {label_b} skills:")
        print(f"  ...{found[:200]}...")
        sys.exit(1)

print("PASS: no >80-word substring overlap")
PYEOF
