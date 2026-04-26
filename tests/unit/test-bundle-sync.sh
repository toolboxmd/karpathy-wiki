#!/bin/bash
# Test: skills/karpathy-wiki/scripts is a symlink to ../../scripts.
#
# Per v2.3 spec §5.6 (path-A patch): the bundle directory shares a single
# inode with the dev /scripts/ directory via symlink. This test guards
# against accidental "fix" that would replace the symlink with a real copy
# (which would re-introduce the drift problem the symlink avoids).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEV="${REPO_ROOT}/scripts"
BUNDLE="${REPO_ROOT}/skills/karpathy-wiki/scripts"

test_bundle_is_symlink() {
  if [[ ! -L "${BUNDLE}" ]]; then
    echo "FAIL: ${BUNDLE} is not a symlink (must be 'scripts -> ../../scripts')"
    exit 1
  fi
}

test_symlink_target_correct() {
  target="$(readlink "${BUNDLE}")"
  if [[ "${target}" != "../../scripts" ]]; then
    echo "FAIL: ${BUNDLE} symlink target is '${target}', expected '../../scripts'"
    exit 1
  fi
}

test_bundle_dir_resolves_to_dev_scripts() {
  # Resolve both paths and verify they point to the same inode/path.
  dev_real="$(readlink -f "${DEV}" 2>/dev/null || python3 -c "import os; print(os.path.realpath('${DEV}'))")"
  bundle_real="$(readlink -f "${BUNDLE}" 2>/dev/null || python3 -c "import os; print(os.path.realpath('${BUNDLE}'))")"
  if [[ "${dev_real}" != "${bundle_real}" ]]; then
    echo "FAIL: dev ${dev_real} != bundle ${bundle_real}"
    exit 1
  fi
}

test_bundle_is_symlink
test_symlink_target_correct
test_bundle_dir_resolves_to_dev_scripts
echo "all tests passed"
