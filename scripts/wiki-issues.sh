#!/bin/bash
# wiki-issues.sh — render <wiki>/.ingest-issues.jsonl as grouped markdown.
#
# v2.4 ships the basic render only; --filter and --since flags are
# deferred to v2.5.
#
# Usage:
#   wiki-issues.sh --wiki <path>

set -uo pipefail

wiki=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wiki) wiki="$2"; shift 2 ;;
    *) echo >&2 "wiki-issues: unknown arg: $1"; exit 1 ;;
  esac
done
[[ -n "${wiki}" ]] || { echo >&2 "wiki-issues: --wiki required"; exit 1; }
[[ -d "${wiki}" ]] || { echo >&2 "wiki-issues: wiki path missing: ${wiki}"; exit 1; }

log="${wiki}/.ingest-issues.jsonl"

if [[ ! -f "${log}" || ! -s "${log}" ]]; then
  echo "# Wiki issues — no issues reported"
  exit 0
fi

python3 - "${log}" <<'PYEOF'
import json, sys
from collections import defaultdict

log_path = sys.argv[1]
SEVERITY_ORDER = {"error": 0, "warn": 1, "info": 2}
TYPE_ORDER = [
    "broken-cross-link",
    "contradiction",
    "schema-drift",
    "stale-claim",
    "tag-drift",
    "quality-concern",
    "orphan",
    "other",
]
TYPE_LABEL = {
    "broken-cross-link": "Broken cross-links",
    "contradiction":     "Contradictions",
    "schema-drift":      "Schema drift",
    "stale-claim":       "Stale claims",
    "tag-drift":         "Tag drift",
    "quality-concern":   "Quality concerns",
    "orphan":            "Orphans",
    "other":             "Other",
}

issues = defaultdict(list)
total = 0
malformed = 0

with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            malformed += 1
            continue
        itype = obj.get("issue_type", "other")
        issues[itype].append(obj)
        total += 1

print(f"# Wiki issues — {total} reported")
if malformed:
    print(f"\n_(skipped {malformed} malformed line(s))_")

for itype in TYPE_ORDER:
    rows = issues.get(itype, [])
    if not rows:
        continue
    label = TYPE_LABEL.get(itype, itype)
    print(f"\n## {label} ({len(rows)})")
    rows.sort(key=lambda r: SEVERITY_ORDER.get(r.get("severity", "info"), 99))
    for r in rows:
        sev = r.get("severity", "info")
        page = r.get("page", "(no page)")
        detail = r.get("detail", "(no detail)")
        ts = r.get("reported_at", "")
        run = r.get("ingester_run", "")
        action = r.get("suggested_action")
        print(f"\n- **{sev}** `{page}`: {detail}")
        print(f"  - reported {ts} by {run}")
        if action:
            print(f"  - suggested: {action}")
PYEOF
