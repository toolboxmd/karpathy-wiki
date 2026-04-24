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
total_pages="$(find "${wiki}" -type f -name "*.md" -not -path "*/.wiki-pending/*" 2>/dev/null | wc -l | tr -d ' ')"

last_ingest="never"
if [[ -f "${wiki}/log.md" ]]; then
  last_ingest="$(grep -oE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' "${wiki}/log.md" | tail -1 | tr -d '[]# ')"
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

# Quality rollup: count pages with overall < 3.5
below_35=0
while IFS= read -r page; do
  overall="$(grep -oE '^  overall: [0-9]+\.[0-9]+$' "${page}" | head -1 | awk '{print $2}')"
  if [[ -n "${overall}" ]]; then
    if awk -v v="${overall}" 'BEGIN { exit !(v < 3.5) }'; then
      below_35=$((below_35 + 1))
    fi
  fi
done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/sources" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)

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
