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

test_wiki_root_from_cwd_derefs_project_pointer() {
  # A cwd .wiki-config with role "project-pointer" is a POINTER, not a wiki.
  # wiki_root_from_cwd must follow it to the pointed directory. (Bug: status /
  # session-start / stop measured the pointer dir itself — wrong manifest,
  # wrong git state, silent no-op drift scans.)
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki"
  printf 'role = "project"\n' > "${tmp}/wiki/.wiki-config"
  printf 'role = "project-pointer"\nwiki = "./wiki"\n' > "${tmp}/.wiki-config"

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
  # Same deref must apply when the pointer config is found via walk-up
  # (cwd is a subdirectory of the project root).
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki" "${tmp}/Assets/Scripts"
  printf 'role = "project"\n' > "${tmp}/wiki/.wiki-config"
  printf 'role = "project-pointer"\nwiki = "./wiki"\n' > "${tmp}/.wiki-config"

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
