#!/bin/bash
# wiki-orphan.sh — preserve a capture body when bin/wiki capture must abort.
#
# Usage:
#   wiki-orphan.sh --title <title> --reason <reason> --body-file <path>
#
# Writes the body to ${WIKI_ORPHANS_DIR:-$HOME/.wiki-orphans}/<timestamp>-<slug>.md
# with a frontmatter explaining why the capture was aborted.
#
# Env overrides for testing:
#   WIKI_ORPHANS_DIR — orphan directory (default: ~/.wiki-orphans)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

ORPHANS_DIR="${WIKI_ORPHANS_DIR:-${HOME}/.wiki-orphans}"

title=""
reason=""
body_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) title="$2"; shift 2 ;;
    --reason) reason="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    *) echo >&2 "wiki-orphan: unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "${title}" && -n "${reason}" && -n "${body_file}" ]] \
  || { echo >&2 "wiki-orphan: --title --reason --body-file all required"; exit 1; }
[[ -f "${body_file}" ]] || { echo >&2 "wiki-orphan: body file missing: ${body_file}"; exit 1; }

mkdir -p "${ORPHANS_DIR}"

ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
slug="$(slugify "${title}")"
out="${ORPHANS_DIR}/${ts}-${slug}.md"

cat > "${out}" <<EOF
---
title: "${title}"
orphaned_at: "${ts}"
reason: "${reason}"
---

EOF
cat "${body_file}" >> "${out}"

echo "${out}"
