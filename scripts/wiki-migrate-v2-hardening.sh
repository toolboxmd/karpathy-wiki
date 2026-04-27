#!/bin/bash
# One-time migration: bring a wiki to the v2-hardening schema.
#
# Usage:
#   wiki-migrate-v2-hardening.sh [--yes] [--wiki-root DIR] [--backup-dir DIR]
#
# Without --wiki-root, defaults to $HOME/wiki.
# Without --backup-dir, backup goes to "$(dirname <wiki>)" (so $HOME for
# $HOME/wiki).
# Without --yes, prompts before committing the migrated wiki to git.
#
# What it does (in order):
#   1. Backup the wiki to <backup-dir>/wiki.backup-<timestamp>/.
#   2. Run `wiki-manifest.py migrate` to consolidate the two manifests.
#   3. Walk concepts/entities/sources/queries/*.md, run
#      `wiki-normalize-frontmatter.py` on each.
#   4. Rebuild the manifest (`wiki-manifest.py build`) to populate sha256.
#   5. Run `wiki-validate-page.py --wiki-root <wiki>` on every page.
#   6. If ANY validator violation: restore backup, exit 1, print violations.
#   7. Otherwise: prompt user to commit (skipped with --yes), then exit 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

yes_mode=0
wiki=""
backup_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) yes_mode=1; shift;;
    --wiki-root) wiki="$2"; shift 2;;
    --backup-dir) backup_dir="$2"; shift 2;;
    *) echo >&2 "unknown arg: $1"; exit 1;;
  esac
done

[[ -z "${wiki}" ]] && wiki="${HOME}/wiki"
wiki="$(cd "${wiki}" && pwd)" || { echo >&2 "wiki not found: ${wiki}"; exit 1; }
[[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "not a wiki (no .wiki-config): ${wiki}"; exit 1; }
[[ -z "${backup_dir}" ]] && backup_dir="$(dirname "${wiki}")"
mkdir -p "${backup_dir}"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup="${backup_dir}/wiki.backup-${timestamp}"

echo "backup: ${backup}"
cp -R "${wiki}" "${backup}"

restore_backup() {
  echo >&2 "restoring backup from ${backup}"
  rm -rf "${wiki}"
  cp -R "${backup}" "${wiki}"
}

# 1. Manifest consolidation
python3 "${SCRIPT_DIR}/wiki-manifest.py" migrate "${wiki}" || {
  echo >&2 "manifest migrate failed"
  restore_backup
  exit 1
}

# 2. Normalize frontmatter on every page
normalize_failed=0
for category in concepts entities sources queries; do
  if [[ -d "${wiki}/${category}" ]]; then
    while IFS= read -r page; do
      if ! python3 "${SCRIPT_DIR}/wiki-normalize-frontmatter.py" --wiki-root "${wiki}" "${page}"; then
        echo >&2 "normalize failed: ${page}"
        normalize_failed=1
      fi
    done < <(find "${wiki}/${category}" -type f -name "*.md" 2>/dev/null)
  fi
done
if [[ "${normalize_failed}" -eq 1 ]]; then
  restore_backup
  exit 1
fi

# 3. Backfill quality: blocks on every page missing one (Phase B requirement)
if [[ -f "${SCRIPT_DIR}/wiki-backfill-quality.py" ]]; then
  python3 "${SCRIPT_DIR}/wiki-backfill-quality.py" --wiki-root "${wiki}" || {
    echo >&2 "quality backfill failed"
    restore_backup
    exit 1
  }
fi

# 4. Rebuild manifest to populate sha256 for all raw files
python3 "${SCRIPT_DIR}/wiki-manifest.py" build "${wiki}" || {
  echo >&2 "manifest build failed"
  restore_backup
  exit 1
}

# 5. Validate every page
violations_found=0
while IFS= read -r page; do
  if ! python3 "${SCRIPT_DIR}/wiki-validate-page.py" --wiki-root "${wiki}" "${page}" 2>&1; then
    violations_found=1
  fi
done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/sources" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)

if [[ "${violations_found}" -eq 1 ]]; then
  echo >&2 "validator found violations; rolling back"
  restore_backup
  exit 1
fi

# 6. Optionally commit
if [[ "${yes_mode}" -eq 1 ]]; then
  (cd "${wiki}" && git add -A && git commit -m "chore: v2-hardening schema migration" >/dev/null)
  echo "committed."
else
  echo "migration complete. review with:"
  echo "  cd ${wiki} && git status && git diff"
  echo -n "commit the migration now? [y/N] "
  read -r reply
  if [[ "${reply}" == "y" || "${reply}" == "Y" ]]; then
    (cd "${wiki}" && git add -A && git commit -m "chore: v2-hardening schema migration" >/dev/null)
    echo "committed."
  else
    echo "not committed. backup retained at ${backup}."
  fi
fi

echo "done. backup at: ${backup}"
exit 0
