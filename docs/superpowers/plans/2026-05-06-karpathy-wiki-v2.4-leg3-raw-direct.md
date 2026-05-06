# karpathy-wiki v2.4 — Leg 3: Raw-direct ingest via `inbox/`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `<wiki>/inbox/` a first-class drop zone for Web Clipper exports, subagent reports, and manual file drops. Files in `inbox/` get raw-direct ingestion (no fabricated wrapper capture). Add `wiki ingest-now` for on-demand ingestion. Make `raw/` ingester-write-only with atomic write-staging through `.raw-staging/` and a recovery rule that moves accidentally-dropped files in `raw/` back to `inbox/`. Extend SessionStart to scan `inbox/` (in addition to existing `raw/` drift) with deterministic filename + 5-second mtime defer for partial-write safety.

**Architecture:** Inbox is a transient queue; durable state lives in the existing `<wiki>/.manifest.json` (root, not `raw/.manifest.json`). The ingester moves `inbox/<basename>` → `raw/<basename>` as part of the ingest commit. Concurrent SessionStarts deduplicate via deterministic capture filenames (`drift-<sha12(absolute_path)>-<slug>.md`) and atomic `set -C` create. Files modified within the last 5 seconds are deferred (rsync/unzip protection). The legitimate ingester writes to `.raw-staging/<basename>` first, then under `flock` on `.locks/manifest.lock` it atomically renames to `raw/<basename>` and updates the manifest. Recovery acquires the same lock and re-checks manifest membership before classifying a file as "user accident" — eliminating the staging-vs-recovery race.

**Tech Stack:** bash, `flock`, `set -C` for atomic create, `mv` rename for atomic file movement, sha256 (`shasum`) for deterministic naming.

**Spec reference:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/superpowers/specs/2026-05-05-karpathy-wiki-v2.4-executable-protocol-design.md` (Leg 3 — Raw-direct ingest; lines ~720-1100).

**Inter-leg dependency:** Depends on Leg 2 (the no-arg `wiki ingest-now` calls `wiki-resolve.sh`). Reverting requires Leg 3 reverted before Leg 2.

**Verification gate:** After this plan ships:
- A file dropped in `<wiki>/inbox/` is ingested on next SessionStart OR via `wiki ingest-now`. The file is moved to `raw/` and registered in the manifest. `inbox/` is empty after ingest.
- Two SessionStarts firing concurrently against the same `inbox/foo.md` produce exactly one capture (deterministic filename + atomic create).
- A file with mtime within the last 5 seconds is skipped (partial-write safety).
- Subagent-report workflow: `mv <file> <wiki>/inbox/ && wiki ingest-now <wiki>` produces a wiki page without the agent writing a capture body.
- Files dropped accidentally in `raw/` are auto-recovered to `inbox/` (with collision suffix if needed) under the manifest lock; in-flight legitimate ingesters are not disturbed.
- Concurrent ingesters writing distinct raw files do not corrupt the manifest.

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `scripts/wiki-ingest-now.sh` | Create | On-demand drift-scan + drain. Wraps the same logic SessionStart runs. Optional positional path arg. |
| `scripts/wiki-manifest-lock.sh` | Create | flock wrapper around manifest mutations. Used by ingester writes and `raw/` recovery. |
| `scripts/wiki-spawn-ingester.sh` | Modify | Use `.raw-staging/` for atomic raw write; acquire manifest lock; clean up `inbox/` source after commit. |
| `scripts/wiki-manifest.py` | Modify | Add `--lock` flag for in-process lock acquisition; write to `.manifest.json.tmp` and `os.rename` atomically. |
| `scripts/wiki_yaml.py` | Modify | Add `inbox` to `RESERVED` set. (`.raw-staging` is dot-prefixed; existing dot-skip logic in `wiki-relink.py` covers it. Verify wiki_yaml.py's RESERVED set is also dot-aware; if not, add `.raw-staging` explicitly.) |
| `scripts/wiki-relink.py` | Modify (small) | Add `inbox` to its reserved-set tuple at line 80. |
| `hooks/session-start` | Modify | Extend `_drift_scan` to also scan `inbox/`. Add the 5-second mtime defer. Add the `raw/` recovery rule. |
| `tests/unit/test-wiki-ingest-now.sh` | Create | Argument contract: no-arg uses cwd resolver; explicit path bypasses; refuses half-built wiki. |
| `tests/unit/test-wiki-manifest-lock.sh` | Create | Two concurrent manifest writers serialize correctly; final manifest contains both entries. |
| `tests/unit/test-inbox-drift-scan.sh` | Create | File in `inbox/` produces a raw-direct capture; `inbox/` empty after ingest; `raw/` has the file + manifest entry. |
| `tests/unit/test-mtime-defer.sh` | Create | File mtime within 5s is skipped; older files are picked up. |
| `tests/unit/test-raw-recovery.sh` | Create | Unmanifested file in `raw/` → moved to `inbox/` (with collision suffix); ingested; final state correct. |
| `tests/unit/test-raw-staging-no-race.sh` | Create | Concurrent recovery scan + legitimate ingester do not double-queue or corrupt manifest. |
| `tests/unit/test-reserved-set-update.sh` | Create | `wiki_yaml.py` reserved set contains `inbox` and does NOT contain `Clippings`. |
| `tests/integration/test-leg3-end-to-end.sh` | Create | Drop file → next SessionStart → page committed; same via `wiki ingest-now`; subagent-report workflow; binary file fails gracefully. |
| `tests/red/RED-leg3-fabricated-wrapper.md` | Create | RED scenario: subagent-report workflow today forces fabricated capture body, producing low-information wiki pages. |

---

### Task 1: RED scenario — fabricated-wrapper anti-pattern

**Files:**
- Create: `tests/red/RED-leg3-fabricated-wrapper.md`

- [ ] **Step 1: Write the RED scenario**

```markdown
# RED scenario — fabricated wrapper captures around subagent reports

**Date:** 2026-05-06
**Skill change this justifies:** v2.4 Leg 3 — `inbox/` drop zone + `wiki ingest-now` + raw-direct capture path.

## The scenario

A research subagent returns a 4 KB findings file at `/tmp/research-2026-05-06.md`. The findings include detailed claims, citations, version numbers, code snippets — exactly the kind of content the wiki should preserve.

Pre-v2.4 workflow: the main agent must write a `chat-attached` capture body (≥ 1000 bytes) wrapping a pointer to `/tmp/research-2026-05-06.md`. The body says something like:

> The research subagent at /tmp/research-2026-05-06.md returned findings on X. Please read the file and ingest it into the wiki. The findings cover [a brief summary]. The ingester should categorize this as concepts/ and cross-link to [related pages].

This wrapper body is a fabrication: it summarizes what the file already says (the ingester is going to read the file directly anyway). It wastes tokens AND produces a redundant first-pass on the content. The ingester ends up writing a wiki page that is essentially "what the wrapper body said, cleaned up" — much weaker than what it would write reading the report directly with full context.

Symptom: every research-subagent-returns-file event produces a wiki page that is a summary-of-a-summary. The actual rich content in the report is filtered through the wrapper's compression first.

## Why prose alone doesn't fix this

The pre-v2.4 SKILL.md describes "raw-direct ingest" (line 121: *"the user adds a file to raw/"*) but the actual mechanism still requires the agent to write a wrapper capture pointing at the raw. There is no `wiki ingest-now` and no `inbox/` queue that the ingester drains directly. Drift detection only fires when an EXISTING raw file's sha changes — it doesn't pick up new files dropped from outside.

The fix is structural:
- `<wiki>/inbox/` is a queue scanned by SessionStart and `wiki ingest-now`.
- A file in `inbox/` produces an auto-generated raw-direct capture (frontmatter only; body is hook-generated boilerplate). The ingester reads the FILE, not the capture body.
- Subagent-report workflow becomes: `mv /tmp/research-... <wiki>/inbox/ && wiki ingest-now <wiki>`. One command. No body authoring.

## Pass criterion

After Leg 3 ships:
- A subagent file moved into `<wiki>/inbox/` and processed via `wiki ingest-now` produces a wiki page that is a deep ingest of the FILE content, not a re-summary of an agent-written wrapper.
- The capture skill explicitly directs: "Subagent reports: do NOT write a chat-style capture body. Move the file into `<wiki>/inbox/` and run `wiki ingest-now`."
```

- [ ] **Step 2: Commit**

```bash
git add tests/red/RED-leg3-fabricated-wrapper.md
git commit -m "test(red): RED scenario for v2.4 Leg 3 fabricated-wrapper anti-pattern"
```

---

### Task 2: Failing test — reserved-set update

**Files:**
- Create: `tests/unit/test-reserved-set-update.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki_yaml.py and wiki-relink.py reserved sets are updated:
# - inbox is reserved (in both)
# - Clippings is removed (from both)
# - .raw-staging is reserved (in wiki_yaml.py, OR auto-skipped in wiki-relink.py via dot prefix)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
YAML_PY="${REPO_ROOT}/scripts/wiki_yaml.py"
RELINK_PY="${REPO_ROOT}/scripts/wiki-relink.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

# wiki_yaml.py reserved set
grep -q 'RESERVED.*inbox' "${YAML_PY}" || fail "wiki_yaml.py RESERVED missing 'inbox'"
if grep -q 'RESERVED.*Clippings' "${YAML_PY}"; then
  fail "wiki_yaml.py RESERVED still contains 'Clippings'"
fi

# wiki-relink.py reserved tuple
grep -q '"inbox"' "${RELINK_PY}" || fail "wiki-relink.py reserved tuple missing 'inbox'"
if grep -q '"Clippings"' "${RELINK_PY}"; then
  fail "wiki-relink.py reserved tuple still contains 'Clippings'"
fi

# .raw-staging: covered by dot-prefix auto-skip in wiki-relink.py (line 80 already
# uses p.startswith(".") check). Verify that check is still in place.
grep -q 'startswith(".")' "${RELINK_PY}" \
  || fail "wiki-relink.py lost the dot-prefix auto-skip; .raw-staging may surface as a category"

echo "PASS: reserved-set update"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-reserved-set-update.sh`
Expected: FAIL — current files still have `Clippings` and lack `inbox`.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-reserved-set-update.sh
git commit -m "test(unit): add failing test for reserved-set inbox/Clippings update"
```

---

### Task 3: Update reserved sets in `wiki_yaml.py` and `wiki-relink.py`

**Files:**
- Modify: `scripts/wiki_yaml.py`
- Modify: `scripts/wiki-relink.py`

- [ ] **Step 1: Update `wiki_yaml.py`**

Find the `RESERVED` set (line 30):

```python
RESERVED: set[str] = {"raw", "index", "archive", "Clippings"}
```

Replace with:

```python
RESERVED: set[str] = {"raw", "index", "archive", "inbox"}
```

- [ ] **Step 2: Update `wiki-relink.py`**

Find the reserved tuple at line 80:

```python
if any(p in {"raw", "index", "archive", "Clippings"} or p.startswith(".") for p in rel_parts[:-1]):
```

Replace with:

```python
if any(p in {"raw", "index", "archive", "inbox"} or p.startswith(".") for p in rel_parts[:-1]):
```

The `p.startswith(".")` already auto-skips `.raw-staging`, `.wiki-pending`, etc. — no explicit listing needed.

- [ ] **Step 3: Run the failing test**

Run: `bash tests/unit/test-reserved-set-update.sh`
Expected: PASS.

- [ ] **Step 4: Run existing discovery + relink tests**

Run: `bash tests/unit/test-discover.sh && bash tests/unit/test-relink.sh`
Expected: PASS. The existing tests assert `Clippings` is excluded from category discovery and relink walks; with `inbox` in its place AND `Clippings` removed, the existing assertions may need updating. Inspect the test code; if a test asserts `Clippings` is reserved, change it to assert `inbox` is reserved.

- [ ] **Step 5: Commit**

```bash
git add scripts/wiki_yaml.py scripts/wiki-relink.py
# Plus any test updates:
git add tests/unit/test-discover.sh tests/unit/test-relink.sh
git commit -m "feat(reserved): swap Clippings for inbox in reserved sets"
```

---

### Task 4: Failing test — manifest lock serializes concurrent writers

**Files:**
- Create: `tests/unit/test-wiki-manifest-lock.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-manifest-lock.sh serializes two concurrent manifest writers.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCK="${REPO_ROOT}/scripts/wiki-manifest-lock.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${LOCK}" ]] || fail "wiki-manifest-lock.sh missing or not executable"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Write fixture raw files
echo "content A" > "${WIKI}/raw/file-a.md"
echo "content B" > "${WIKI}/raw/file-b.md"

# Run two concurrent register-via-build operations.
# wiki-manifest.py build re-scans raw/ and writes the entire manifest
# wholesale; with the lock, the two runs must serialize.
( bash "${LOCK}" python3 "${REPO_ROOT}/scripts/wiki-manifest.py" build "${WIKI}" ) &
( bash "${LOCK}" python3 "${REPO_ROOT}/scripts/wiki-manifest.py" build "${WIKI}" ) &
wait

# Assert the final manifest is well-formed JSON and contains both files
python3 -c "
import json
with open('${WIKI}/.manifest.json') as f:
    data = json.load(f)
assert 'raw/file-a.md' in data, f'file-a.md missing: {list(data.keys())}'
assert 'raw/file-b.md' in data, f'file-b.md missing: {list(data.keys())}'
print('PASS: both files registered, manifest well-formed')
" || fail "manifest after concurrent writers is corrupted"

echo "PASS: wiki-manifest-lock.sh serializes concurrent writers"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-manifest-lock.sh`
Expected: FAIL — `wiki-manifest-lock.sh` doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-manifest-lock.sh
git commit -m "test(unit): add failing test for manifest lock serialization"
```

---

### Task 5: Implement `scripts/wiki-manifest-lock.sh`

**Files:**
- Create: `scripts/wiki-manifest-lock.sh`

- [ ] **Step 1: Write the lock wrapper**

```bash
#!/bin/bash
# wiki-manifest-lock.sh — flock wrapper for manifest mutations.
#
# Usage: wiki-manifest-lock.sh <command> [args...]
#
# The command's first reference to a wiki must be discoverable so we can
# locate the lock file. Convention: the first arg that looks like a path
# AND contains .wiki-config is treated as the wiki root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

# Find the wiki root by inspecting args for a path containing .wiki-config.
wiki=""
for arg in "$@"; do
  if [[ -d "${arg}" && -f "${arg}/.wiki-config" ]]; then
    wiki="${arg}"
    break
  fi
done

if [[ -z "${wiki}" ]]; then
  echo >&2 "wiki-manifest-lock: cannot locate wiki root in args"
  exit 1
fi

lock_dir="${wiki}/.locks"
mkdir -p "${lock_dir}"
lock_file="${lock_dir}/manifest.lock"

# Acquire exclusive lock (block; default flock timeout = forever, but
# typical mutations finish in < 100 ms).
exec 9>"${lock_file}"
flock 9

# Run the command under the lock.
"$@"
status=$?

# Lock is released automatically when fd 9 closes on script exit.
exit "${status}"
```

- [ ] **Step 2: Make it executable and run the test**

```bash
chmod +x scripts/wiki-manifest-lock.sh
bash tests/unit/test-wiki-manifest-lock.sh
```

Expected: PASS.

If the test fails because `wiki-manifest.py` itself rewrites the file non-atomically, also need to update `wiki-manifest.py`:

- [ ] **Step 3: Update `wiki-manifest.py` for atomic rename**

In `scripts/wiki-manifest.py`, find the function that writes the manifest (likely `build` or a helper). The current pattern is something like:

```python
with open(manifest_path, "w") as f:
    json.dump(data, f, indent=2)
```

Replace with the temp-and-rename pattern:

```python
import os
tmp = manifest_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
os.rename(tmp, manifest_path)
```

`os.rename` is atomic on POSIX when source and destination are on the same filesystem.

- [ ] **Step 4: Re-run the test**

Run: `bash tests/unit/test-wiki-manifest-lock.sh`
Expected: PASS.

- [ ] **Step 5: Run existing manifest tests**

Run: `bash tests/unit/test-manifest.sh && bash tests/unit/test-manifest-validate.sh`
Expected: PASS — no regression.

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-manifest-lock.sh scripts/wiki-manifest.py
git commit -m "feat(scripts): add wiki-manifest-lock.sh + atomic manifest rename"
```

---

### Task 6: Failing test — `inbox/` drift scan creates raw-direct captures

**Files:**
- Create: `tests/unit/test-inbox-drift-scan.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify SessionStart hook scans inbox/ and creates raw-direct captures.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
# Override headless_command to no-op
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

# Drop a file in inbox/ with mtime in the past (so it's not deferred)
echo -e "# Test note\n\nSome content for ingestion." > "${WIKI}/inbox/note.md"
# Make it 10 seconds old so the 5-second mtime defer doesn't apply
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/note.md"

# Run the SessionStart hook with cwd = WIKI
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# Assert a raw-direct capture appeared in .wiki-pending/
ls "${WIKI}/.wiki-pending/" | grep -q '^drift-' \
  || fail "no drift- capture appeared in .wiki-pending/"

# Inspect the capture frontmatter for capture_kind: raw-direct
capture=$(ls "${WIKI}/.wiki-pending/drift-"*.md | head -1)
grep -q 'capture_kind: "raw-direct"' "${capture}" \
  || fail "drift capture missing capture_kind: raw-direct"
grep -q "evidence: \"${WIKI}/inbox/note.md\"" "${capture}" \
  || fail "drift capture evidence path wrong: $(grep '^evidence:' "${capture}")"

echo "PASS: inbox/ drift scan creates raw-direct captures"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-inbox-drift-scan.sh`
Expected: FAIL — current hook does not scan `inbox/`.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-inbox-drift-scan.sh
git commit -m "test(unit): add failing test for inbox/ drift scan"
```

---

### Task 7: Extend SessionStart hook — scan `inbox/`, mtime defer, capture_kind label

**Files:**
- Modify: `hooks/session-start`

- [ ] **Step 1: Refactor `_drift_scan` to share logic across `raw/` and `inbox/`**

Read the current `_drift_scan` function (lines ~40-103 of `hooks/session-start`). It uses `wiki-manifest.py diff` to find new/modified files in `raw/`. Extend it to:

1. Scan `inbox/` for any files (not in manifest comparison; presence alone makes them queue items).
2. For each `inbox/` file with mtime > 5 seconds ago, emit a raw-direct capture with deterministic filename.
3. Continue calling `wiki-manifest.py diff` for `raw/` (existing behavior, unchanged).
4. Add a 5-second mtime defer to BOTH paths (raw/ drift detection + inbox/ scan).

Replace the existing `_drift_scan` function with this expanded version:

```bash
_drift_scan() {
  local now mtime age
  now="$(date +%s)"

  # --- Inbox queue scan (new in v2.4) ---
  if [[ -d "${wiki}/inbox" ]]; then
    local f
    for f in "${wiki}/inbox"/*; do
      [[ -f "${f}" ]] || continue

      mtime="$(stat -f %m "${f}" 2>/dev/null || stat -c %Y "${f}" 2>/dev/null || echo 0)"
      age=$((now - mtime))
      # 5-second mtime defer (rsync/unzip/in-progress copy protection)
      if [[ "${age}" -lt 5 ]]; then
        log_info "session-start: inbox file mtime within last 5s, deferring: $(basename "${f}")"
        continue
      fi

      _emit_raw_direct_capture "${f}"
    done
  fi

  # --- Existing raw/ drift detection ---
  local drift_out
  drift_out="$(python3 "${REPO_ROOT}/scripts/wiki-manifest.py" diff "${wiki}" 2>/dev/null || echo "CLEAN")"
  [[ "${drift_out}" == "CLEAN" ]] && return 0

  log_info "session-start: drift detected"
  local line src
  while IFS= read -r line; do
    case "${line}" in
      NEW:\ *)      src="${line#NEW: }" ;;
      MODIFIED:\ *) src="${line#MODIFIED: }" ;;
      *)            continue ;;
    esac

    # Convert wiki-relative src to absolute
    local abs_src="${wiki}/${src}"

    # 5-second mtime defer
    mtime="$(stat -f %m "${abs_src}" 2>/dev/null || stat -c %Y "${abs_src}" 2>/dev/null || echo 0)"
    age=$((now - mtime))
    if [[ "${age}" -lt 5 ]]; then
      log_info "session-start: raw file mtime within last 5s, deferring: ${src}"
      continue
    fi

    # NEW raw/ files that are not in manifest could be "user accident" —
    # apply the recovery rule: move to inbox/ and re-process via inbox path.
    if [[ "${line}" == NEW:* ]]; then
      _raw_recovery "${abs_src}" "${src}"
      continue
    fi

    # MODIFIED raw/ files use the existing legacy drift capture path
    _emit_legacy_drift_capture "${src}"
  done <<< "${drift_out}"
}

# Helper: emit a raw-direct capture for a file in inbox/ or recovered into inbox/.
_emit_raw_direct_capture() {
  local file_path="$1"
  local basename
  basename="$(basename "${file_path}")"

  # Deterministic capture filename based on absolute path sha
  local src_hash
  src_hash="$(printf '%s' "${file_path}" | shasum | cut -c1-12)"
  local capture_base="drift-${src_hash}-$(slugify "${basename}")"
  local capture_name="${capture_base:0:200}.md"
  local capture_path="${wiki}/.wiki-pending/${capture_name}"

  # Atomic exclusive create
  if ( set -C; : > "${capture_path}" ) 2>/dev/null; then
    cat > "${capture_path}" <<EOF
---
title: "Drop: ${basename}"
evidence: "${file_path}"
evidence_type: "file"
capture_kind: "raw-direct"
suggested_action: "auto"
suggested_pages: []
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
captured_by: "session-start-drop"
propagated_from: null
---

Auto-ingest of file in <inbox|raw>/. The raw file at \`evidence\` is the
canonical source; this body is auto-generated and intentionally
minimal. Action for the ingester: read the raw file, infer category
from content, decide create vs augment, file under appropriate
category. If the raw file looks like an Obsidian Web Clipper export
(has source/created/published frontmatter), preserve those fields.
EOF
    log_info "session-start: raw-direct capture created: ${capture_name}"
  fi
}

# Helper: legacy drift capture for MODIFIED files in raw/ (sha mismatch
# on existing manifest entry — same behavior as v2.x with capture_kind label).
_emit_legacy_drift_capture() {
  local src="$1"
  local src_hash capture_base capture_name capture_path
  src_hash="$(printf '%s' "${src}" | shasum | cut -c1-12)"
  capture_base="drift-${src_hash}-$(slugify "${src}")"
  capture_name="${capture_base:0:200}.md"
  capture_path="${wiki}/.wiki-pending/${capture_name}"
  if ( set -C; : > "${capture_path}" ) 2>/dev/null; then
    cat > "${capture_path}" <<EOF
---
title: "Drift: ${src}"
evidence: "${wiki}/${src}"
evidence_type: "file"
capture_kind: "raw-direct"
suggested_action: "update"
suggested_pages: []
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
captured_by: "session-start-drift"
propagated_from: null
---

Auto-generated drift capture. The raw source file at \`${src}\` has a
sha mismatch against the manifest entry. Re-ingest to bring the wiki
back in sync.
EOF
    log_info "session-start: legacy drift capture created: ${capture_name}"
  fi
}

# Helper: recover an unmanifested file in raw/ by moving it to inbox/.
_raw_recovery() {
  local abs_src="$1"
  local src="$2"
  local basename
  basename="$(basename "${abs_src}")"

  # Acquire manifest lock and re-check membership
  local lock_file="${wiki}/.locks/manifest.lock"
  mkdir -p "${wiki}/.locks"
  exec 8>"${lock_file}"
  flock 8

  # Re-read manifest under the lock — may have been registered while we were
  # acquiring the lock (legitimate ingester finishing).
  if python3 -c "
import json, sys
with open('${wiki}/.manifest.json') as f:
    data = json.load(f)
sys.exit(0 if 'raw/${basename}' in data else 1)
"; then
    # Already in manifest — abort recovery
    flock -u 8
    exec 8>&-
    log_info "session-start: raw/${basename} now in manifest; recovery aborted"
    return 0
  fi

  # Move to inbox with collision suffix if needed
  local target="${wiki}/inbox/${basename}"
  if [[ -e "${target}" ]]; then
    local n=1
    while [[ -e "${wiki}/inbox/${basename%.*}.${n}.${basename##*.}" ]]; do
      n=$((n + 1))
    done
    target="${wiki}/inbox/${basename%.*}.${n}.${basename##*.}"
  fi

  mv "${abs_src}" "${target}"
  log_warn "session-start: raw-recovery | unmanifested file moved raw/ → inbox/: ${basename}"

  flock -u 8
  exec 8>&-

  # Now emit raw-direct capture for the recovered file
  _emit_raw_direct_capture "${target}"
}
```

- [ ] **Step 2: Run the failing test from Task 6**

Run: `bash tests/unit/test-inbox-drift-scan.sh`
Expected: PASS.

- [ ] **Step 3: Run existing SessionStart tests**

Run: `bash tests/integration/test-session-start.sh && bash tests/integration/test-concurrent-ingest.sh`
Expected: PASS — no regression.

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start
git commit -m "feat(hooks): SessionStart scans inbox/ + raw-direct capture + 5s mtime defer + raw-recovery"
```

---

### Task 8: Failing test — 5-second mtime defer

**Files:**
- Create: `tests/unit/test-mtime-defer.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify the 5-second mtime defer protects against partial writes.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

# Drop a file with mtime = NOW (within 5s)
echo "fresh content" > "${WIKI}/inbox/fresh.md"
touch "${WIKI}/inbox/fresh.md"

# Run hook — should defer
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# No capture should appear yet
if ls "${WIKI}/.wiki-pending/drift-"*.md >/dev/null 2>&1; then
  fail "fresh-mtime file was not deferred"
fi

# Wait > 5 seconds and re-run
sleep 6
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# Now a capture SHOULD appear
ls "${WIKI}/.wiki-pending/drift-"*.md >/dev/null 2>&1 \
  || fail "after 6s wait, drift capture should appear"

echo "PASS: 5-second mtime defer"
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/unit/test-mtime-defer.sh`
Expected: PASS (Task 7 already implemented the defer).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-mtime-defer.sh
git commit -m "test(unit): verify 5-second mtime defer for inbox/ scans"
```

---

### Task 9: Failing test — `raw/` recovery

**Files:**
- Create: `tests/unit/test-raw-recovery.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify raw/ recovery: an unmanifested file in raw/ is moved to inbox/
# and processed via the standard queue.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

# Drop a file directly in raw/ (simulating user accident)
echo "user accidentally dropped this here" > "${WIKI}/raw/accident.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/accident.md"

# Verify file is NOT in manifest (it was created outside the ingester)
python3 -c "
import json
with open('${WIKI}/.manifest.json') as f:
    data = json.load(f)
assert 'raw/accident.md' not in data, 'precondition failed: accident.md is already in manifest'
"

# Run hook — should recover
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# After recovery, accident.md should be in inbox/, not raw/
[[ -f "${WIKI}/inbox/accident.md" ]] || fail "raw recovery did not move file to inbox/"
[[ ! -f "${WIKI}/raw/accident.md" ]] || fail "raw recovery left file in raw/"

# A drift capture should exist for the inbox/ file
ls "${WIKI}/.wiki-pending/drift-"*.md >/dev/null 2>&1 \
  || fail "raw recovery did not produce drift capture"

# .ingest.log should have a WARN line
grep -q 'raw-recovery' "${WIKI}/.ingest.log" \
  || fail ".ingest.log missing raw-recovery WARN"

# Collision case: drop another file with the same basename in raw/, and one
# already in inbox/ from the prior recovery.
echo "second collision" > "${WIKI}/raw/accident.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/accident.md"
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true
[[ -f "${WIKI}/inbox/accident.1.md" ]] || fail "collision-suffix accident.1.md missing"

echo "PASS: raw/ recovery"
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/unit/test-raw-recovery.sh`
Expected: PASS (Task 7's `_raw_recovery` should handle both the basic and collision cases).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-raw-recovery.sh
git commit -m "test(unit): verify raw/ recovery (move to inbox + collision suffix)"
```

---

### Task 10: Failing test — concurrent recovery + ingester race

**Files:**
- Create: `tests/unit/test-raw-staging-no-race.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify the recovery scan and a legitimate in-flight ingester do not
# race. The ingester writes to .raw-staging/ first, atomic-renames into
# raw/ under the manifest lock; recovery acquires the same lock and
# re-checks membership, so it never picks up an in-flight file.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Simulate an in-flight legitimate ingester: a file in .raw-staging/.
echo "in flight" > "${WIKI}/.raw-staging/inflight.md"
touch -t "$(date -v-30S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '30 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/.raw-staging/inflight.md"

# Drop an unrelated unmanifested file in raw/ — recovery should pick this up.
echo "user dropped this" > "${WIKI}/raw/dropped.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/dropped.md"

# Run hook
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# .raw-staging/inflight.md must be untouched (recovery skips reserved dirs)
[[ -f "${WIKI}/.raw-staging/inflight.md" ]] || fail "recovery touched .raw-staging/ (must be reserved)"

# dropped.md should be moved to inbox/
[[ -f "${WIKI}/inbox/dropped.md" ]] || fail "raw recovery did not move dropped.md"

echo "PASS: raw-staging skipped by recovery (no race)"
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/unit/test-raw-staging-no-race.sh`
Expected: PASS — the recovery scan iterates over `raw/*` (a glob that doesn't match `.raw-staging/`), so the in-flight file is naturally excluded.

If the test fails (some implementation issue), inspect the recovery loop to confirm it iterates `${wiki}/raw/*` (no recursion into hidden dirs) and that `wiki-manifest.py diff` does not surface `.raw-staging/` files.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-raw-staging-no-race.sh
git commit -m "test(unit): verify .raw-staging/ is skipped by recovery scan"
```

---

### Task 11: Update `wiki-spawn-ingester.sh` for write-staging discipline

**Files:**
- Modify: `scripts/wiki-spawn-ingester.sh`

- [ ] **Step 1: Read the current spawner**

Read `scripts/wiki-spawn-ingester.sh` end-to-end. The current flow:

1. Claim the capture (rename `.md` → `.md.processing`).
2. Read `headless_command` from `.wiki-config`.
3. Build the ingest prompt.
4. Spawn `claude -p` detached.

The ingester itself (the spawned `claude -p`) is what writes to `raw/`. Updating the *spawner* to enforce raw-staging is the wrong layer; the right layer is the **ingester's** behavior, which lives in `karpathy-wiki-ingest/SKILL.md`.

For Leg 3, the ingest skill must instruct the spawned ingester to use `.raw-staging/` for atomic raw writes. The Leg 1 plan extracted the existing ingester body from `karpathy-wiki/SKILL.md` lines 275-470 verbatim. Now Leg 3 modifies that body to add raw-staging.

- [ ] **Step 2: Update `karpathy-wiki-ingest/SKILL.md` to use `.raw-staging/`**

Open `skills/karpathy-wiki-ingest/SKILL.md` (created in Leg 1). Find step 4 ("Copy evidence, write manifest entry with correct origin"). The current text says:

> If `evidence_type` is `file` or `mixed`: `cp` the evidence file to `<wiki>/raw/<basename>` preserving basename.

Replace with:

```markdown
**Step 4 — Copy evidence with write-staging discipline (v2.4):**

Atomic write to `raw/` requires the staging dance:

1. Copy the evidence file to `<wiki>/.raw-staging/<basename>` (NOT directly to `raw/`).
2. Compute the new sha256.
3. Acquire `<wiki>/.locks/manifest.lock` via `flock` (use `bash scripts/wiki-manifest-lock.sh ...` for the surrounding work).
4. Re-read the manifest under the lock. If `raw/<basename>` already exists with the same sha256, this is a duplicate — skip (apply the sha256 short-circuit below).
5. Update the manifest entry for `raw/<basename>` (origin, sha, copied_at, last_ingested, referenced_by).
6. Write the manifest atomically (`.manifest.json.tmp` + `os.rename`).
7. Atomically rename `<wiki>/.raw-staging/<basename>` → `<wiki>/raw/<basename>` (POSIX rename is atomic on the same filesystem).
8. Release the lock.
9. If the source file is in `<wiki>/inbox/<basename>` (raw-direct via inbox queue), `rm` it.

Crash recovery: if the ingester crashes between steps 1 and 7, a file lingers in `.raw-staging/`. The SessionStart recovery scan SKIPS `.raw-staging/` (it's a reserved dot-prefixed directory). Future cleanup is `wiki doctor`'s responsibility.

If `evidence_type` is `conversation` AND the capture has no real path, there is no file to stage; skip steps 1-2 and 7. The manifest entry's `origin` is the literal string `"conversation"`.
```

- [ ] **Step 3: Run the existing ingester tests + Leg 1's skill tests**

Run: `bash tests/unit/test-spawn-ingester.sh && bash tests/unit/test-ingest-skill.sh`
Expected: PASS — the spawner test doesn't run the actual ingester; the ingest-skill test only checks for required sections.

- [ ] **Step 4: Commit**

```bash
git add skills/karpathy-wiki-ingest/SKILL.md
git commit -m "feat(skills/ingest): document raw-staging write discipline + manifest lock"
```

---

### Task 12: Failing test — `wiki-ingest-now` argument contract

**Files:**
- Create: `tests/unit/test-wiki-ingest-now.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-ingest-now CLI argument contract.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INGEST_NOW="${REPO_ROOT}/scripts/wiki-ingest-now.sh"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${INGEST_NOW}" ]] || fail "wiki-ingest-now.sh missing"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${WIKI}" > "${WIKI_POINTER_FILE}"
export CLAUDE_HEADLESS=1

# Case 1: explicit path bypasses resolver
echo "explicit content" > "${WIKI}/inbox/explicit.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/explicit.md"
bash "${WIKI_BIN}" ingest-now "${WIKI}" >/dev/null \
  || fail "wiki ingest-now <path> failed"
ls "${WIKI}/.wiki-pending/drift-"*.md >/dev/null 2>&1 \
  || fail "explicit-path ingest-now did not produce drift capture"

# Case 2: no-arg uses cwd-resolved wiki
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
echo "main-only" > "${PROJ}/.wiki-mode"
echo "noarg content" > "${WIKI}/inbox/noarg.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/noarg.md"
( cd "${PROJ}" && bash "${WIKI_BIN}" ingest-now ) >/dev/null \
  || fail "wiki ingest-now (no arg) failed"
# .wiki-mode = main-only resolves to WIKI; noarg.md should produce a drift capture
ls "${WIKI}/.wiki-pending/" | grep noarg >/dev/null \
  || fail "no-arg ingest-now did not pick up noarg.md from cwd-resolved wiki"

# Case 3: explicit path to half-built wiki → exit non-zero
HALF="${TESTDIR}/half"
mkdir -p "${HALF}/.wiki-pending"
echo 'role = "main"' > "${HALF}/.wiki-config"
# schema.md and index.md missing
bash "${WIKI_BIN}" ingest-now "${HALF}" 2>/dev/null \
  && fail "ingest-now on half-built wiki should exit non-zero"

# Case 4: headless + resolver error (cwd unconfigured + pointer = none) → exit non-zero, no orphan
echo "none" > "${WIKI_POINTER_FILE}"
SCRATCH="${TESTDIR}/scratch"
mkdir -p "${SCRATCH}"
( cd "${SCRATCH}" && bash "${WIKI_BIN}" ingest-now ) 2>/dev/null \
  && fail "ingest-now headless + unconfigured + pointer=none should exit non-zero"

echo "PASS: wiki ingest-now argument contract"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-ingest-now.sh`
Expected: FAIL — `wiki-ingest-now.sh` doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-ingest-now.sh
git commit -m "test(unit): add failing test for wiki ingest-now argument contract"
```

---

### Task 13: Implement `scripts/wiki-ingest-now.sh`

**Files:**
- Create: `scripts/wiki-ingest-now.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# wiki-ingest-now.sh — on-demand drift-scan + drain.
#
# Usage:
#   wiki-ingest-now.sh                — uses cwd-resolved wiki(s)
#   wiki-ingest-now.sh <wiki-path>    — operates on the explicit path,
#                                       no resolver, no prompting

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

ingest_one_wiki() {
  local wiki="$1"
  [[ -d "${wiki}" ]] || { echo >&2 "wiki ingest-now: wiki path does not exist: ${wiki}"; return 1; }
  [[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "wiki ingest-now: not a wiki (no .wiki-config): ${wiki}"; return 1; }

  # Verify structure
  for required in schema.md index.md .wiki-pending; do
    if [[ ! -e "${wiki}/${required}" ]]; then
      echo >&2 "wiki ingest-now: half-built wiki — missing ${required} at ${wiki}"
      return 1
    fi
  done

  # Run the same drift-scan + drain logic as SessionStart, but inline.
  # Since the SessionStart hook is a single script, we invoke it with
  # cwd set to the wiki AND override env vars to make it scan THIS wiki.
  # The hook keeps walk-up via wiki_root_from_cwd, which from inside the
  # wiki dir will find the wiki itself.
  ( cd "${wiki}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${REPO_ROOT}/hooks/session-start" >/dev/null 2>&1 )
}

if [[ $# -eq 0 ]]; then
  # No-arg: use cwd resolver
  resolver_out="$(bash "${SCRIPT_DIR}/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0 || resolver_exit=$?

  if [[ "${resolver_exit}" != 0 ]]; then
    echo >&2 "wiki ingest-now: resolver exit ${resolver_exit}; cannot determine target wiki(s)."
    case "${resolver_exit}" in
      10) echo >&2 "  pointer missing — run 'wiki init-main' first" ;;
      11) echo >&2 "  cwd unconfigured — run 'wiki use project|main|both' first" ;;
      12) echo >&2 "  cwd requires a main wiki but pointer is none/missing" ;;
      13) echo >&2 "  cwd has both .wiki-config and .wiki-mode (conflict); rm one" ;;
      14) echo >&2 "  half-built wiki at cwd or pointer target" ;;
    esac
    exit 1
  fi

  while IFS= read -r wiki_path; do
    [[ -n "${wiki_path}" ]] || continue
    ingest_one_wiki "${wiki_path}" || exit 1
  done <<< "${resolver_out}"
else
  # Explicit path — no resolver, no prompting
  ingest_one_wiki "$1" || exit 1
fi

exit 0
```

- [ ] **Step 2: Make it executable and run the test**

```bash
chmod +x scripts/wiki-ingest-now.sh
bash tests/unit/test-wiki-ingest-now.sh
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/wiki-ingest-now.sh
git commit -m "feat(scripts): add wiki-ingest-now.sh on-demand drift+drain"
```

---

### Task 14: Update `karpathy-wiki-capture/SKILL.md` for subagent-report workflow

**Files:**
- Modify: `skills/karpathy-wiki-capture/SKILL.md`

The Leg 1 plan included a subagent-report section in the capture skill. Verify it's there and points at `wiki ingest-now`. If the implementer of Leg 1 wrote a stub, this is the moment to ensure it's accurate.

- [ ] **Step 1: Verify the subagent-report section exists**

Run: `grep -A 8 'Subagent reports' skills/karpathy-wiki-capture/SKILL.md`
Expected: lines covering the `mv ... <wiki>/inbox/ && wiki ingest-now <wiki>` workflow.

If the section is missing or weak, add it. The text:

```markdown
## Subagent reports — DO NOT write a capture body

When a research subagent returns a file with durable findings, the
report IS the capture. Move the file to `<wiki>/inbox/`:

```bash
mv <subagent-report-path> <wiki>/inbox/<basename>
wiki ingest-now <wiki>          # or wait for next SessionStart
```

`wiki ingest-now` triggers the same drift-scan + drain that
SessionStart runs, but on demand. Use this when the user is still in
the active session and wants the report ingested before they close
the terminal.

Subagent-report bodies frequently exceed several KB; rewriting them
as a `chat-only` capture body wastes tokens AND produces an inferior
wiki page (the body summarizes what the file already says).
```

- [ ] **Step 2: Commit (if any change made)**

```bash
git add skills/karpathy-wiki-capture/SKILL.md
git commit -m "docs(skills/capture): tighten subagent-report workflow guidance"
```

---

### Task 15: Integration test — Leg 3 end-to-end

**Files:**
- Create: `tests/integration/test-leg3-end-to-end.sh`

- [ ] **Step 1: Write the integration test**

```bash
#!/bin/bash
# Integration test for Leg 3: drop file → SessionStart OR wiki ingest-now → page committed.
# Subagent-report workflow + binary-file failure mode.
#
# Note: this test does NOT spawn a real `claude -p` ingester (that
# requires API keys + wall-clock time). It verifies the spawner is
# called, drift captures appear, and inbox/ is correctly drained
# downstream of the hook. Real ingester behavior is covered by
# tests/integration/test-end-to-end-plumbing.sh.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
# Mock the ingester to a no-op for testing
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${WIKI}" > "${WIKI_POINTER_FILE}"

# 1. Drop file → SessionStart → drift capture
echo "real content" > "${WIKI}/inbox/dropped.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/dropped.md"
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true
ls "${WIKI}/.wiki-pending/drift-"*.md >/dev/null 2>&1 \
  || fail "SessionStart did not produce drift capture"

# Cleanup for next case
rm -f "${WIKI}/.wiki-pending/drift-"*.md
rm -f "${WIKI}/inbox/"*

# 2. wiki ingest-now <path>
echo "explicit content" > "${WIKI}/inbox/explicit.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/explicit.md"
bash "${WIKI_BIN}" ingest-now "${WIKI}" >/dev/null \
  || fail "wiki ingest-now <path> failed"
ls "${WIKI}/.wiki-pending/drift-"*.md >/dev/null 2>&1 \
  || fail "wiki ingest-now did not produce drift capture"

# 3. Subagent-report workflow simulation
rm -f "${WIKI}/.wiki-pending/drift-"*.md
rm -f "${WIKI}/inbox/"*

REPORT="${TESTDIR}/subagent-report.md"
cat > "${REPORT}" <<EOF
# Research findings

This is a 4 KB+ subagent report with detailed claims, citations, and
durable knowledge that should NOT be rewritten as a capture body.

$(yes "Some content here." | head -c 4000)
EOF

mv "${REPORT}" "${WIKI}/inbox/"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/$(basename "${REPORT}")"
bash "${WIKI_BIN}" ingest-now "${WIKI}" >/dev/null \
  || fail "subagent-report ingest-now failed"
ls "${WIKI}/.wiki-pending/drift-"*.md >/dev/null 2>&1 \
  || fail "subagent-report did not produce drift capture"

# Verify the capture's evidence path points at the moved file
capture=$(ls "${WIKI}/.wiki-pending/drift-"*.md | head -1)
grep -q "evidence: \"${WIKI}/inbox/$(basename "${REPORT}")\"" "${capture}" \
  || fail "subagent-report capture has wrong evidence path"

echo "PASS: Leg 3 end-to-end (inbox drop, ingest-now, subagent workflow)"
```

- [ ] **Step 2: Run the integration test**

Run: `bash tests/integration/test-leg3-end-to-end.sh`
Expected: PASS.

- [ ] **Step 3: Run the full test suite**

Run: `bash tests/run-all.sh`
Expected: PASS — no regressions.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test-leg3-end-to-end.sh
git commit -m "test(integration): Leg 3 end-to-end (inbox + ingest-now + subagent-report)"
```

---

## Self-review checklist

- [ ] `inbox/` and `.raw-staging/` directories are created by `wiki-init.sh` (Leg 2 task 4).
- [ ] Reserved sets in `wiki_yaml.py` and `wiki-relink.py` contain `inbox`, do NOT contain `Clippings`.
- [ ] SessionStart hook scans `inbox/` AND `raw/`; defers files with mtime < 5s; recovers unmanifested files in `raw/` to `inbox/` (with collision suffix) under the manifest lock.
- [ ] `wiki-manifest-lock.sh` serializes concurrent manifest mutations.
- [ ] `wiki-manifest.py` writes manifest atomically (`.tmp` + `os.rename`).
- [ ] `karpathy-wiki-ingest/SKILL.md` documents the `.raw-staging/` write-staging discipline (atomic rename + lock + re-check).
- [ ] `wiki-ingest-now.sh` accepts no-arg (cwd resolution) AND explicit path (bypass).
- [ ] `bin/wiki ingest-now` dispatches to `wiki-ingest-now.sh`.
- [ ] `karpathy-wiki-capture/SKILL.md` directs subagent-report workflow to `mv` + `wiki ingest-now`.
- [ ] `bash tests/run-all.sh` passes.
- [ ] RED scenario committed before code changes.

## Verification gate

After Leg 3 ships:
- File in `inbox/` becomes a wiki page after SessionStart OR `wiki ingest-now`. File ends up in `raw/` with manifest entry; `inbox/` empty.
- Two SessionStarts on the same `inbox/foo.md` produce exactly one capture.
- `inbox/foo.md` with mtime now is deferred until 5+ seconds pass.
- `raw/accident.md` (unmanifested) is recovered to `inbox/`; processed normally.
- Concurrent recovery scan + in-flight ingester do not race (recovery acquires manifest lock + skips `.raw-staging/`).
- Two ingesters writing distinct raw files do not corrupt the manifest.

## Next leg

Leg 4 plan: `docs/superpowers/plans/2026-05-06-karpathy-wiki-v2.4-leg4-deep-orientation-issues.md` — adds deep orientation to the ingest skill (read 0-7 candidate pages before deciding) AND issue reporting (`.ingest-issues.jsonl` + `wiki issues` render). Does not depend on Leg 3 mechanically; modifies the ingest skill body and adds a new CLI subcommand.
