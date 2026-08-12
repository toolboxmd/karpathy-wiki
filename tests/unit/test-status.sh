#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

write_runtime_config() {
  local root="$1"
  local mode="${2:-session_start}"
  local usage="${3:-auto}"
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "${mode}"
schedule_interval_seconds = 60
max_processes = 3
default_profile = "grok_medium"
fallback_profile = "sonnet_low"
heartbeat_seconds = 5
stale_after_seconds = 15
usage_monitor = "${usage}"

[ingest.profiles.grok_medium]
provider = "grok"
model = "grok-test"
reasoning_effort = "medium"

[ingest.profiles.sonnet_low]
provider = "claude"
model = "sonnet-test"
reasoning_effort = "low"

[settings]
auto_commit = false
EOF
}

test_status_on_empty_wiki() {
  setup
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "role: main" || { echo "FAIL: role missing"; teardown; exit 1; }
  echo "${output}" | grep -q "pending: 0" || { echo "FAIL: pending missing"; teardown; exit 1; }
  echo "${output}" | grep -q "total pages:" || { echo "FAIL: total pages missing"; teardown; exit 1; }
  echo "${output}" | grep -q "pages below 3.5 quality:" || { echo "FAIL: quality line missing"; teardown; exit 1; }
  echo "${output}" | grep -q "tag synonyms flagged:" || { echo "FAIL: synonyms line missing"; teardown; exit 1; }
  echo "${output}" | grep -q "^index.md:" || { echo "FAIL: status output missing index.md field"; teardown; exit 1; }
  echo "${output}" | grep -q "runtime config: missing" || { echo "FAIL: missing runtime config not surfaced"; teardown; exit 1; }
  echo "${output}" | grep -q "Run: wiki config init-local" || { echo "FAIL: missing runtime config action absent"; teardown; exit 1; }
  echo "PASS: test_status_on_empty_wiki"
  teardown
}

test_status_reports_runtime_and_scheduler_state() {
  setup
  write_runtime_config "${WIKI}" scheduled auto
  local output
  output="$(WIKI_CODEXBAR_EXECUTABLE=/definitely/missing bash "${STATUS}" "${WIKI}")"
  grep -q "runtime config: configured" <<< "${output}" \
    || { echo "FAIL: configured runtime missing"; teardown; exit 1; }
  grep -q "dispatch mode: scheduled" <<< "${output}" \
    || { echo "FAIL: scheduled mode missing"; teardown; exit 1; }
  grep -q "scheduler: mismatch" <<< "${output}" \
    || { echo "FAIL: scheduled-without-agent mismatch missing"; teardown; exit 1; }
  grep -q "profiles: default=grok_medium, fallback=sonnet_low" <<< "${output}" \
    || { echo "FAIL: profile summary missing"; teardown; exit 1; }
  grep -q "usage monitor: reactive" <<< "${output}" \
    || { echo "FAIL: missing CodexBar should be reactive"; teardown; exit 1; }
  echo "PASS: test_status_reports_runtime_and_scheduler_state"
  teardown
}

test_status_reports_legacy_migration_action() {
  setup
  cat >> "${WIKI}/.wiki-config" <<'EOF'

[platform]
headless_command = "claude --model sonnet --effort low -p"
EOF
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  grep -q "runtime config: migration required" <<< "${output}" \
    || { echo "FAIL: legacy migration state missing"; teardown; exit 1; }
  grep -Fq "Run: wiki config migrate" <<< "${output}" \
    || { echo "FAIL: legacy migration command missing"; teardown; exit 1; }
  grep -Fq -- "--dry-run" <<< "${output}" \
    || { echo "FAIL: migration command lacks dry-run"; teardown; exit 1; }
  echo "PASS: test_status_reports_legacy_migration_action"
  teardown
}

test_status_reports_queue_runtime_health() {
  setup
  write_runtime_config "${WIKI}" session_start off
  mkdir -p "${WIKI}/.locks/ingest-slots" "${WIKI}/.wiki-pending/failed"
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
    "${WIKI}/.wiki-pending/stalled.md.processing"
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
    "${WIKI}/.wiki-pending/fresh.md.processing"
  touch -t "$(date -v-60S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '60 seconds ago' '+%Y%m%d%H%M.%S')" \
    "${WIKI}/.wiki-pending/stalled.md.processing"
  cat > "${WIKI}/.locks/ingest-slots/1.lock" <<'EOF'
{"run_id":"run-stalled","slot":1,"capture":"stalled.md.processing","profile":"grok_medium"}
EOF
  cat > "${WIKI}/.locks/ingest-slots/2.lock" <<'EOF'
{"run_id":"run-fresh","slot":2,"capture":"fresh.md.processing","profile":"sonnet_low"}
EOF
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
    "${WIKI}/.wiki-pending/failed/gave-up.md"
  cat > "${WIKI}/.wiki-pending/needs-detail.md" <<'EOF'
---
needs_more_detail: true
needs_more_detail_reason: "fixture"
---
EOF
  retry_after="$(python3 -c 'from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)+timedelta(hours=1)).isoformat().replace("+00:00","Z"))')"
  cat > "${WIKI}/.ingest-runs.jsonl" <<EOF
not-json
{"run_id":"rate-1","capture":"x.md","status":"provider_rate_limited","profile":"grok_medium","provider":"grok","model":"grok-test","retry_after":"${retry_after}","at":"2026-08-11T00:00:00Z"}
{"run_id":"concurrent-older","capture":"older.md","status":"completed","profile":"grok_medium","provider":"grok","model":"grok-test","at":"2026-08-11T00:00:01Z"}
EOF
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  grep -q "active ingests: 2 / 3" <<< "${output}" \
    || { echo "FAIL: active slot count wrong"; teardown; exit 1; }
  grep -q "stalled heartbeat: 1" <<< "${output}" \
    || { echo "FAIL: stalled heartbeat count wrong"; teardown; exit 1; }
  grep -q "failed captures: 1" <<< "${output}" \
    || { echo "FAIL: failed capture count wrong"; teardown; exit 1; }
  grep -q "captures needing more detail: 1" <<< "${output}" \
    || { echo "FAIL: needs-more-detail count wrong"; teardown; exit 1; }
  grep -q "run history malformed lines: 1" <<< "${output}" \
    || { echo "FAIL: malformed run count missing"; teardown; exit 1; }
  grep -Fq "provider cooldowns: grok_medium until ${retry_after}" <<< "${output}" \
    || { echo "FAIL: cooldown reset missing or cleared by concurrent completion"; teardown; exit 1; }
  grep -q "usage monitor: off" <<< "${output}" \
    || { echo "FAIL: off usage monitor missing"; teardown; exit 1; }
  echo "PASS: test_status_reports_queue_runtime_health"
  teardown
}

test_status_counts_pending() {
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c1.md"
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c2.md"
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "pending: 2" || {
    echo "FAIL: expected 'pending: 2', got:"
    echo "${output}"
    teardown; exit 1
  }
  echo "PASS: test_status_counts_pending"
  teardown
}

test_status_reports_quality_rollup() {
  setup
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/low.md" <<'EOF'
---
title: "Low"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 2
  completeness: 2
  signal: 2
  interlinking: 2
  overall: 2.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

body
EOF
  cat > "${WIKI}/concepts/high.md" <<'EOF'
---
title: "High"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

body
EOF
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "pages below 3.5 quality: 1" || {
    echo "FAIL: quality rollup wrong. output: ${output}"; teardown; exit 1
  }
  echo "PASS: test_status_reports_quality_rollup"
  teardown
}

test_status_reports_tag_synonyms() {
  setup
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/a.md" <<'EOF'
---
title: "A"
type: concept
tags: [dentistry]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---
body
EOF
  cat > "${WIKI}/concepts/b.md" <<'EOF'
---
title: "B"
type: concept
tags: [dentistries]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---
body
EOF
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -qE "tag synonyms flagged: [1-9]" || {
    echo "FAIL: tag synonym report missing. output: ${output}"; teardown; exit 1
  }
  echo "PASS: test_status_reports_tag_synonyms"
  teardown
}

test_status_walks_discovered_categories() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/ideas" "${tmp}/wiki/raw" "${tmp}/wiki/.wiki-pending"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/concepts/foo.md"
  echo "stub" > "${tmp}/wiki/ideas/bar.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1 || true)"
  echo "${out}" | grep -q "concepts" && echo "${out}" | grep -q "ideas" || { echo "FAIL: status missing categories"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_walks_discovered_categories"
}

test_status_includes_ideas_directory() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/ideas" "${tmp}/wiki/raw"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/ideas/foo.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "ideas" || { echo "FAIL: ideas/ not surfaced"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_includes_ideas_directory"
}

test_status_depth_violation_count() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts/a/b/c/d" "${tmp}/wiki/raw"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/concepts/a/b/c/d/deep.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "categories exceeding depth 4" || { echo "FAIL: depth-violation line absent"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_depth_violation_count"
}

test_status_soft_ceiling_line() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/raw"
  printf 'role = "main"\n' > "${tmp}/wiki/.wiki-config"
  for c in a b c d e f g h i; do
    mkdir -p "${tmp}/wiki/${c}"
    echo "stub" > "${tmp}/wiki/${c}/x.md"
  done
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "category count vs soft-ceiling" || { echo "FAIL: soft-ceiling line absent"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
  echo "PASS: test_status_soft_ceiling_line"
}

test_status_reports_selective_promotion_decisions() {
  setup
  mkdir -p "${WIKI}/.wiki-pending/archive/2026-08"
  for item in pending:null local:keep-local promoted:promoted; do
    name="${item%%:*}"
    decision="${item#*:}"
    cat > "${WIKI}/.wiki-pending/archive/2026-08/${name}.md" <<EOF
---
promotion_policy: "selective"
promotion_decision: ${decision}
---
EOF
  done
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  grep -q "1 awaiting decision" <<< "${output}" \
    || { echo "FAIL: pending promotion decision missing"; teardown; exit 1; }
  grep -q "1 kept local" <<< "${output}" \
    || { echo "FAIL: keep-local promotion count missing"; teardown; exit 1; }
  grep -q "1 promoted" <<< "${output}" \
    || { echo "FAIL: promoted count missing"; teardown; exit 1; }
  echo "PASS: test_status_reports_selective_promotion_decisions"
  teardown
}

test_status_on_empty_wiki
test_status_reports_runtime_and_scheduler_state
test_status_reports_legacy_migration_action
test_status_reports_queue_runtime_health
test_status_counts_pending
test_status_reports_quality_rollup
test_status_reports_tag_synonyms
test_status_walks_discovered_categories
test_status_includes_ideas_directory
test_status_depth_violation_count
test_status_soft_ceiling_line
test_status_reports_selective_promotion_decisions
echo "ALL PASS"
