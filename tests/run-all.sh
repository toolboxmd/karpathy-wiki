#!/bin/bash
# Run all tests.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

passed=0
failed=0
failed_tests=()

run() {
  local name="$1"
  shift
  echo "=== ${name} ==="
  if "$@"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failed_tests+=("${name}")
  fi
  echo
}

# Unit tests
for t in "${SCRIPT_DIR}"/unit/test-*.sh; do
  run "unit/$(basename "${t}")" bash "${t}"
done

# Integration tests
for t in "${SCRIPT_DIR}"/integration/test-*.sh; do
  run "integration/$(basename "${t}")" bash "${t}"
done

echo "========================"
echo "passed: ${passed}"
echo "failed: ${failed}"
if [[ "${failed}" -gt 0 ]]; then
  echo "failing tests:"
  for t in "${failed_tests[@]}"; do echo "  - ${t}"; done
  exit 1
fi
