#!/bin/bash
# Commit wiki changes with a structured message. Idempotent.
#
# Usage:
#   wiki-commit.sh <wiki_root> <message>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

wiki="$1"
msg="$2"

[[ -n "${wiki}" ]] || { echo >&2 "missing wiki_root"; exit 1; }
[[ -n "${msg}" ]]  || { echo >&2 "missing message"; exit 1; }

# Respect auto_commit setting.
auto_commit="$(wiki_config_get "${wiki}" settings.auto_commit 2>/dev/null || echo "true")"
if [[ "${auto_commit}" != "true" ]]; then
  log_info "commit: auto_commit disabled, skipping"
  exit 0
fi

# Git must be available and wiki must be a git repo.
command -v git >/dev/null 2>&1 || { log_warn "commit: git not installed"; exit 0; }
if ! (cd "${wiki}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  log_warn "commit: wiki is not a git repo"
  exit 0
fi

cd "${wiki}"
git add -A

# If nothing staged, silently exit.
if git diff --cached --quiet; then
  log_info "commit: nothing to commit"
  exit 0
fi

# Validator gate (0.2.8 #3): the iron rule that "every touched page must
# pass the validator before commit" used to live as prose in the ingest
# skill. Enforce it here in code: validate every staged .md page that
# lives under a category dir (i.e. user-authored content pages, not
# captures, raw evidence, manifest/log files, or _index.md indexes).
validator="${SCRIPT_DIR}/wiki-validate-page.py"
if [[ -x "${validator}" ]]; then
  failed=0
  failed_pages=()
  while IFS= read -r staged; do
    [[ -n "${staged}" ]] || continue
    [[ "${staged}" == *.md ]] || continue
    # Skip non-content paths.
    case "${staged}" in
      .wiki-pending/*|raw/*|inbox/*|.raw-staging/*) continue ;;
      _index.md|*/_index.md|index.md|README.md|log.md|schema.md) continue ;;
    esac
    # Skip deletions.
    [[ -f "${wiki}/${staged}" ]] || continue
    if ! python3 "${validator}" --wiki-root "${wiki}" "${wiki}/${staged}" >&2; then
      failed=$((failed + 1))
      failed_pages+=("${staged}")
    fi
  done < <(git diff --cached --name-only --diff-filter=ACMR)

  if [[ "${failed}" -gt 0 ]]; then
    log_error "commit: validator failed for ${failed} page(s); refusing commit"
    for p in "${failed_pages[@]}"; do
      log_error "commit:   ${p}"
    done
    exit 1
  fi
fi

git commit -m "${msg}" >/dev/null 2>&1 || {
  log_error "commit: git commit failed"
  exit 1
}
log_info "commit: ${msg}"
exit 0
