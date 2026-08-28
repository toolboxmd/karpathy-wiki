#!/bin/bash
# wiki rewrite CLI, cluster compact, and shared-pool worker contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-rewrite/SKILL.md"
DOCTOR_SKILL="${REPO_ROOT}/skills/karpathy-wiki-doctor/SKILL.md"
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${REPO_ROOT}/scripts/wiki-rewrite.sh" ]] || fail "wiki-rewrite.sh is not executable"
[[ -x "${REPO_ROOT}/scripts/wiki-complete-rewrite.sh" ]] || fail "wiki-complete-rewrite.sh is not executable"
[[ -x "${REPO_ROOT}/scripts/wiki-compact-cluster.py" ]] || fail "wiki-compact-cluster.py is not executable"

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
export WIKI_CONFIG_HOME="${TESTDIR}/config-home"
cleanup() {
  local lease pid provider
  while IFS= read -r lease; do
    [[ -n "${lease}" ]] || continue
    pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wrapper_pid", "") or "")' "${lease}" 2>/dev/null || true)"
    provider="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("provider_pid", "") or "")' "${lease}" 2>/dev/null || true)"
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill "${pid}" 2>/dev/null || true
    [[ "${provider}" =~ ^[0-9]+$ ]] && kill "${provider}" 2>/dev/null || true
  done < <(find "${TESTDIR}" -type f -path '*/.locks/ingest-slots/*.lock' 2>/dev/null || true)
  rm -rf "${TESTDIR}"
}
trap cleanup EXIT

make_wiki() {
  local root="$1"
  local auto_commit="${2:-false}"
  bash "${INIT}" main "${root}" >/dev/null
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "test_profile"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test_profile]
provider = "codex"
model = "test-model"
reasoning_effort = "low"

[settings]
auto_commit = ${auto_commit}
EOF
}

write_concept() {
  local path="$1" title="$2" body="$3"
  cat > "${path}" <<EOF
---
title: "${title}"
type: concepts
tags: [cart]
sources: []
summary: "${title}"
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
${body}
EOF
}

write_cluster_job() {
  local wiki="$1"
  mkdir -p "${wiki}/.wiki-pending/rewrite-jobs"
  cat > "${wiki}/.wiki-pending/rewrite-jobs/cart.md" <<'EOF'
---
kind: cluster
object: cart
pages:
  - /concepts/cart-playbook.md
  - /concepts/cart-checkout-button.md
---
EOF
}

write_entity_job() {
  local wiki="$1"
  mkdir -p "${wiki}/.wiki-pending/rewrite-jobs" "${wiki}/entities"
  cat > "${wiki}/entities/carl-weische.md" <<'EOF'
---
title: "Carl Weische"
type: entities
tags: [carl-weische]
sources: []
summary: "Catalog entity"
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
Catalog body.
EOF
  cat > "${wiki}/.wiki-pending/rewrite-jobs/carl-weische.md" <<'EOF'
---
kind: entity
object: carl-weische
pages:
  - /entities/carl-weische.md
---
EOF
}

seed_cart_siblings() {
  local wiki="$1"
  write_concept "${wiki}/concepts/cart-playbook.md" "Cart drawer playbook" "Keep the gift threshold visible."
  write_concept "${wiki}/concepts/cart-checkout-button.md" "Cart checkout button" "Checkout button stays sticky."
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${wiki}" --rebuild-all
  write_cluster_job "${wiki}"
}

count_leases() {
  find "$1/.locks/ingest-slots" -maxdepth 1 -type f -name '*.lock' 2>/dev/null | wc -l | tr -d ' '
}

stop_wiki_workers() {
  local wiki="$1"
  local lease pid provider
  for lease in "${wiki}"/.locks/ingest-slots/*.lock; do
    [[ -f "${lease}" ]] || continue
    pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wrapper_pid", "") or "")' "${lease}" 2>/dev/null || true)"
    provider="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("provider_pid", "") or "")' "${lease}" 2>/dev/null || true)"
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill "${pid}" 2>/dev/null || true
    [[ "${provider}" =~ ^[0-9]+$ ]] && kill "${provider}" 2>/dev/null || true
  done
  sleep 0.2
}

wait_for() {
  local i
  for i in $(seq 1 80); do
    if eval "$1"; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

leases_eq() {
  [[ "$(count_leases "$1")" -eq "$2" ]]
}

assert_compacted() {
  local wiki="$1"
  [[ -f "${wiki}/concepts/cart-playbook.md" ]] || fail "playbook missing"
  [[ -f "${wiki}/concepts/cart-checkout-button.md" ]] || fail "pointer file deleted"
  grep -q 'tags: \[pointer\]' "${wiki}/concepts/cart-checkout-button.md" \
    || fail "folded sibling is not a pointer"
  grep -q 'Cart drawer playbook' "${wiki}/concepts/_index.md" \
    || fail "playbook missing from index"
  if grep -q 'Pointer:' "${wiki}/concepts/_index.md"; then
    fail "pointer leaked into category index"
  fi
  if grep -q 'cart-checkout-button.md' "${wiki}/concepts/_index.md"; then
    fail "pointer filename leaked into category index"
  fi
  grep -q '/concepts/cart-checkout-button.md' "${wiki}/concepts/cart-playbook.md" \
    || fail "playbook related does not list folded slug"
}

test_skill_and_help() {
  [[ -f "${SKILL}" ]] || fail "rewrite skill missing"
  head -12 "${SKILL}" | grep -q '^name: karpathy-wiki-rewrite' || fail "rewrite skill missing name"
  grep -q 'wiki-complete-rewrite.sh' "${SKILL}" || fail "rewrite skill missing complete helper"
  grep -q 'pointer' "${SKILL}" || fail "rewrite skill missing pointer contract"
  grep -q 'playbook' "${SKILL}" || fail "rewrite skill missing playbook contract"
  grep -q 'Do not execute the rewrite' "${DOCTOR_SKILL}" \
    || fail "doctor skill must still refuse to execute rewrite jobs"
  bash "${WIKI_BIN}" help | grep -q rewrite || fail "wiki help missing rewrite"
  echo "PASS: test_skill_and_help"
}

test_test_mode_compacts_two_siblings_and_commits_once() {
  local wiki="${TESTDIR}/cli-compact"
  make_wiki "${wiki}" true
  seed_cart_siblings "${wiki}"
  local before after last
  before="$(cd "${wiki}" && git rev-list --count HEAD)"
  local out
  out="$(WIKI_REWRITE_TEST=1 bash "${WIKI_BIN}" rewrite "${wiki}" 2>&1)" \
    || fail "wiki rewrite test-mode failed: ${out}"
  grep -qi 'not implemented' <<< "${out}" && fail "wiki rewrite still says not implemented"
  grep -q '"status":"completed"' "${wiki}/.rewrite-runs.jsonl" \
    || fail "test-mode rewrite did not write a completed run"
  [[ ! -f "${wiki}/.wiki-pending/rewrite-jobs/cart.md" ]] \
    || fail "completed job was not archived"
  [[ -f "${wiki}/.wiki-pending/archive/rewrite-jobs/cart.md" ]] \
    || fail "job archive missing"
  assert_compacted "${wiki}"
  after="$(cd "${wiki}" && git rev-list --count HEAD)"
  [[ "${after}" -eq $((before + 1)) ]] || fail "expected one rewrite commit, before=${before} after=${after}"
  last="$(cd "${wiki}" && git log -1 --format=%s)"
  [[ "${last}" == "rewrite: cart" ]] || fail "commit message was '${last}'"
  echo "PASS: test_test_mode_compacts_two_siblings_and_commits_once"
}

test_doctor_test_mode_does_not_compact() {
  local wiki="${TESTDIR}/cli-doctor-untouched"
  make_wiki "${wiki}" false
  seed_cart_siblings "${wiki}"
  # Two siblings are not a 6+ cluster, so doctor complete is allowed.
  WIKI_DOCTOR_TEST=1 bash "${WIKI_BIN}" doctor "${wiki}" >/dev/null \
    || fail "doctor test-mode failed on a two-sibling wiki"
  grep -q 'Checkout button stays sticky' "${wiki}/concepts/cart-checkout-button.md" \
    || fail "doctor rewrote a sibling body"
  grep -q 'tags: \[cart\]' "${wiki}/concepts/cart-checkout-button.md" \
    || fail "doctor compacted a sibling into a pointer"
  [[ -f "${wiki}/.wiki-pending/rewrite-jobs/cart.md" ]] \
    || fail "doctor consumed the rewrite job"
  echo "PASS: test_doctor_test_mode_does_not_compact"
}

test_failed_helper_does_not_stamp_completed() {
  local wiki="${TESTDIR}/cli-fail"
  make_wiki "${wiki}" false
  WIKI_ROOT="${wiki}" bash "${REPO_ROOT}/scripts/wiki-complete-rewrite.sh" >/dev/null 2>&1 \
    && fail "complete-rewrite without WIKI_RUN_ID should fail"
  [[ ! -f "${wiki}/.rewrite-runs.jsonl" ]] \
    || grep -qv '"status":"completed"' "${wiki}/.rewrite-runs.jsonl" \
    || fail "failed complete-rewrite wrote a completed record"
  echo "PASS: test_failed_helper_does_not_stamp_completed"
}

test_entity_job_is_not_drained() {
  local wiki="${TESTDIR}/cli-entity"
  make_wiki "${wiki}" true
  write_entity_job "${wiki}"
  local before out
  before="$(cd "${wiki}" && git rev-list --count HEAD)"
  out="$(WIKI_REWRITE_TEST=1 bash "${WIKI_BIN}" rewrite "${wiki}" 2>&1)" \
    || fail "entity-only rewrite should be a no-op: ${out}"
  grep -q 'nothing pending' <<< "${out}" || fail "entity-only rewrite did not skip, got: ${out}"
  [[ -f "${wiki}/.wiki-pending/rewrite-jobs/carl-weische.md" ]] \
    || fail "entity job was consumed"
  grep -q 'Catalog body' "${wiki}/entities/carl-weische.md" \
    || fail "entity page was rewritten"
  local after
  after="$(cd "${wiki}" && git rev-list --count HEAD)"
  [[ "${after}" -eq "${before}" ]] || fail "entity skip created a commit"
  echo "PASS: test_entity_job_is_not_drained"
}

test_dispatch_spawns_rewrite_worker_lease() {
  local wiki="${TESTDIR}/cli-hold"
  make_wiki "${wiki}" false
  seed_cart_siblings "${wiki}"
  WIKI_DISPATCH_TEST_MODE=1 \
  WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
  WIKI_DISPATCH_TEST_PROVIDER_SECONDS=8 \
  WIKI_DISPATCH_TEST_HEARTBEAT_SECONDS=0.1 \
  WIKI_DISPATCH_TEST_NO_REFILL=1 \
    python3 "${DISPATCH}" rewrite --wiki "${wiki}" --run-id "rew-hold-1" \
    || fail "dispatch rewrite hold spawn failed"
  wait_for 'leases_eq "'"${wiki}"'" 1' \
    || fail "rewrite worker did not take a slot lease"
  python3 - "${wiki}/.locks/ingest-slots" <<'PY' || fail "rewrite lease is not marked job=rewrite"
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
leases = list(root.glob("*.lock"))
assert leases, "no lease"
lease = json.loads(leases[0].read_text())
assert lease.get("job") == "rewrite", lease
assert lease.get("run_id") == "rew-hold-1", lease
PY
  grep -q '"status":"completed"' "${wiki}/.rewrite-runs.jsonl" 2>/dev/null \
    && fail "hold-mode rewrite wrote completed before the worker finished"
  stop_wiki_workers "${wiki}"
  echo "PASS: test_dispatch_spawns_rewrite_worker_lease"
}

test_second_rewrite_skips_while_leased() {
  local wiki="${TESTDIR}/cli-skip"
  make_wiki "${wiki}" false
  seed_cart_siblings "${wiki}"
  WIKI_DISPATCH_TEST_MODE=1 \
  WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
  WIKI_DISPATCH_TEST_PROVIDER_SECONDS=8 \
  WIKI_DISPATCH_TEST_NO_REFILL=1 \
    python3 "${DISPATCH}" rewrite --wiki "${wiki}" --run-id "rew-first" \
    || fail "first rewrite spawn failed"
  wait_for 'leases_eq "'"${wiki}"'" 1' || fail "first rewrite lease missing"
  local out
  out="$(
    WIKI_DISPATCH_TEST_MODE=1 \
    WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
    WIKI_DISPATCH_TEST_NO_REFILL=1 \
      python3 "${DISPATCH}" rewrite --wiki "${wiki}" --run-id "rew-second"
  )" || fail "second rewrite enqueue should exit 0"
  grep -qi 'skipped' <<< "${out}" || fail "second rewrite did not skip, got: ${out}"
  [[ "$(count_leases "${wiki}")" -eq 1 ]] || fail "second rewrite created another lease"
  stop_wiki_workers "${wiki}"
  echo "PASS: test_second_rewrite_skips_while_leased"
}

test_tick_starts_rewrite_when_idle() {
  local wiki="${TESTDIR}/cli-tick"
  make_wiki "${wiki}" false
  seed_cart_siblings "${wiki}"
  WIKI_DISPATCH_TEST_MODE=1 \
  WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
  WIKI_DISPATCH_TEST_PROVIDER_SECONDS=8 \
  WIKI_DISPATCH_TEST_NO_REFILL=1 \
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source scheduled \
    || fail "tick did not start with a rewrite job waiting"
  wait_for 'leases_eq "'"${wiki}"'" 1' || fail "tick did not lease a rewrite job"
  python3 - "${wiki}/.locks/ingest-slots" <<'PY' || fail "tick lease is not job=rewrite"
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
leases = list(root.glob("*.lock"))
assert leases, "no lease"
lease = json.loads(leases[0].read_text())
assert lease.get("job") == "rewrite", lease
PY
  stop_wiki_workers "${wiki}"
  echo "PASS: test_tick_starts_rewrite_when_idle"
}

test_rewrite_skips_while_ingest_leased() {
  local wiki="${TESTDIR}/cli-busy"
  make_wiki "${wiki}" false
  seed_cart_siblings "${wiki}"
  printf 'capture\n' > "${wiki}/.wiki-pending/001.md"
  WIKI_DISPATCH_TEST_MODE=1 \
  WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
  WIKI_DISPATCH_TEST_PROVIDER_SECONDS=8 \
  WIKI_DISPATCH_TEST_NO_REFILL=1 \
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source scheduled \
    || fail "ingest tick failed"
  wait_for 'leases_eq "'"${wiki}"'" 1' || fail "ingest lease missing"
  local out
  out="$(
    WIKI_DISPATCH_TEST_MODE=1 \
    WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
    WIKI_DISPATCH_TEST_NO_REFILL=1 \
      python3 "${DISPATCH}" rewrite --wiki "${wiki}" --run-id "rew-busy"
  )" || fail "rewrite enqueue during ingest should exit 0"
  grep -qi 'skipped' <<< "${out}" || fail "rewrite did not skip busy wiki, got: ${out}"
  [[ "$(count_leases "${wiki}")" -eq 1 ]] || fail "rewrite started beside ingest"
  stop_wiki_workers "${wiki}"
  echo "PASS: test_rewrite_skips_while_ingest_leased"
}

test_skill_and_help
test_test_mode_compacts_two_siblings_and_commits_once
test_doctor_test_mode_does_not_compact
test_failed_helper_does_not_stamp_completed
test_entity_job_is_not_drained
test_dispatch_spawns_rewrite_worker_lease
test_second_rewrite_skips_while_leased
test_tick_starts_rewrite_when_idle
test_rewrite_skips_while_ingest_leased
echo "ALL PASS"
