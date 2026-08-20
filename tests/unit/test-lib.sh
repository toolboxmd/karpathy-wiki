#!/bin/bash
# Test wiki-lib.sh helpers.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB="${REPO_ROOT}/scripts/wiki-lib.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"
TEST_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "${TEST_CONFIG_HOME}"' EXIT
export XDG_CONFIG_HOME="${TEST_CONFIG_HOME}"

# shellcheck source=/dev/null
source "${LIB}"

test_log_info() {
  local tmpfile
  tmpfile="$(mktemp)"
  WIKI_INGEST_LOG="${tmpfile}" log_info "hello"
  grep -q "INFO  hello" "${tmpfile}" || {
    echo "FAIL: test_log_info — expected 'INFO  hello' in log, got:"
    cat "${tmpfile}"
    exit 1
  }
  rm -f "${tmpfile}"
  echo "PASS: test_log_info"
}

test_slugify() {
  local result
  result="$(slugify "Hello World! My Title")"
  [[ "${result}" == "hello-world-my-title" ]] || {
    echo "FAIL: test_slugify — expected 'hello-world-my-title', got '${result}'"
    exit 1
  }
  echo "PASS: test_slugify"
}

test_wiki_root_from_cwd_with_wiki_dir() {
  local tmp
  tmp="$(mktemp -d)"
  tmp="$(cd "${tmp}" && pwd -P)"
  bash "${INIT}" project "${tmp}/wiki" >/dev/null
  python3 "${CONFIG}" route-set --workspace "${tmp}" --mode project \
    --project-wiki "${tmp}/wiki" >/dev/null

  local result
  result="$(cd "${tmp}" && wiki_root_from_cwd)"
  [[ "${result}" == "${tmp}/wiki" ]] || {
    echo "FAIL: test_wiki_root_from_cwd — expected '${tmp}/wiki', got '${result}'"
    rm -rf "${tmp}"
    exit 1
  }
  rm -rf "${tmp}"
  echo "PASS: test_wiki_root_from_cwd_with_wiki_dir"
}

test_wiki_root_from_cwd_derefs_project_pointer() {
  # Legacy structural pointers cannot override the trusted runtime target.
  local tmp
  tmp="$(mktemp -d)"
  tmp="$(cd "${tmp}" && pwd -P)"
  bash "${INIT}" project "${tmp}/wiki" >/dev/null
  printf 'role = "project-pointer"\nwiki = "./wiki"\n' > "${tmp}/.wiki-config"
  python3 "${CONFIG}" route-set --workspace "${tmp}" --mode project \
    --project-wiki "${tmp}/wiki" >/dev/null

  local result
  result="$(cd "${tmp}" && wiki_root_from_cwd)"
  [[ "${result}" == "${tmp}/wiki" ]] || {
    echo "FAIL: test_wiki_root_from_cwd_derefs_project_pointer — expected '${tmp}/wiki', got '${result}'"
    rm -rf "${tmp}"
    exit 1
  }
  rm -rf "${tmp}"
  echo "PASS: test_wiki_root_from_cwd_derefs_project_pointer"
}

test_wiki_root_from_cwd_derefs_pointer_on_walkup() {
  # The same authoritative runtime applies when cwd is below the workspace.
  local tmp
  tmp="$(mktemp -d)"
  tmp="$(cd "${tmp}" && pwd -P)"
  mkdir -p "${tmp}/Assets/Scripts"
  bash "${INIT}" project "${tmp}/wiki" >/dev/null
  printf 'role = "project-pointer"\nwiki = "./wiki"\n' > "${tmp}/.wiki-config"
  python3 "${CONFIG}" route-set --workspace "${tmp}" --mode project \
    --project-wiki "${tmp}/wiki" >/dev/null

  local result
  result="$(cd "${tmp}/Assets/Scripts" && wiki_root_from_cwd)"
  [[ "${result}" == "${tmp}/wiki" ]] || {
    echo "FAIL: test_wiki_root_from_cwd_derefs_pointer_on_walkup — expected '${tmp}/wiki', got '${result}'"
    rm -rf "${tmp}"
    exit 1
  }
  rm -rf "${tmp}"
  echo "PASS: test_wiki_root_from_cwd_derefs_pointer_on_walkup"
}

test_log_info
test_slugify
test_wiki_root_from_cwd_with_wiki_dir
test_wiki_root_from_cwd_derefs_project_pointer
test_wiki_root_from_cwd_derefs_pointer_on_walkup
echo "ALL PASS"
