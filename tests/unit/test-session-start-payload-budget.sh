#!/bin/bash
# Provider/runtime mechanics must not increase the model-visible loader payload.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOADER="${REPO_ROOT}/skills/using-karpathy-wiki/SKILL.md"
BASELINE_BYTES=8853

actual="$(wc -c < "${LOADER}" | tr -d ' ')"
if [[ "${actual}" -gt "${BASELINE_BYTES}" ]]; then
  echo "FAIL: loader payload grew from ${BASELINE_BYTES} to ${actual} bytes" >&2
  exit 1
fi

echo "PASS: loader payload is ${actual} bytes (baseline ceiling ${BASELINE_BYTES})"
