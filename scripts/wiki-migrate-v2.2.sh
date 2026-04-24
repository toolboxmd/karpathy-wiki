#!/bin/bash
# wiki-migrate-v2.2.sh -- apply v2.2 hardening to a live wiki.
#
# Usage:
#   wiki-migrate-v2.2.sh <wiki_root>            # apply
#   wiki-migrate-v2.2.sh --dry-run <wiki_root>  # report only
#
# Mutations performed:
#   1. Remove sources/ category (every file inside).
#   2. Rewrite any concept-page sources: frontmatter that points at
#      sources/<x>.md to point at raw/<x>.md instead.
#   3. Strip body-prose markdown links to sources/ pages.
#   4. Fix same-dir-prefix-bug links (e.g. concept page links to
#      "concepts/foo.md" when the linker also lives in concepts/).
#   5. Set origin = "conversation" on manifest entries with empty origin.
#   6. Rename archive/*.md.processing files -> *.md.

set -uo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

wiki="${1:-}"
[[ -n "${wiki}" ]] || { echo >&2 "usage: $0 [--dry-run] <wiki_root>"; exit 1; }
[[ -d "${wiki}" ]] || { echo >&2 "not a directory: ${wiki}"; exit 1; }
[[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "not a wiki: ${wiki}"; exit 1; }

say() { echo "$@"; }

# 1. Remove sources/ category.
migrate_remove_sources_category() {
  if [[ -d "${wiki}/sources" ]]; then
    while IFS= read -r f; do
      rel="${f#${wiki}/}"
      if (( DRY_RUN )); then
        say "would-remove ${rel}"
      else
        rm -- "${f}"
      fi
    done < <(find "${wiki}/sources" -type f -name "*.md")
    if (( ! DRY_RUN )); then
      rmdir "${wiki}/sources" 2>/dev/null || true
    fi
  fi
}

# 2. Rewrite frontmatter sources: lines pointing at sources/<x>.md -> raw/<x>.md.
migrate_rewrite_frontmatter_sources() {
  while IFS= read -r f; do
    if grep -qE '^  - sources/' "${f}"; then
      rel="${f#${wiki}/}"
      if (( DRY_RUN )); then
        say "would-rewrite ${rel} sources: sources/ -> raw/"
      else
        # In-place sed; portable form (works on BSD + GNU).
        python3 - "${f}" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'^(  - )sources/', r'\1raw/', text, flags=re.MULTILINE)
open(path, 'w').write(text)
PY
      fi
    fi
  done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/ideas" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)
}

# 3. Strip body-prose markdown links to sources/ pages.
#    Heuristic: remove the entire markdown link [text](path) where path
#    contains 'sources/'. Keep the surrounding prose.
migrate_strip_body_sources_links() {
  while IFS= read -r f; do
    if grep -qE '\]\([^)]*sources/' "${f}"; then
      rel="${f#${wiki}/}"
      if (( DRY_RUN )); then
        say "would-rewrite ${rel} body-link sources/"
      else
        python3 - "${f}" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
# Match [...](path-containing-sources/...) and replace with the link text only.
text = re.sub(r'\[([^\]]*)\]\([^)]*sources/[^)]*\)', r'\1', text)
open(path, 'w').write(text)
PY
      fi
    fi
  done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/ideas" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)
}

# 4. Fix same-dir-prefix-bug links.
#    Heuristic: in concepts/X.md, a link target like "concepts/Y.md" is
#    wrong (should be "Y.md"). Apply per category.
migrate_fix_same_dir_prefix_links() {
  for category in concepts entities ideas queries; do
    [[ -d "${wiki}/${category}" ]] || continue
    while IFS= read -r f; do
      if grep -qE "\]\(${category}/" "${f}"; then
        rel="${f#${wiki}/}"
        if (( DRY_RUN )); then
          say "would-fix-prefix ${rel}"
        else
          python3 - "${f}" "${category}" <<'PY'
import sys, re
path, cat = sys.argv[1], sys.argv[2]
text = open(path).read()
text = re.sub(rf'\]\({re.escape(cat)}/', '](', text)
open(path, 'w').write(text)
PY
        fi
      fi
    done < <(find "${wiki}/${category}" -type f -name "*.md")
  done
}

# 5. Manifest empty-origin -> "conversation" backfill.
migrate_manifest_empty_origin() {
  local manifest="${wiki}/.manifest.json"
  [[ -f "${manifest}" ]] || return 0
  while IFS= read -r key; do
    if (( DRY_RUN )); then
      say "would-set-origin ${key} = conversation"
    fi
  done < <(python3 -c "
import json
m = json.load(open('${manifest}'))
for k, v in m.items():
    if isinstance(v, dict) and v.get('origin', '') == '':
        print(k)
")
  if (( ! DRY_RUN )); then
    python3 - "${manifest}" <<'PY'
import json, sys
path = sys.argv[1]
m = json.load(open(path))
changed = False
for k, v in m.items():
    if isinstance(v, dict) and v.get('origin', '') == '':
        v['origin'] = 'conversation'
        changed = True
if changed:
    open(path, 'w').write(json.dumps(m, indent=2) + '\n')
PY
  fi
}

# 6. Rename archive/*.md.processing -> *.md.
migrate_archive_processing_suffix() {
  while IFS= read -r f; do
    rel="${f#${wiki}/}"
    new="${f%.processing}"
    new_rel="${new#${wiki}/}"
    if (( DRY_RUN )); then
      say "would-rename ${rel} -> .md"
    else
      mv -- "${f}" "${new}"
    fi
  done < <(find "${wiki}/.wiki-pending/archive" -type f -name "*.processing" 2>/dev/null)
}

main() {
  migrate_remove_sources_category
  migrate_rewrite_frontmatter_sources
  migrate_strip_body_sources_links
  migrate_fix_same_dir_prefix_links
  migrate_manifest_empty_origin
  migrate_archive_processing_suffix
  if (( DRY_RUN )); then
    say ""
    say "(dry-run complete; no files modified)"
  fi
}

main
