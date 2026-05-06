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

# Fork asymmetry (v2.4)
forks_log="${HOME}/.wiki-forks.jsonl"
if [[ -f "${forks_log}" && -s "${forks_log}" ]]; then
  python3 - "${forks_log}" "${wiki}" <<'PYEOF'
import json, os, sys
from datetime import datetime, timedelta, timezone

forks_path, target_wiki = sys.argv[1], os.path.realpath(sys.argv[2])
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
asymmetric = []

with open(forks_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            fork = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            ts = datetime.fromisoformat(fork.get("captured_at", "").replace("Z", "+00:00"))
        except ValueError:
            continue
        if ts < cutoff:
            continue
        wikis = fork.get("wikis", [])
        if target_wiki not in [os.path.realpath(w) for w in wikis]:
            continue
        statuses = {}
        for w in wikis:
            runs_log = os.path.join(w, ".ingest-runs.jsonl")
            if not os.path.exists(runs_log):
                statuses[w] = "missing"
                continue
            found_status = "spawned-no-close"
            with open(runs_log) as rf:
                for rline in rf:
                    rline = rline.strip()
                    if not rline:
                        continue
                    try:
                        run = json.loads(rline)
                    except json.JSONDecodeError:
                        continue
                    cap = run.get("capture", "")
                    if cap in fork.get("captures", []) and "status" in run and run["status"] != "spawned":
                        found_status = run["status"]
                        break
            statuses[w] = found_status
        if any(s != "completed" for s in statuses.values()):
            asymmetric.append((fork, statuses))

if asymmetric:
    print()
    print("## Fork asymmetry (last 7 days)")
    for fork, statuses in asymmetric:
        print(f"  fork {fork.get('fork_id', '(no id)')}: {fork.get('title', '(no title)')}")
        for w, s in statuses.items():
            print(f"    {w}: {s}")
    print("  Run `wiki ingest-now <wiki>` on incomplete sides to retry.")
PYEOF
fi
