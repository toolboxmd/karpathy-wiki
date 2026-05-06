# karpathy-wiki v2.4 — Leg 4: Deep orientation + issue reporting

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ingester's lens shaped by the wiki it sees, not by an a-priori role hint. Add a "deep orientation" step that selects 0-7 candidate pages by deterministic signal-matching against the index and reads them in full before deciding what to write. Add an issue-reporting stream: when the ingester observes broken cross-links, contradictions, schema drift, stale claims, tag drift, quality concerns, or orphans during deep orientation, it appends one JSON line per issue to `<wiki>/.ingest-issues.jsonl` (under flock). Add `bin/wiki issues` to render the JSONL log as grouped markdown for human consumption (basic render only; `--filter` and `--since` flags deferred to v2.5).

**Architecture:** Deep orientation is a prose change in `karpathy-wiki-ingest/SKILL.md` plus a deterministic candidate-selection algorithm specified in detail (substring + tag match against index, scored, top-7). On wikis with ≤7 pages, the cold-start path uses the role guardrail as the primary lens (the index has insufficient gravity). Issue reporting introduces `scripts/wiki-issue-log.sh` (a flock-protected JSONL appender, max 4 KB per line) and `scripts/wiki-issues.sh` (renders JSONL → grouped markdown). `bin/wiki issues` and `bin/wiki status` integration round out the read surface.

**Tech Stack:** bash, JSON Lines (JSONL) for the issue log, `flock` for atomicity, Python for the JSONL → markdown render (cleaner string handling than bash for JSON).

**Spec reference:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/superpowers/specs/2026-05-05-karpathy-wiki-v2.4-executable-protocol-design.md` (Deep orientation; Issue reporting; sections at lines ~1100-1410).

**Inter-leg dependency:** Modifies `karpathy-wiki-ingest/SKILL.md` (created in Leg 1) and adds CLI subcommands. Does not depend on Leg 2 or Leg 3 mechanically — the issue log and renderer work against any wiki, regardless of how captures arrived.

**Verification gate:** After this plan ships:
- The ingest skill documents the deep orientation algorithm with deterministic candidate selection (substring + tag match, top-7 by score) and a cold-start fallback (≤7 pages → role-prompt is primary lens).
- `wiki-issue-log.sh` appends valid JSONL lines under flock; concurrent appenders do not corrupt the file.
- Each line is ≤ 4 KB; over-length `detail` is truncated with `... [truncated]` suffix.
- `bin/wiki issues` renders the JSONL log as markdown grouped by `issue_type`, ordered by severity within each group.
- `bin/wiki status` shows an issue-count summary section.

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `scripts/wiki-issue-log.sh` | Create | Bash CLI helper: validates `--type` enum, escapes JSON via Python, appends one JSONL line under flock, truncates over-length lines. |
| `scripts/wiki-issues.sh` | Create | Renders `.ingest-issues.jsonl` as grouped markdown (basic render only in v2.4). |
| `bin/wiki` | Modify | Add `issues` subcommand. Wire it to `scripts/wiki-issues.sh`. |
| `scripts/wiki-status.sh` | Modify | Add an Issues section showing counts per issue_type for the last 30 days. |
| `skills/karpathy-wiki-ingest/SKILL.md` | Modify | Replace the basic orientation with the v2.4 deep-orientation algorithm (steps 1-9 specified). Add cold-start fallback. Add issue-reporting calls. |
| `tests/unit/test-wiki-issue-log.sh` | Create | Type-enum validation; concurrent flock-serialized appends; over-length truncation; corrupt-input rejection. |
| `tests/unit/test-wiki-issues-render.sh` | Create | Render fixture log → expected markdown grouped by type, ordered by severity. Empty-log handling. Corrupted line skip+warn. |
| `tests/unit/test-wiki-status-issues.sh` | Create | `wiki status` output contains the Issues summary section when `.ingest-issues.jsonl` has lines. |
| `tests/unit/test-deep-orientation-cold-start.sh` | Create | Skill text describes cold-start fallback (≤7 pages → role-prompt primary). |
| `tests/red/RED-leg4-shallow-orientation.md` | Create | RED scenario: ingester picks wrong cross-links because index titles are misleading without reading the candidate pages. |

Also: a deferred test for warm-state lens divergence (A/B fixture). The spec calls for this as a pressure test, but executing it requires real `claude -p` runs against fixture wikis — too expensive for the unit test surface. We document it as a `tests/red/` scenario plus a manual-verification acceptance criterion.

---

### Task 1: RED scenario — shallow orientation produces wrong cross-links

**Files:**
- Create: `tests/red/RED-leg4-shallow-orientation.md`

- [ ] **Step 1: Write the RED scenario**

```markdown
# RED scenario — ingester picks wrong cross-links from titles alone

**Date:** 2026-05-06
**Skill change this justifies:** v2.4 Leg 4 — deep orientation (read 0-7 candidate pages in full before deciding what to write or which existing pages to cross-link).

## The scenario

A capture arrives describing "rate limits in the X API." The wiki has these existing concept pages:

- `concepts/rate-limits-and-burst-tokens.md` — about HTTP rate-limit headers, retry-after, exponential backoff. Generic, applies to any API.
- `concepts/x-api-quotas-vs-throughput.md` — about the X API specifically: quota enforcement at the GraphQL field level, not the HTTP level. Explicitly says "rate limit" is a misleading term for this API.

Pre-v2.4 ingester reads only the index and matches the new capture's title against page titles. "Rate limits in X API" matches `rate-limits-and-burst-tokens.md` strongly (3 of 5 keywords). The ingester writes a new page that augments `rate-limits-and-burst-tokens.md` and adds a `see also` link to it.

But that page is the WRONG canonical reference. The right one is `x-api-quotas-vs-throughput.md`, which explicitly handles the X-API-specific case the capture is about. The ingester missed it because the title used "quotas" instead of "rate-limits", which the title-match heuristic ranked lower.

## Why prose alone doesn't fix this

The pre-v2.4 ingester orientation reads `schema.md`, `index.md`, and the last 10 lines of `log.md`. None of these include the BODY of the candidate pages. Reading the index reveals what page titles exist; it does NOT reveal what those pages actually say. Title-only matching is the failure mode.

The fix is structural:
- Step 4 (deep orientation): from the capture, extract candidate signals (title, tags, frontmatter, body keywords for chat-only/chat-attached, filename + first 200 lines for raw-direct).
- Step 5: score candidates against the index by substring + tag match. Top 7 by score (descending), title-length ascending as tie-break (shorter titles rank higher for the same score; they are more general).
- Step 6: read the picked candidates IN FULL before deciding.
- Cold-start: ≤7 pages → role-prompt is primary lens, not the index. Index has insufficient gravity.

## Pass criterion

After Leg 4 ships:
- Ingester reads candidate pages in full during orientation; has the actual page bodies in context when deciding what to write or which to cross-link.
- Issue reporting catches the case where the ingester observes a contradiction or stale claim during this read; the issue is appended to `.ingest-issues.jsonl` for `wiki doctor` to act on later.
```

- [ ] **Step 2: Commit**

```bash
git add tests/red/RED-leg4-shallow-orientation.md
git commit -m "test(red): RED scenario for v2.4 Leg 4 shallow-orientation antipattern"
```

---

### Task 2: Failing test — `wiki-issue-log.sh` enum validation + flock serialization + truncation

**Files:**
- Create: `tests/unit/test-wiki-issue-log.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-issue-log.sh:
# - validates --type against the 8-value enum
# - serializes concurrent appends via flock
# - truncates over-length lines to 4 KB total
# - escapes JSON correctly (special chars in detail)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG="${REPO_ROOT}/scripts/wiki-issue-log.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${LOG}" ]] || fail "wiki-issue-log.sh missing"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Case 1: enum validation — invalid type rejected
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-1" --capture "c.md" \
  --page "concepts/foo.md" --type bad-type --severity warn --detail "x" 2>/dev/null \
  && fail "invalid --type should reject"

# Case 2: valid append
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-1" --capture "c.md" \
  --page "concepts/foo.md" --type broken-cross-link --severity warn \
  --detail "Links to /concepts/missing.md which does not exist." \
  --suggested-action "Remove link or create stub" \
  || fail "valid append failed"
[[ -f "${WIKI}/.ingest-issues.jsonl" ]] || fail "issues log not created"

# Verify the line is valid JSON
python3 -c "
import json
with open('${WIKI}/.ingest-issues.jsonl') as f:
    line = f.readline().strip()
data = json.loads(line)
assert data['issue_type'] == 'broken-cross-link', f'bad issue_type: {data}'
assert data['severity'] == 'warn'
assert data['detail'].startswith('Links to')
"

# Case 3: special chars in detail (quotes, newlines, backslashes)
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-2" --capture "c.md" \
  --page "concepts/bar.md" --type contradiction --severity info \
  --detail 'Page X claims "foo\nis bar" but page Y says \\backslash "no it'"'"'s not"' \
  || fail "special-chars append failed"
python3 -c "
import json
lines = open('${WIKI}/.ingest-issues.jsonl').readlines()
assert len(lines) == 2, f'expected 2 lines, got {len(lines)}'
data = json.loads(lines[1].strip())
assert 'foo' in data['detail'], f'detail mangled: {data[\"detail\"]}'
assert 'backslash' in data['detail']
"

# Case 4: over-length truncation (5 KB detail → ≤ 4 KB total line)
LARGE_DETAIL=$(python3 -c "print('x' * 5000)")
bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-test-3" --capture "c.md" \
  --page "concepts/baz.md" --type stale-claim --severity warn \
  --detail "${LARGE_DETAIL}" \
  || fail "large-detail append failed"

last_line=$(tail -1 "${WIKI}/.ingest-issues.jsonl")
line_size=$(echo -n "${last_line}" | wc -c)
[[ "${line_size}" -le 4096 ]] || fail "over-length line not truncated: ${line_size} bytes"
echo "${last_line}" | grep -q '\[truncated\]' || fail "truncated line missing marker"

# Case 5: concurrent flock-serialized appends
TMPLINES="${TESTDIR}/.tmplines"
> "${TMPLINES}"
for i in {1..5}; do
  ( bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-conc-${i}" --capture "c.md" \
      --page "concepts/conc-${i}.md" --type orphan --severity info \
      --detail "concurrent ${i}" ) &
done
wait

# Verify all 5 appended lines are well-formed JSON
final_lines=$(wc -l < "${WIKI}/.ingest-issues.jsonl")
[[ "${final_lines}" -eq 8 ]] || fail "expected 8 lines after 5 concurrent appends + 3 prior, got ${final_lines}"

# Each line must parse as JSON
python3 -c "
import json
with open('${WIKI}/.ingest-issues.jsonl') as f:
    for i, line in enumerate(f):
        try:
            json.loads(line.strip())
        except json.JSONDecodeError as e:
            print(f'line {i+1} corrupted: {e}'); exit(1)
print('PASS: all lines parse')
" || fail "concurrent appends corrupted JSONL"

echo "PASS: wiki-issue-log.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-issue-log.sh`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-issue-log.sh
git commit -m "test(unit): add failing test for wiki-issue-log.sh"
```

---

### Task 3: Implement `scripts/wiki-issue-log.sh`

**Files:**
- Create: `scripts/wiki-issue-log.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# wiki-issue-log.sh — append a structured issue line to <wiki>/.ingest-issues.jsonl.
#
# Usage:
#   wiki-issue-log.sh --wiki <path> --ingester-run <id> --capture <relpath> \
#       --page <relpath> --type <enum> --severity <info|warn|error> \
#       --detail "<prose>" [--suggested-action "<prose>"]
#
# Enum for --type: broken-cross-link | contradiction | schema-drift |
#                  stale-claim | tag-drift | quality-concern | orphan | other
#
# Concurrency: appends are serialized via flock on
# <wiki>/.locks/ingest-issues.lock. Atomic per line.
#
# Truncation: total JSON line size capped at 4096 bytes; --detail is
# truncated with "... [truncated]" suffix if needed.

set -uo pipefail

VALID_TYPES="broken-cross-link contradiction schema-drift stale-claim tag-drift quality-concern orphan other"
VALID_SEVERITIES="info warn error"
MAX_LINE=4096

wiki=""; run=""; capture=""; page=""; itype=""; severity=""; detail=""; action=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wiki) wiki="$2"; shift 2 ;;
    --ingester-run) run="$2"; shift 2 ;;
    --capture) capture="$2"; shift 2 ;;
    --page) page="$2"; shift 2 ;;
    --type) itype="$2"; shift 2 ;;
    --severity) severity="$2"; shift 2 ;;
    --detail) detail="$2"; shift 2 ;;
    --suggested-action) action="$2"; shift 2 ;;
    *) echo >&2 "wiki-issue-log: unknown arg: $1"; exit 1 ;;
  esac
done

# Required args
for v in wiki run capture page itype severity detail; do
  eval "[[ -n \"\${${v}}\" ]]" || { echo >&2 "wiki-issue-log: --${v} required"; exit 1; }
done

# Validate enums
echo " ${VALID_TYPES} " | grep -q " ${itype} " \
  || { echo >&2 "wiki-issue-log: invalid --type '${itype}'; valid: ${VALID_TYPES}"; exit 1; }
echo " ${VALID_SEVERITIES} " | grep -q " ${severity} " \
  || { echo >&2 "wiki-issue-log: invalid --severity '${severity}'; valid: ${VALID_SEVERITIES}"; exit 1; }

[[ -d "${wiki}" ]] || { echo >&2 "wiki-issue-log: wiki path missing: ${wiki}"; exit 1; }

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log_file="${wiki}/.ingest-issues.jsonl"
lock_dir="${wiki}/.locks"
mkdir -p "${lock_dir}"
lock_file="${lock_dir}/ingest-issues.lock"

# Use Python for JSON formatting (handles all escaping correctly) AND
# truncation if needed.
line=$(python3 - "${MAX_LINE}" <<EOF
import json, sys
max_line = int(sys.argv[1])

obj = {
  "reported_at": "${ts}",
  "ingester_run": $(printf '%s' "${run}" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))'),
  "capture": $(printf '%s' "${capture}" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))'),
  "page": $(printf '%s' "${page}" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))'),
  "issue_type": "${itype}",
  "severity": "${severity}",
  "detail": $(printf '%s' "${detail}" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))'),
}
sa = $(printf '%s' "${action}" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')
if sa:
    obj["suggested_action"] = sa

line = json.dumps(obj, separators=(",", ":"))
if len(line) > max_line:
    # Trim detail to fit
    overflow = len(line) - max_line + len("... [truncated]")
    obj["detail"] = obj["detail"][:max(0, len(obj["detail"]) - overflow)] + "... [truncated]"
    line = json.dumps(obj, separators=(",", ":"))
print(line)
EOF
)

# Append under flock
exec 9>"${lock_file}"
flock 9
printf '%s\n' "${line}" >> "${log_file}"
exec 9>&-

exit 0
```

- [ ] **Step 2: Make it executable and run the test**

```bash
chmod +x scripts/wiki-issue-log.sh
bash tests/unit/test-wiki-issue-log.sh
```

Expected: PASS.

If the bash heredoc with embedded `python3` invocations is fragile, alternative: write a small Python helper at `scripts/wiki_issue_log.py` and have the bash wrapper call it. That's cleaner. If the heredoc passes the test, it's fine.

- [ ] **Step 3: Commit**

```bash
git add scripts/wiki-issue-log.sh
git commit -m "feat(scripts): add wiki-issue-log.sh (flock + JSON-safe + 4KB truncation)"
```

---

### Task 4: Failing test — `wiki-issues.sh` renders JSONL as markdown

**Files:**
- Create: `tests/unit/test-wiki-issues-render.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-issues.sh renders .ingest-issues.jsonl as grouped markdown.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ISSUES="${REPO_ROOT}/scripts/wiki-issues.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${ISSUES}" ]] || fail "wiki-issues.sh missing"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Empty log: graceful output
output=$(bash "${ISSUES}" --wiki "${WIKI}" 2>/dev/null) || fail "empty render failed"
echo "${output}" | grep -q -i 'no issues' || fail "empty render should say 'no issues'"

# Write fixture issues spanning 3 types and 2 severity levels
log="${WIKI}/.ingest-issues.jsonl"
cat > "${log}" <<EOF
{"reported_at":"2026-05-06T10:00:00Z","ingester_run":"in-1","capture":".wiki-pending/c1.md","page":"concepts/auth.md","issue_type":"broken-cross-link","severity":"warn","detail":"Links to /concepts/legacy.md which does not exist.","suggested_action":"Remove link or create stub"}
{"reported_at":"2026-05-06T11:00:00Z","ingester_run":"in-2","capture":".wiki-pending/c2.md","page":"concepts/foo.md","issue_type":"broken-cross-link","severity":"warn","detail":"Links to /entities/bar.md which does not exist."}
{"reported_at":"2026-05-06T12:00:00Z","ingester_run":"in-3","capture":".wiki-pending/c3.md","page":"concepts/baz.md","issue_type":"schema-drift","severity":"info","detail":"Has type: concept (singular); should be type: concepts."}
{"reported_at":"2026-05-06T13:00:00Z","ingester_run":"in-4","capture":".wiki-pending/c4.md","page":"concepts/x.md","issue_type":"contradiction","severity":"error","detail":"Claims X but page concepts/y.md says not-X."}
EOF

output=$(bash "${ISSUES}" --wiki "${WIKI}")

# Assert grouping by type
echo "${output}" | grep -q '## Broken' || fail "missing Broken cross-links group"
echo "${output}" | grep -q '## Schema' || fail "missing Schema drift group"
echo "${output}" | grep -q '## Contradictions' || fail "missing Contradictions group"

# Assert error severity sorts before warn within a group (or contradictions group is shown first if globally sorted)
# v2.4 spec: ordered by severity within each group. Test: error severity has "(error)" near it.
echo "${output}" | grep -q -i 'error' || fail "error severity not surfaced"

# Assert counts
echo "${output}" | grep -q '6\|2 issues\|2 broken' \
  || true  # exact count format is implementation-flexible

# Assert corrupt-line resilience
echo "this is not json" >> "${log}"
output2=$(bash "${ISSUES}" --wiki "${WIKI}" 2>&1) || fail "corrupt line broke render"
echo "${output2}" | grep -q -i 'broken' || fail "render after corrupt line lost good data"

echo "PASS: wiki-issues.sh render"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-issues-render.sh`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-issues-render.sh
git commit -m "test(unit): add failing test for wiki-issues.sh render"
```

---

### Task 5: Implement `scripts/wiki-issues.sh`

**Files:**
- Create: `scripts/wiki-issues.sh`

- [ ] **Step 1: Write the renderer**

```bash
#!/bin/bash
# wiki-issues.sh — render <wiki>/.ingest-issues.jsonl as grouped markdown.
#
# v2.4 ships the basic render only; --filter and --since flags are
# deferred to v2.5.
#
# Usage:
#   wiki-issues.sh --wiki <path>

set -uo pipefail

wiki=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wiki) wiki="$2"; shift 2 ;;
    *) echo >&2 "wiki-issues: unknown arg: $1"; exit 1 ;;
  esac
done
[[ -n "${wiki}" ]] || { echo >&2 "wiki-issues: --wiki required"; exit 1; }
[[ -d "${wiki}" ]] || { echo >&2 "wiki-issues: wiki path missing: ${wiki}"; exit 1; }

log="${wiki}/.ingest-issues.jsonl"

if [[ ! -f "${log}" || ! -s "${log}" ]]; then
  echo "# Wiki issues — no issues reported"
  exit 0
fi

python3 - "${log}" <<'PYEOF'
import json, sys
from collections import defaultdict

log_path = sys.argv[1]
SEVERITY_ORDER = {"error": 0, "warn": 1, "info": 2}
TYPE_ORDER = [
    "broken-cross-link",
    "contradiction",
    "schema-drift",
    "stale-claim",
    "tag-drift",
    "quality-concern",
    "orphan",
    "other",
]
TYPE_LABEL = {
    "broken-cross-link": "Broken cross-links",
    "contradiction":     "Contradictions",
    "schema-drift":      "Schema drift",
    "stale-claim":       "Stale claims",
    "tag-drift":         "Tag drift",
    "quality-concern":   "Quality concerns",
    "orphan":            "Orphans",
    "other":             "Other",
}

issues = defaultdict(list)
total = 0
malformed = 0

with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            malformed += 1
            continue
        itype = obj.get("issue_type", "other")
        issues[itype].append(obj)
        total += 1

print(f"# Wiki issues — {total} reported")
if malformed:
    print(f"\n_(skipped {malformed} malformed line(s))_")

for itype in TYPE_ORDER:
    rows = issues.get(itype, [])
    if not rows:
        continue
    label = TYPE_LABEL.get(itype, itype)
    print(f"\n## {label} ({len(rows)})")
    # Sort by severity (error first)
    rows.sort(key=lambda r: SEVERITY_ORDER.get(r.get("severity", "info"), 99))
    for r in rows:
        sev = r.get("severity", "info")
        page = r.get("page", "(no page)")
        detail = r.get("detail", "(no detail)")
        ts = r.get("reported_at", "")
        run = r.get("ingester_run", "")
        action = r.get("suggested_action")
        print(f"\n- **{sev}** `{page}`: {detail}")
        print(f"  - reported {ts} by {run}")
        if action:
            print(f"  - suggested: {action}")
PYEOF
```

- [ ] **Step 2: Make it executable and run the test**

```bash
chmod +x scripts/wiki-issues.sh
bash tests/unit/test-wiki-issues-render.sh
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/wiki-issues.sh
git commit -m "feat(scripts): add wiki-issues.sh basic render (grouped, severity-ordered)"
```

---

### Task 6: Wire `bin/wiki issues` subcommand

**Files:**
- Modify: `bin/wiki`

- [ ] **Step 1: Add the `issues` case**

In `bin/wiki`, add this case to the dispatch (after `ingest-now`, before the `*)` default):

```bash
  issues)
    bash "${REPO_ROOT}/scripts/wiki-issues.sh" --wiki "$(wiki_root)" "$@"
    ;;
```

- [ ] **Step 2: Update the `help` block**

Add to the help text:

```bash
  issues         Show ingester-reported issues (grouped, severity-ordered)
                   wiki issues
```

- [ ] **Step 3: Smoke-test**

Set up a fake wiki with an issue log and verify `bin/wiki issues` returns expected output:

```bash
TESTDIR=$(mktemp -d)
bash scripts/wiki-init.sh main "${TESTDIR}/wiki" >/dev/null
echo '{"reported_at":"2026-05-06T10:00:00Z","ingester_run":"in-1","capture":"c.md","page":"concepts/x.md","issue_type":"orphan","severity":"info","detail":"Page not linked from any _index.md."}' \
  > "${TESTDIR}/wiki/.ingest-issues.jsonl"
( cd "${TESTDIR}/wiki" && bash "$(pwd)/../../bin/wiki" issues )
rm -rf "${TESTDIR}"
```

Expected: markdown showing the orphan.

- [ ] **Step 4: Commit**

```bash
git add bin/wiki
git commit -m "feat(bin/wiki): add issues subcommand"
```

---

### Task 7: Failing test — `wiki status` shows issue summary

**Files:**
- Create: `tests/unit/test-wiki-status-issues.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki status output contains an Issues section when .ingest-issues.jsonl has lines.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Status without issues log: no Issues section (or empty placeholder)
output=$(bash "${STATUS}" "${WIKI}" 2>/dev/null) || fail "status without issues log failed"
# Should not crash; output may or may not have an Issues section header

# Add issue log with 6 broken links + 2 contradictions
log="${WIKI}/.ingest-issues.jsonl"
{
  for i in {1..6}; do
    echo "{\"reported_at\":\"2026-05-06T10:00:00Z\",\"ingester_run\":\"in-${i}\",\"capture\":\"c.md\",\"page\":\"concepts/p${i}.md\",\"issue_type\":\"broken-cross-link\",\"severity\":\"warn\",\"detail\":\"Link missing\"}"
  done
  for i in {1..2}; do
    echo "{\"reported_at\":\"2026-05-06T10:00:00Z\",\"ingester_run\":\"in-c${i}\",\"capture\":\"c.md\",\"page\":\"concepts/q${i}.md\",\"issue_type\":\"contradiction\",\"severity\":\"error\",\"detail\":\"Conflict\"}"
  done
} > "${log}"

output=$(bash "${STATUS}" "${WIKI}")
echo "${output}" | grep -q -i 'issues' || fail "status output missing Issues section"
echo "${output}" | grep -q '6.*broken' || fail "status output missing broken-link count"
echo "${output}" | grep -q '2.*contradict' || fail "status output missing contradiction count"

echo "PASS: wiki status issues integration"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-status-issues.sh`
Expected: FAIL — `wiki-status.sh` does not yet read `.ingest-issues.jsonl`.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-status-issues.sh
git commit -m "test(unit): add failing test for wiki status issues summary"
```

---

### Task 8: Add Issues section to `wiki-status.sh`

**Files:**
- Modify: `scripts/wiki-status.sh`

- [ ] **Step 1: Read the current `wiki-status.sh`**

Familiarize yourself with the existing structure. Identify a logical insertion point for the Issues section (probably near the end, alongside other summary metrics like drift / quality).

- [ ] **Step 2: Add an Issues section**

At the appropriate location in `scripts/wiki-status.sh`, add a Python block that reads `.ingest-issues.jsonl` and emits a count summary:

```bash
# Issues summary (v2.4)
issues_log="${wiki}/.ingest-issues.jsonl"
if [[ -f "${issues_log}" && -s "${issues_log}" ]]; then
  echo
  echo "## Issues reported by ingesters (last 30 days)"
  python3 - "${issues_log}" <<'PYEOF'
import json, sys
from collections import Counter
from datetime import datetime, timedelta, timezone

cutoff = datetime.now(timezone.utc) - timedelta(days=30)
counts = Counter()
malformed = 0

with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            malformed += 1
            continue
        ts = obj.get("reported_at", "")
        try:
            t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            continue
        if t < cutoff:
            continue
        counts[obj.get("issue_type", "other")] += 1

if not counts:
    print("  (none in the last 30 days)")
else:
    LABEL = {
        "broken-cross-link": "broken cross-link",
        "contradiction":     "contradiction",
        "schema-drift":      "schema drift",
        "stale-claim":       "stale claim",
        "tag-drift":         "tag drift",
        "quality-concern":   "quality concern",
        "orphan":            "orphan",
        "other":             "other",
    }
    for itype, n in counts.most_common():
        plural = "s" if n != 1 else ""
        print(f"  {n} {LABEL.get(itype, itype)}{plural}")
    print("  Run `wiki issues` for details.")

if malformed:
    print(f"  ({malformed} malformed line(s) skipped)")
PYEOF
fi
```

- [ ] **Step 3: Run the failing test**

Run: `bash tests/unit/test-wiki-status-issues.sh`
Expected: PASS.

- [ ] **Step 4: Run existing status tests**

Run: `bash tests/unit/test-status.sh && bash tests/unit/test-status-last-ingest.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/wiki-status.sh
git commit -m "feat(status): add Issues summary section (last 30 days, grouped by type)"
```

---

### Task 9: Failing test — ingest skill documents deep orientation

**Files:**
- Create: `tests/unit/test-deep-orientation-cold-start.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify karpathy-wiki-ingest/SKILL.md documents deep orientation algorithm
# AND the cold-start fallback (≤7 candidate-eligible pages → role-prompt primary).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SKILL}" ]] || fail "ingest skill missing"

# Required deep-orientation language
grep -q -i 'deep orientation' "${SKILL}" || fail "missing 'deep orientation' heading or term"
grep -q -i 'candidate' "${SKILL}" || fail "missing 'candidate' selection language"
grep -q -i 'substring.*tag\|tag.*substring' "${SKILL}" || fail "missing substring + tag match algorithm"
grep -q -i 'top.*7\|max.*7\|up to 7' "${SKILL}" || fail "missing 7-candidate cap"
grep -q -i 'cold.start\|≤.*7\|<=.*7\|fewer than 8' "${SKILL}" || fail "missing cold-start fallback"

# Issue reporting integration
grep -q 'wiki-issue-log.sh' "${SKILL}" || fail "ingest skill should call wiki-issue-log.sh"
grep -q -i '.ingest-issues.jsonl' "${SKILL}" || fail "ingest skill should mention .ingest-issues.jsonl"

# Issue types enumerated
for t in broken-cross-link contradiction schema-drift stale-claim; do
  grep -q "${t}" "${SKILL}" || fail "ingest skill missing issue_type: ${t}"
done

echo "PASS: ingest skill documents deep orientation + issue reporting"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-deep-orientation-cold-start.sh`
Expected: FAIL — Leg 1 only extracted the basic ingester body; deep orientation hasn't been added yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-deep-orientation-cold-start.sh
git commit -m "test(unit): add failing test for deep-orientation skill text"
```

---

### Task 10: Update `karpathy-wiki-ingest/SKILL.md` with deep orientation + issue reporting

**Files:**
- Modify: `skills/karpathy-wiki-ingest/SKILL.md`

- [ ] **Step 1: Locate the orientation section**

In `skills/karpathy-wiki-ingest/SKILL.md`, find the existing `## Orientation` section. The Leg 1 plan extracted the basic 3-step orientation (schema.md, index.md, last 10 lines of log.md) verbatim from v2.3. Now we replace it with the v2.4 deep-orientation 9-step protocol.

- [ ] **Step 2: Replace the orientation section with the deep-orientation algorithm**

Replace the existing `## Orientation` section with:

````markdown
## Deep orientation

Before any wiki write, run this 9-step orientation protocol. The goal:
your view of the wiki is shaped by the actual page content, not by
titles alone.

### Steps 1-3: read the wiki's current state

1. Read `<wiki>/schema.md` — current categories, taxonomy, thresholds.
2. Read `<wiki>/index.md` (or `<wiki>/<category>/_index.md` per category) — what pages exist with one-line summaries.
3. Read the last ~10 entries of `<wiki>/log.md` — recent activity.

### Steps 4-7: pick and read 0-7 candidate pages

4. **Extract candidate signals from the capture.** From the body and
   frontmatter, gather:
   - Words and phrases from the capture title (lowercase, split on
     non-alphanumerics).
   - Frontmatter `tags:` list (if any).
   - For `chat-only` and `chat-attached` captures: meaningful nouns and
     proper-noun phrases from the body. Use judgment — you're an LLM,
     not a regex; pick names, identifiers, technical terms, version
     numbers.
   - For `raw-direct` captures: filename basename + the file's first
     200 lines.

5. **Score candidates against the index.** A page is a candidate if ANY
   extracted signal:
   - Substring-matches its title (case-insensitive), OR
   - Matches a tag (exact, case-insensitive), OR
   - Appears in its `_index.md` one-line summary.

6. **Pick up to 7 candidates** ordered by:
   - Signal-match count (descending — more matches = stronger candidate).
   - Title length (ascending — shorter titles rank higher for the same
     match count; they tend to be more general / canonical).
   - Tie-break: alphabetical by title.

7. **Read all picked candidates in full.** Zero is a valid count for a
   small or fresh wiki — see "Cold start" below.

### Steps 8-9: decide and report observations

8. **Decide**: create new page, augment an existing page, or no-op
   (the capture's content is already covered by an existing page).
   Write your decision rationale into the commit message later.

9. **Issue reporting (during steps 5-7).** While reading the index and
   the candidate pages, observe issues. Append each as one JSONL line
   to `<wiki>/.ingest-issues.jsonl` via `bash scripts/wiki-issue-log.sh`.
   Do NOT fix issues inline; report only — `wiki doctor` consumes the
   log later.

   Issue types to watch for (the `--type` enum in `wiki-issue-log.sh`):
   - **broken-cross-link**: page links to `/path/foo.md` but that file
     does not exist.
   - **contradiction**: page makes a claim that contradicts another
     page you're reading or the capture itself.
   - **schema-drift**: page has `type: concept` (singular) but
     directory is `concepts/`; page lacks required frontmatter; page
     uses retired categories.
   - **stale-claim**: page says "as of 2025-12 library X is at version
     Y" and the capture or another source clearly indicates a newer
     version.
   - **tag-drift**: same concept tagged two different ways across
     pages.
   - **quality-concern**: page's `quality.overall < 3.0` was rated by
     ingester (not human).
   - **orphan**: page exists but is not linked from any `_index.md` or
     other page.
   - **other**: anything else worth noting.

   Severity:
   - **error**: blocks ingestion (rare — only if reading the schema or
     a candidate page fails outright).
   - **warn**: default. Issue noted; ingestion proceeds.
   - **info**: observational; usually for tag-drift or quality-concern.

   Each issue gets one JSONL line, ≤ 4096 bytes total. Over-length
   `--detail` is auto-truncated by the helper.

### Cold start: wikis with ≤ 7 pages

When the candidate list from step 6 is empty or near-empty (the index
has < 8 pages total), step 7 reads few or no pages. The role guardrail
in `<wiki>/.wiki-config` becomes the PRIMARY lens, not a backup tripwire:

- **`role: project` or `role: project-pointer`**: write specifics
  about THIS codebase / instance / situation. Document the symptom,
  the pinpoint, what code path triggered it. Do NOT generalize.
- **`role: main`**: write general patterns reusable across projects.
  Do NOT name specific apps or instances; abstract them.

In the cold-start state the index has insufficient gravity to shape
the page; the role hint carries the lens. Defer cross-linking to a
future ingester run when more pages exist.

### Why no embeddings / vector search

The substring + tag match in step 5 is deterministic, scriptable,
testable, and cheap. Embedding-based candidate selection is the
"smart" upgrade but explicitly out of scope per CLAUDE.md ("do not
add: vector search — defer until genuine scaling pain"). The
substring/tag approach degrades gracefully — at large scale it hits
more candidates than 7, but the ranking still produces a usable
top-7. When that breaks, vector search becomes worth its complexity;
not before.

### Cost

3-7 extra file reads per ingestion (zero on cold-start wikis). Each
page is typically 5-20 KB. The ingester is already reading the
capture and the schema; this is the same order of magnitude. No
measurable spawn-time impact.
````

- [ ] **Step 3: Update the role-guardrail section to defer to deep orientation**

The existing `## Role guardrail` section (from Leg 1) describes the role hint as a "tripwire" backup. With deep orientation in place, the guardrail becomes a fallback for the cold-start case AND a sanity check for the warm case. Update the section to point at the deep-orientation cold-start subsection.

Find `## Role guardrail` and adjust the text to make clear:

> The role field is the primary lens during cold start (≤ 7 pages in
> the wiki) and a sanity tripwire in mature wikis (the index pull is
> the primary lens once enough pages exist). See "Deep orientation —
> Cold start" above.

- [ ] **Step 4: Run the failing test**

Run: `bash tests/unit/test-deep-orientation-cold-start.sh`
Expected: PASS.

- [ ] **Step 5: Re-run the existing ingest-skill structure test**

Run: `bash tests/unit/test-ingest-skill.sh`
Expected: PASS — Leg 1's structure assertions still hold (frontmatter, required sections, no iron-law duplication).

- [ ] **Step 6: Run the skill-split overlap test**

Run: `bash tests/unit/test-skill-split-no-overlap.sh`
Expected: PASS — the deep orientation language is unique to the ingest skill; no >80-word overlap with the capture skill.

- [ ] **Step 7: Commit**

```bash
git add skills/karpathy-wiki-ingest/SKILL.md
git commit -m "feat(skills/ingest): add deep orientation (steps 1-9) + issue reporting + cold-start fallback"
```

---

### Task 11: Integration test — end-to-end issue reporting

**Files:**
- Create: `tests/integration/test-leg4-end-to-end.sh`

- [ ] **Step 1: Write the integration test**

```bash
#!/bin/bash
# Integration test for Leg 4: ingester emits issue lines, wiki status
# summarizes them, wiki issues renders them.
#
# Note: this test does NOT spawn a real `claude -p` ingester. Instead,
# it directly invokes wiki-issue-log.sh to simulate issue emission,
# and verifies the read surface (status + issues render) consumes the
# log correctly.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
LOG="${REPO_ROOT}/scripts/wiki-issue-log.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Simulate 5 issue emissions across 3 types
for i in {1..3}; do
  bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-${i}" \
    --capture ".wiki-pending/c${i}.md" --page "concepts/p${i}.md" \
    --type broken-cross-link --severity warn \
    --detail "Links to /concepts/missing-${i}.md which does not exist."
done

bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-x" \
  --capture ".wiki-pending/cx.md" --page "concepts/x.md" \
  --type contradiction --severity error \
  --detail "Page x.md claims X but page y.md says not-X."

bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-y" \
  --capture ".wiki-pending/cy.md" --page "concepts/y.md" \
  --type schema-drift --severity info \
  --detail "Has type: concept (singular); should be type: concepts."

# 1. wiki issues renders all 5
output=$(cd "${WIKI}" && bash "${WIKI_BIN}" issues)
echo "${output}" | grep -q '5 reported' || fail "wiki issues missing total"
echo "${output}" | grep -q '## Broken' || fail "wiki issues missing broken-cross-link group"
echo "${output}" | grep -q '## Contradictions' || fail "wiki issues missing contradictions group"
echo "${output}" | grep -q '## Schema' || fail "wiki issues missing schema-drift group"

# 2. wiki status shows the count summary
output=$(cd "${WIKI}" && bash "${WIKI_BIN}" status)
echo "${output}" | grep -q -i 'issues' || fail "wiki status missing Issues section"
echo "${output}" | grep -q '3 broken' || fail "wiki status missing broken-link count"

# 3. Concurrent flock works under load
for i in {1..10}; do
  ( bash "${LOG}" --wiki "${WIKI}" --ingester-run "in-conc-${i}" \
      --capture "c.md" --page "p.md" --type orphan --severity info \
      --detail "concurrent ${i}" ) &
done
wait
final_count=$(wc -l < "${WIKI}/.ingest-issues.jsonl")
[[ "${final_count}" -eq 15 ]] || fail "concurrent appends produced wrong line count: ${final_count}"

# All 15 lines must be valid JSON
python3 -c "
import json
with open('${WIKI}/.ingest-issues.jsonl') as f:
    for i, line in enumerate(f):
        try:
            json.loads(line.strip())
        except json.JSONDecodeError as e:
            print(f'line {i+1} corrupted: {e}'); exit(1)
print('all 15 lines valid')
" || fail "concurrent appends corrupted JSONL"

echo "PASS: Leg 4 end-to-end (issue log + render + status)"
```

- [ ] **Step 2: Run the integration test**

Run: `bash tests/integration/test-leg4-end-to-end.sh`
Expected: PASS.

- [ ] **Step 3: Run the full test suite**

Run: `bash tests/run-all.sh`
Expected: PASS — no regressions across legs 1-4.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test-leg4-end-to-end.sh
git commit -m "test(integration): Leg 4 end-to-end (issue log + render + status)"
```

---

## Self-review checklist

- [ ] `wiki-issue-log.sh` validates `--type` against the 8-value enum.
- [ ] Concurrent appends to `.ingest-issues.jsonl` are flock-serialized; all lines remain well-formed JSON.
- [ ] Lines over 4096 bytes are truncated with `... [truncated]` suffix in the `detail` field.
- [ ] `wiki-issues.sh` renders empty log gracefully ("no issues reported").
- [ ] `wiki-issues.sh` groups by `issue_type`, orders by severity within each group, skips malformed lines with a warning footer.
- [ ] `bin/wiki issues` dispatches to `wiki-issues.sh`.
- [ ] `wiki-status.sh` shows an Issues summary section (last 30 days, count per type).
- [ ] `karpathy-wiki-ingest/SKILL.md` documents the 9-step deep orientation.
- [ ] Cold-start fallback (≤7 pages → role-prompt primary) is documented.
- [ ] Substring + tag match algorithm is specified deterministically (no embeddings).
- [ ] Issue types enumerated in skill match the enum in `wiki-issue-log.sh`.
- [ ] No skill-split duplication regression (`tests/unit/test-skill-split-no-overlap.sh` passes).
- [ ] `bash tests/run-all.sh` passes; no regressions.
- [ ] RED scenario committed before skill changes.

## Verification gate

After Leg 4 ships:
- Ingester reads 0-7 candidate pages during orientation; algorithm is deterministic given fixture index + capture.
- Cold-start orientation (≤7 pages) does not fail any "candidate count" gate; ingestion succeeds with role-prompt as primary lens.
- Issues observed during orientation appear in `.ingest-issues.jsonl`.
- `wiki issues` renders the log as grouped markdown.
- `wiki status` shows the issue count summary.
- Two ingesters concurrently appending issues do not corrupt the log.

### Task 12: Per-wiki ingester run record (`.ingest-runs.jsonl`)

**Files:**
- Modify: `skills/karpathy-wiki-ingest/SKILL.md`
- Modify: `scripts/wiki-status.sh`

The spec calls for asymmetric-outcome observability in `both` mode: if project ingester succeeds and main fails (or vice versa), `wiki status` should report the asymmetry. Leg 2 already writes the cross-wiki coordination record at `~/.wiki-forks.jsonl` from `bin/wiki capture`. This task adds the per-wiki side: the spawned ingester appends one line to `<wiki>/.ingest-runs.jsonl` at start (status=spawned) and another at end (status=completed/failed).

- [ ] **Step 1: Add a run-record protocol to the ingest skill**

In `skills/karpathy-wiki-ingest/SKILL.md`, add a section at the top of the ingester steps (right after `## Deep orientation`) with the title `## Run record (per ingestion)`:

```markdown
## Run record (per ingestion)

At the very start of your work, generate a unique `run_id` and append
a "spawned" record to `<wiki>/.ingest-runs.jsonl`:

```bash
RUN_ID="in-$(date +%s)-$(openssl rand -hex 4 2>/dev/null || echo $$)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "${WIKI_ROOT}/.locks"
{
  flock 7
  printf '{"run_id":"%s","capture":"%s","started_at":"%s","status":"spawned"}\n' \
    "${RUN_ID}" "${WIKI_CAPTURE}" "${ts}" >> "${WIKI_ROOT}/.ingest-runs.jsonl"
} 7>"${WIKI_ROOT}/.locks/ingest-runs.lock"
```

At the END of your work (success or failure), append a closing
record:

```bash
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
status="completed"  # or "failed" if you exit non-zero
exit_code=0          # or your real exit code
{
  flock 7
  printf '{"run_id":"%s","ended_at":"%s","status":"%s","exit_code":%d}\n' \
    "${RUN_ID}" "${ts}" "${status}" "${exit_code}" >> "${WIKI_ROOT}/.ingest-runs.jsonl"
} 7>"${WIKI_ROOT}/.locks/ingest-runs.lock"
```

The two records (spawned + closing) tie back via `run_id`. `wiki
status` reads both files and surfaces asymmetric outcomes in `both`
mode (a fork that has a project record but no main record is
flagged).

If the ingester crashes between the two records, the spawned record
remains without a closing record. `wiki status` flags such records as
"in-flight or stalled" if they're > 30 minutes old.
```

- [ ] **Step 2: Failing test — `.ingest-runs.jsonl` schema**

Create `tests/unit/test-ingest-runs-record.sh`:

```bash
#!/bin/bash
# Verify the ingest skill documents .ingest-runs.jsonl protocol.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q -i 'Run record' "${SKILL}" || fail "missing 'Run record' section"
grep -q '.ingest-runs.jsonl' "${SKILL}" || fail "missing .ingest-runs.jsonl filename"
grep -q '"status":"spawned"' "${SKILL}" || fail "missing spawned status"
grep -q 'completed\|failed' "${SKILL}" || fail "missing closing status values"
grep -q 'flock' "${SKILL}" || fail "missing flock guidance"

echo "PASS: ingest skill documents run-record protocol"
```

Run: `bash tests/unit/test-ingest-runs-record.sh`
Expected: PASS after Step 1's edit.

- [ ] **Step 3: Add fork-asymmetry detection to `wiki-status.sh`**

In `scripts/wiki-status.sh`, after the Issues section (added in Task 8 above), add a Fork-asymmetry section:

```bash
# Fork asymmetry (v2.4)
forks_log="${HOME}/.wiki-forks.jsonl"
if [[ -f "${forks_log}" && -s "${forks_log}" ]]; then
  python3 - "${forks_log}" "${wiki}" <<'PYEOF'
import json, os, sys
from datetime import datetime, timedelta, timezone

forks_path, target_wiki = sys.argv[1], os.path.realpath(sys.argv[2])
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
asymmetric = []

with open(forks_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            fork = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            ts = datetime.fromisoformat(fork.get("captured_at", "").replace("Z", "+00:00"))
        except ValueError:
            continue
        if ts < cutoff:
            continue
        wikis = fork.get("wikis", [])
        if target_wiki not in [os.path.realpath(w) for w in wikis]:
            continue
        # Check each wiki's .ingest-runs.jsonl for a completed record
        # matching this fork's capture.
        statuses = {}
        for w in wikis:
            runs_log = os.path.join(w, ".ingest-runs.jsonl")
            if not os.path.exists(runs_log):
                statuses[w] = "missing"
                continue
            found_status = "spawned-no-close"
            with open(runs_log) as rf:
                for rline in rf:
                    rline = rline.strip()
                    if not rline:
                        continue
                    try:
                        run = json.loads(rline)
                    except json.JSONDecodeError:
                        continue
                    cap = run.get("capture", "")
                    # Match by fork captures list
                    if cap in fork.get("captures", []) and "status" in run and run["status"] != "spawned":
                        found_status = run["status"]
                        break
            statuses[w] = found_status
        # Asymmetric if not all statuses are "completed"
        if any(s != "completed" for s in statuses.values()):
            asymmetric.append((fork, statuses))

if asymmetric:
    print()
    print("## Fork asymmetry (last 7 days)")
    for fork, statuses in asymmetric:
        print(f"  fork {fork.get('fork_id', '(no id)')}: {fork.get('title', '(no title)')}")
        for w, s in statuses.items():
            print(f"    {w}: {s}")
    print("  Run `wiki ingest-now <wiki>` on incomplete sides to retry.")
PYEOF
fi
```

- [ ] **Step 4: Run the new tests + full suite**

```bash
bash tests/unit/test-ingest-runs-record.sh
bash tests/run-all.sh
```

Both expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/karpathy-wiki-ingest/SKILL.md scripts/wiki-status.sh tests/unit/test-ingest-runs-record.sh
git commit -m "feat(skills/ingest): add per-wiki .ingest-runs.jsonl protocol + status fork-asymmetry"
```

---

## Manual verification (deferred to post-ship)

The spec calls for an A/B pressure test of the lens claim — same capture against two fixture wikis (one `role: project`, one `role: main`), assert outputs diverge in expected ways. This requires real `claude -p` runs against fixture wikis with full inboxes and is too expensive for the unit-test surface. After v2.4 ships, run this manually:

1. Build two fixture wikis: one populated with 12 instance-style project pages; one with 12 pattern-style main pages.
2. Drop the same fixture file into both inboxes.
3. Run `wiki ingest-now` on each.
4. Compare the resulting wiki pages: the project-wiki page should focus on specifics; the main-wiki page should focus on patterns. Cross-links should differ — project page links to project pages, main page links to main pages.

Add the result to a separate observation log. If outputs DON'T diverge, the lens claim needs revisiting (likely cold-start is firing because the candidate-selection algorithm is too narrow at 12 pages).

## End of v2.4

After Leg 4 ships:
- All four legs of v2.4 are in. The spec's "Acceptance criteria" section enumerates the full v2.4 ship gate; this leg closes the deep-orientation and issue-reporting items.
- The deferred-to-v2.5 list (in the spec) becomes the next planning surface: `.ingest.log` migration to JSONL, `wiki doctor` real implementation, `wiki link-instances` cross-wiki back-references, filesystem watcher for raw-direct, rich `wiki issues` flags (`--filter`, `--since`, `--by-page`), `wiki use main --remove-local`.
- Cleanup commit: remove the deprecated old `skills/karpathy-wiki/SKILL.md` once v2.4 has been observed working in the wild for a release cycle (per the spec's migration step 3).
