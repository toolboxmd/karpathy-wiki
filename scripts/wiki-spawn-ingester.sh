#!/bin/bash
# Spawn a detached headless ingester for a single capture.
#
# Usage:
#   wiki-spawn-ingester.sh <wiki_root> <capture_path>
#
# This script exits within milliseconds. The ingester runs in the background
# (child of init via setsid), surviving the parent session.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

wiki="$1"
capture="$2"

[[ -n "${wiki}" ]] || { echo >&2 "missing wiki_root"; exit 1; }
[[ -n "${capture}" ]] || { echo >&2 "missing capture_path"; exit 1; }

# Graceful no-op if capture doesn't exist.
if [[ ! -f "${capture}" ]]; then
  log_warn "spawn: capture missing, skipping: ${capture}"
  exit 0
fi

# Read platform.headless_command from config.
headless_cmd="$(wiki_config_get "${wiki}" platform.headless_command 2>/dev/null || echo "")"
if [[ -z "${headless_cmd}" ]]; then
  log_error "spawn: no headless_command configured"
  exit 1
fi

# Build the ingest prompt.
# The skill prose defines what this prompt means operationally.
prompt="Ingest this capture into the wiki. Wiki root: ${wiki}. Capture file: ${capture}. Follow the karpathy-wiki skill's INGEST operation exactly."

# Explicit env passthrough (Anthropic API keys, etc.).
# Headless workers don't inherit interactive-session env by default on some platforms.
env_passthrough=(
  "HOME=${HOME}"
  "PATH=${PATH}"
  "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}"
  "WIKI_ROOT=${wiki}"
  "WIKI_CAPTURE=${capture}"
)

# Detach via setsid (Linux) or nohup (macOS/BSD fallback).
# Output goes to .ingest.log.
logfile="${wiki}/.ingest.log"

if command -v setsid >/dev/null 2>&1; then
  setsid env "${env_passthrough[@]}" \
    ${headless_cmd} "${prompt}" \
    >> "${logfile}" 2>&1 < /dev/null &
else
  nohup env "${env_passthrough[@]}" \
    ${headless_cmd} "${prompt}" \
    >> "${logfile}" 2>&1 < /dev/null &
fi

log_info "spawned ingester: capture=$(basename "${capture}") pid=$!"
# Disown so the spawner can exit cleanly.
disown 2>/dev/null || true
exit 0
