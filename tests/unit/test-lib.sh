#!/bin/bash
# Test wiki-lib.sh helpers.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB="${REPO_ROOT}/scripts/wiki-lib.sh"

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
  mkdir -p "${tmp}/wiki"
  touch "${tmp}/wiki/.wiki-config"

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

test_log_info
test_slugify
test_wiki_root_from_cwd_with_wiki_dir
echo "ALL PASS"
