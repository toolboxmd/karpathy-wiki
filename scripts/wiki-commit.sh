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

git commit -m "${msg}" >/dev/null 2>&1 || {
  log_error "commit: git commit failed"
  exit 1
}
log_info "commit: ${msg}"
exit 0
