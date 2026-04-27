#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
READER="${REPO_ROOT}/scripts/wiki-config-read.py"

# Fixture config
TMPCFG="$(mktemp)"
cat > "${TMPCFG}" <<'EOF'
role = "main"
created = "2026-04-22"

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
EOF

test_read_top_level() {
  local result
  result="$(python3 "${READER}" "${TMPCFG}" role)"
  [[ "${result}" == "main" ]] || { echo "FAIL: role. got '${result}'"; exit 1; }
  echo "PASS: test_read_top_level"
}

test_read_nested() {
  local result
  result="$(python3 "${READER}" "${TMPCFG}" platform.agent_cli)"
  [[ "${result}" == "claude" ]] || { echo "FAIL: platform.agent_cli. got '${result}'"; exit 1; }
  echo "PASS: test_read_nested"
}

test_read_missing_key_exits_nonzero() {
  if python3 "${READER}" "${TMPCFG}" missing.key 2>/dev/null; then
    echo "FAIL: missing key should exit nonzero"
    exit 1
  fi
  echo "PASS: test_read_missing_key_exits_nonzero"
}

test_read_missing_file_exits_nonzero() {
  if python3 "${READER}" /tmp/does-not-exist-$$ role 2>/dev/null; then
    echo "FAIL: missing file should exit nonzero"
    exit 1
  fi
  echo "PASS: test_read_missing_file_exits_nonzero"
}

test_read_top_level
test_read_nested
test_read_missing_key_exits_nonzero
test_read_missing_file_exits_nonzero
rm -f "${TMPCFG}"
echo "ALL PASS"
