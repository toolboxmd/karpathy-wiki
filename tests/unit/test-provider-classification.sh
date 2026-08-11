#!/bin/bash
# Structured provider errors classify technical outcomes without reading prose.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures/provider-results"
export PYTHONPATH="${REPO_ROOT}/scripts"

fail() { echo "FAIL: $*" >&2; exit 1; }

python3 - "${FIXTURES}" <<'PY' || fail "provider result classification failed"
import pathlib, sys
from wiki_providers import classify_provider_result

root = pathlib.Path(sys.argv[1])
def read(rel): return (root / rel).read_text()

assert classify_provider_result("claude", 1, read("claude/rate-limit.json"), "") == "provider_rate_limited"
assert classify_provider_result("grok", 1, read("grok/rate-limit.jsonl"), "") == "provider_rate_limited"
assert classify_provider_result("codex", 1, read("codex/auth.jsonl"), "") == "configuration_or_auth_failure"
assert classify_provider_result("claude", 1, read("claude/auth.json"), "") == "configuration_or_auth_failure"
assert classify_provider_result("codex", 1, read("codex/ordinary-agent-text.jsonl"), "") == "transient_failure"
assert classify_provider_result("grok", 1, "", read("grok/transient.stderr")) == "transient_failure"
assert classify_provider_result("codex", 2, "", "error: invalid value 'ultra' for '--effort'") == "configuration_or_auth_failure"
assert classify_provider_result("grok", 1, '{"type":"error","error":{"message":"unknown model custom-id"}}', "") == "configuration_or_auth_failure"

# A successful response that merely discusses rate limits is still success.
ordinary = read("codex/ordinary-agent-text.jsonl")
assert classify_provider_result("codex", 0, ordinary, "rate limit quota login") == "success"
PY

echo "PASS: provider errors classify from error channels without prose false positives"
