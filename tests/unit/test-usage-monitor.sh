#!/bin/bash
# CodexBar is an optional conservative preflight, never a hard dependency.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export PYTHONPATH="${REPO_ROOT}/scripts"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

python3 - <<'PY' || fail "CodexBar JSON parsing failed"
from wiki_usage import parse_codexbar_usage

exhausted = '[{"provider":"grok","usage":{"primary":{"usedPercent":100,"resetsAt":"2026-08-15T07:02:38Z"},"secondary":null,"tertiary":null,"identity":{"accountEmail":"secret@example.com"}},"pace":{"primary":{"willLastToReset":false}}}]'
result = parse_codexbar_usage(exhausted, "grok")
assert result.monitor_available is True
assert result.exhausted is True
assert result.resets_at == "2026-08-15T07:02:38Z"
assert "secret@example.com" not in repr(result)

predictive_only = '[{"provider":"grok","usage":{"primary":{"usedPercent":76,"resetsAt":"2026-08-15T07:02:38Z"}},"pace":{"primary":{"willLastToReset":false,"etaSeconds":90000}}}]'
result = parse_codexbar_usage(predictive_only, "grok")
assert result.monitor_available is True
assert result.exhausted is False

explicit = '[{"provider":"claude","usage":{"primary":{"status":"exhausted","resetsAt":"2026-08-12T00:00:00Z"},"secondary":{"usedPercent":40}}}]'
result = parse_codexbar_usage(explicit, "claude")
assert result.exhausted is True

assert parse_codexbar_usage("not json", "grok").monitor_available is False
assert parse_codexbar_usage('[]', "grok").monitor_available is False
PY

MISSING="${TESTDIR}/missing-codexbar"
python3 - "${MISSING}" <<'PY' || fail "missing CodexBar should degrade gracefully"
import sys
from wiki_usage import check_codexbar_usage
result = check_codexbar_usage("grok", 1, executable=sys.argv[1])
assert result.monitor_available is False
assert result.exhausted is False
PY

SLOW="${TESTDIR}/slow-codexbar"
cat > "${SLOW}" <<'EOF'
#!/bin/bash
sleep 2
printf '%s\n' '[]'
EOF
chmod +x "${SLOW}"
python3 - "${SLOW}" <<'PY' || fail "CodexBar timeout should degrade gracefully"
import sys, time
from wiki_usage import check_codexbar_usage
start = time.monotonic()
result = check_codexbar_usage("grok", 0.1, executable=sys.argv[1])
assert time.monotonic() - start < 1
assert result.monitor_available is False
assert result.exhausted is False
PY

BROKEN="${TESTDIR}/broken-codexbar"
cat > "${BROKEN}" <<'EOF'
#!/bin/bash
printf '%s\n' 'provider unsupported' >&2
exit 2
EOF
chmod +x "${BROKEN}"
python3 - "${BROKEN}" <<'PY' || fail "CodexBar non-zero should degrade gracefully"
import sys
from wiki_usage import check_codexbar_usage
result = check_codexbar_usage("unknown-provider", 1, executable=sys.argv[1])
assert result.monitor_available is False
assert result.exhausted is False
PY

echo "PASS: optional CodexBar parsing is conservative and identity-free"
