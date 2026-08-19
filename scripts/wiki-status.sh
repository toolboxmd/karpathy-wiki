#!/bin/bash
# Read-only wiki health report.
#
# Usage: wiki-status.sh <wiki_root>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-capture.sh"

wiki="$1"
[[ -n "${wiki}" ]] || { echo >&2 "usage: wiki-status.sh <wiki_root>"; exit 1; }
[[ -d "${wiki}" ]] || { echo >&2 "not a directory: ${wiki}"; exit 1; }
[[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "not a wiki: ${wiki}"; exit 1; }

role="$(wiki_config_get "${wiki}" role)"
pending="$(wiki_capture_count_pending "${wiki}")"
processing="$(find "${wiki}/.wiki-pending" -maxdepth 1 -name "*.processing" 2>/dev/null | wc -l | tr -d ' ')"
locks="$(find "${wiki}/.locks" -maxdepth 1 -name "*.lock" 2>/dev/null | wc -l | tr -d ' ')"
total_pages=0  # filled below from discovered category counts (content set only)

last_ingest="never"
if [[ -f "${wiki}/.manifest.json" ]]; then
  last_ingest="$(python3 -c '
import json, sys
try:
    m = json.load(open(sys.argv[1] + "/.manifest.json"))
    if not isinstance(m, dict) or not m:
        sys.exit(0)
    iso = max(
        v.get("last_ingested", "")
        for v in m.values()
        if isinstance(v, dict) and v.get("last_ingested")
    )
    print(iso[:10] if iso else "")
except Exception:
    pass
' "${wiki}" 2>/dev/null)"
  [[ -z "${last_ingest}" ]] && last_ingest="never"
fi

# Drift
drift="$(python3 "${SCRIPT_DIR}/wiki-manifest.py" diff "${wiki}" 2>/dev/null | head -1)"

# Git state
git_status="n/a"
if command -v git >/dev/null 2>&1 && (cd "${wiki}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  if (cd "${wiki}" && git diff --quiet && git diff --cached --quiet); then
    git_status="clean"
  else
    git_status="dirty"
  fi
fi

# v2.3: read categories from wiki-discover.py
SCRIPT_DIR_LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
discovered_json="$(python3 "${SCRIPT_DIR_LOCAL}/wiki-discover.py" --wiki-root "${wiki}" 2>/dev/null)" || {
  echo "ERROR: wiki-discover.py failed; status report degraded" >&2
  exit 1
}

# Total pages = sum of per-category content counts (already excludes
# _index.md, reserved dirs, and dot-dirs in wiki-discover.py).
total_pages="$(echo "${discovered_json}" | python3 -c "
import json, sys
print(sum(json.load(sys.stdin)['counts'].values()))
")"

# Quality rollup: count pages with overall < 3.5 (walks all discovered categories)
below_35=0
while IFS= read -r page; do
  overall="$(grep -oE '^  overall: [0-9]+\.[0-9]+$' "${page}" | head -1 | awk '{print $2}')"
  if [[ -n "${overall}" ]]; then
    if awk -v v="${overall}" 'BEGIN { exit !(v < 3.5) }'; then
      below_35=$((below_35 + 1))
    fi
  fi
done < <(
  echo "${discovered_json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('\n'.join(d['categories']))
" | while read -r cat; do
    find "${wiki}/${cat}" -type f -name "*.md" -not -name "_index.md" 2>/dev/null
  done
)

# Tag synonym count
synonym_count=0
if [[ -x "${SCRIPT_DIR}/wiki-lint-tags.py" ]]; then
  synonym_count="$(python3 "${SCRIPT_DIR}/wiki-lint-tags.py" --wiki-root "${wiki}" --all 2>/dev/null | grep -oE 'synonym pairs flagged: [0-9]+' | awk '{print $NF}')"
  [[ -z "${synonym_count}" ]] && synonym_count=0
fi

# Index size (Finding 01 -- surface warning when over 8 KB threshold)
index_size=0
index_warn=""
if [[ -f "${wiki}/index.md" ]]; then
  index_size="$(wc -c < "${wiki}/index.md" | tr -d ' ')"
  if [[ "${index_size}" -gt 8192 ]]; then
    index_kb=$(( (index_size + 512) / 1024 ))
    index_warn=" -- over 8 KB threshold; consider atom-ization"
    index_size="${index_kb} KB"
  else
    index_size="${index_size} bytes"
  fi
fi

# v2.3 new: categories exceeding depth 4
exceeding="$(echo "${discovered_json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(sum(1 for c in d['categories'] if d['depths'].get(c, 1) > 4))
")"

# v2.3 new: category count vs soft-ceiling 8
cat_count="$(echo "${discovered_json}" | python3 -c "
import json, sys
print(len(json.load(sys.stdin)['categories']))
")"

cat <<EOF
wiki: ${wiki}
role: ${role}
total pages: ${total_pages}
pending: ${pending}
processing: ${processing}
active locks: ${locks}
last ingest: ${last_ingest}
drift: ${drift}
git: ${git_status}
pages below 3.5 quality: ${below_35}
tag synonyms flagged: ${synonym_count}
index.md: ${index_size}${index_warn}
EOF

# Per-category counts (v2.3)
echo "${discovered_json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for cat in d['categories']:
    print(f'{cat}: {d[\"counts\"][cat]}')
"

cat <<EOF
categories exceeding depth 4: ${exceeding}
category count vs soft-ceiling 8: ${cat_count} (ceiling 8)
EOF

echo
echo "## Workspace routing"
if routing_plan="$(python3 "${SCRIPT_DIR}/wiki_config.py" route-find --cwd "${wiki}" --json 2>/dev/null)"; then
  python3 - "${routing_plan}" <<'PYEOF'
import json
import sys

plan = json.loads(sys.argv[1])
print(f"routing mode: {plan['mode']}")
print(f"routing runtime: {plan['runtime_config_path']}")
print(f"primary wiki: {plan['primary_wiki']}")
if plan.get("project_wiki"):
    print(f"project wiki: {plan['project_wiki']}")
if plan.get("main_wiki"):
    print(f"main wiki: {plan['main_wiki']}")
print(f"promotion policy: {plan['promotion_policy']}")
PYEOF
else
  echo "routing mode: unconfigured"
  echo "Run: wiki use project|main|both"
fi

echo
echo "## Ingest runtime"
if ! python3 "${SCRIPT_DIR}/wiki_runtime_status.py" "${wiki}"; then
  echo "runtime config: invalid"
  echo "wiki status: runtime health helper failed; content health above is still valid"
fi

# Issues summary (v2.4)
issues_log="${wiki}/.ingest-issues.jsonl"
if [[ -f "${issues_log}" && -s "${issues_log}" ]]; then
  echo
  echo "## Issues reported by ingesters (last 30 days)"
  python3 - "${issues_log}" <<'PYEOF'
import json, sys
from collections import Counter
from datetime import datetime, timedelta, timezone

cutoff = datetime.now(timezone.utc) - timedelta(days=30)
counts = Counter()
malformed = 0

with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            malformed += 1
            continue
        ts = obj.get("reported_at", "")
        try:
            t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            continue
        if t < cutoff:
            continue
        counts[obj.get("issue_type", "other")] += 1

if not counts:
    print("  (none in the last 30 days)")
else:
    LABEL = {
        "broken-cross-link": "broken cross-link",
        "contradiction":     "contradiction",
        "schema-drift":      "schema drift",
        "stale-claim":       "stale claim",
        "tag-drift":         "tag drift",
        "quality-concern":   "quality concern",
        "orphan":            "orphan",
        "other":             "other",
    }
    for itype, n in counts.most_common():
        plural = "s" if n != 1 else ""
        print(f"  {n} {LABEL.get(itype, itype)}{plural}")
    print("  Run `wiki issues` for details.")

if malformed:
    print(f"  ({malformed} malformed line(s) skipped)")
PYEOF
fi

# Selective project-to-main decisions. Legacy simultaneous-fork records are no
# longer written or interpreted because they cannot represent project-first
# routing.
python3 - "${wiki}" <<'PYEOF'
from collections import Counter
import json
from pathlib import Path
import re
import sys

def without_yaml_inline_comment(value):
    single_quoted = False
    double_quoted = False
    escaped = False
    for index, character in enumerate(value):
        if double_quoted and character == "\\" and not escaped:
            escaped = True
            continue
        if character == '"' and not single_quoted and not escaped:
            double_quoted = not double_quoted
        elif character == "'" and not double_quoted:
            single_quoted = not single_quoted
        elif (character == "#" and not single_quoted and not double_quoted
              and (index == 0 or value[index - 1].isspace())):
            return value[:index].rstrip()
        escaped = False
    return value

def frontmatter_scalar(lines, key):
    pattern = re.compile(rf"^{re.escape(key)}\s*:\s*(.*?)\s*$")
    matches = [match.group(1) for line in lines if (match := pattern.match(line))]
    if len(matches) > 1:
        raise ValueError(f"duplicate authoritative frontmatter key: {key}")
    if not matches:
        return None
    value = without_yaml_inline_comment(matches[0])
    if value in {"", "null", "~"}:
        return None
    if len(value) >= 2 and value[0] == value[-1] == '"':
        decoded = json.loads(value)
        if not isinstance(decoded, str):
            raise ValueError(f"frontmatter scalar {key} must be a string")
        return decoded
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1]
    return value

root = Path(sys.argv[1])
counts = Counter()
unreadable = 0
for path in (root / ".wiki-pending").rglob("*.md*"):
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        unreadable += 1
        continue
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        continue
    try:
        frontmatter_end = next(
            index for index, line in enumerate(lines[1:], start=1)
            if line.strip() == "---"
        )
    except StopIteration:
        continue
    frontmatter = lines[1:frontmatter_end]
    try:
        policy = frontmatter_scalar(frontmatter, "promotion_policy")
        decision = frontmatter_scalar(frontmatter, "promotion_decision")
    except (ValueError, json.JSONDecodeError):
        unreadable += 1
        continue
    if policy != "selective":
        continue
    if decision is None:
        counts["awaiting decision"] += 1
    elif decision == "keep-local":
        counts["kept local"] += 1
    elif decision == "promoted":
        counts["promoted"] += 1
    else:
        counts["invalid decision"] += 1

if counts or unreadable:
    print()
    print("## Selective promotion")
    for label in ("awaiting decision", "kept local", "promoted", "invalid decision"):
        if counts[label]:
            print(f"  {counts[label]} {label}")
    if unreadable:
        print(f"  {unreadable} invalid/unreadable")
PYEOF
