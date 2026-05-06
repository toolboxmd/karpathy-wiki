# karpathy-wiki v2.4 — Leg 2: Project-wiki resolver + `bin/wiki capture` CLI + `wiki use`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the implicit, prose-only wiki resolution with three explicit pieces: (1) a non-interactive `wiki-resolve.sh` that returns target wikis on stdout or exits with one of five specific codes signaling user input is needed; (2) a `bin/wiki capture` subcommand that is the canonical entry point for all chat-driven captures (handles prompts, headless fallback, fork emission, ingester spawn); (3) a `wiki use project|main|both` CLI that persists the per-cwd choice into `.wiki-config` (project mode + optional `fork_to_main`) or `.wiki-mode` (main-only).

**Architecture:** The marker layout uses `<cwd>/.wiki-config` as the single canonical detection path. Project mode writes a small "project-pointer" config (`role = "project-pointer"`, `wiki = "./wiki"`, `fork_to_main = false|true`) at cwd; the actual wiki lives at `<cwd>/wiki/`. `.wiki-mode` is reserved for the main-only case (single value: `main-only`). Forking is encoded as `fork_to_main = true` on `.wiki-config`, NOT as a `.wiki-mode = both` value (the latter was structurally impossible to reconcile with project-pointer resolution). The resolver is cwd-only (no walk-up); the SessionStart hook keeps walk-up via `wiki_root_from_cwd` for itself (see Leg 1). `~/.wiki-pointer` carries the path to the user's main wiki, or the literal `none` for project-only users.

**Tech Stack:** bash scripts, TOML-ish `.wiki-config` (existing format from `wiki-init.sh`), POSIX exit codes, flock for concurrency.

**Spec reference:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/superpowers/specs/2026-05-05-karpathy-wiki-v2.4-executable-protocol-design.md` (Leg 2 — Project-wiki resolver; lines ~217-720).

**Inter-leg dependency:** Depends on Leg 1's loader being shipped (the loader instructs the agent to invoke `bin/wiki capture` and `wiki use`). Leg 3 depends on this leg (Leg 3's `wiki ingest-now` calls the same `wiki-resolve.sh`).

**Verification gate:** After this plan ships:
- `bin/wiki capture` exists and is the only path the loader skill instructs the agent to use for chat-driven captures.
- `wiki-resolve.sh` exits 0/10/11/12/13/14 according to the spec's pseudocode.
- `wiki use project|main|both` is idempotent and refuses invalid combinations.
- `wiki-init-main.sh` bootstraps `~/.wiki-pointer` (silent migration if a unique main wiki exists at depth ≤ 2 in `$HOME`; else interactive prompt).
- Headless contexts fall back per the spec's headless-fallback rules; never silently set pointer to `none`; never lose a body (orphan-preserve at `~/.wiki-orphans/`).
- Standalone project mode (no main): `wiki-init.sh project <path>` works without the third argument.

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `scripts/wiki-resolve.sh` | Create | Non-interactive resolver. Returns target wikis on stdout, OR exits 10-14. |
| `scripts/wiki-init-main.sh` | Create | Interactive bootstrap of `~/.wiki-pointer`. Silent migration when a unique main wiki exists; else prompt. |
| `scripts/wiki-use.sh` | Create | Persist `wiki use project|main|both` choice. Idempotent. |
| `scripts/wiki-orphan.sh` | Create | Helper used by `bin/wiki capture` to preserve a body at `~/.wiki-orphans/<timestamp>-<slug>.md` when capture must abort. |
| `bin/wiki` | Modify | Add `capture`, `ingest-now` (placeholder), `use`, `init-main` subcommands to the dispatch. |
| `scripts/wiki-init.sh` | Modify | Allow project mode without a `<main_path>` arg (standalone project). Make script re-runnable on existing wikis (idempotent: skip artifacts if present). Create `inbox/` and `.raw-staging/` directories (used by Leg 3). Write the wiki-root README on init. |
| `scripts/wiki-config-read.py` | Modify (likely) | Add a `--key fork_to_main` reader if the existing reader doesn't already cover dotted-or-flat keys. |
| `tests/unit/test-wiki-resolve.sh` | Create | Exit-code matrix: every combination of pointer state × cwd state. ≥ 14 cases. |
| `tests/unit/test-wiki-init-main.sh` | Create | Bootstrap fresh state, single-candidate silent migration, multi-candidate interactive prompt, "none" path, pointer-already-exists no-op. |
| `tests/unit/test-wiki-use.sh` | Create | Three subcommands × idempotency × refusal cases. |
| `tests/unit/test-wiki-init-standalone-project.sh` | Create | `wiki-init.sh project <path>` (no main arg) creates a usable project wiki. |
| `tests/unit/test-wiki-init-rerun-idempotent.sh` | Create | Re-running `wiki-init.sh` on an existing wiki is a no-op for existing files; creates only what's missing. |
| `tests/unit/test-wiki-capture-cli.sh` | Create | `bin/wiki capture` body-input contract (stdin / `--body-file`), max-body, prompt-channel separation, headless fallback exit codes. |
| `tests/integration/test-leg2-end-to-end.sh` | Create | Three modes (project / main / both) end-to-end with simulated user input + headless fallback. |
| `tests/red/RED-leg2-resolver-prose.md` | Create | RED scenario: capture writes default to `$HOME/wiki/` regardless of cwd because the prose-only resolution is not enforced anywhere. |

---

### Task 1: RED scenario — captures default to `$HOME/wiki/` because resolution is prose

**Files:**
- Create: `tests/red/RED-leg2-resolver-prose.md`

- [ ] **Step 1: Write the RED scenario**

```markdown
# RED scenario — captures default to $HOME/wiki/ because resolver lives in prose

**Date:** 2026-05-06
**Skill change this justifies:** v2.4 Leg 2 — `bin/wiki capture` is the single capture entry point; `wiki-resolve.sh` enforces the project-wiki branching the v2.x SKILL.md prose only describes.

## The scenario

User runs the agent in `~/dev/myapp/` (a git repo with no wiki).
A trigger fires: research subagent returns a 4 KB findings file.
Agent writes a capture body and runs `bash scripts/wiki-spawn-ingester.sh` directly (per pre-v2.4 SKILL.md prose).
`wiki_root_from_cwd` walks up looking for `.wiki-config`. It does not find one in `~/dev/myapp/` or `~/dev/`. It walks to `~/`, where there is no `.wiki-config`. But there IS one at `~/wiki/.wiki-config` — the v2.x lib had a sibling-check that matched this. Result: capture lands in `~/wiki/.wiki-pending/`.

The user expected the capture to land in either:
- A new project wiki at `~/dev/myapp/wiki/`, or
- The main wiki, with a clear "this is general-knowledge" framing,

depending on a one-time per-cwd decision. The spec describes this branching in prose (3-case algorithm) but no script enforces it. Every project session this user has ever run captured to `~/wiki/`.

## Why prose alone doesn't fix this

The current `skills/karpathy-wiki/SKILL.md` lines 74-93 describe the auto-init algorithm:
> 1. If cwd (or a parent) has a `.wiki-config` → use that wiki.
> 2. Otherwise, if `$HOME/wiki/.wiki-config` exists → cwd is outside a wiki; create a project wiki at `./wiki/` linked to `$HOME/wiki/`.
> 3. Otherwise → create the main wiki at `$HOME/wiki/`.

Steps 2 and 3 describe wiki creation that no script automates. The agent doesn't run this branching at every capture; it relies on `wiki_root_from_cwd` (walk-up). The walk-up's sibling-match silently selects `~/wiki/` whenever cwd is anywhere under `$HOME`.

The fix is structural:
- Add `bin/wiki capture` as the canonical entry point. Loader instructs agents to use it.
- `bin/wiki capture` calls `wiki-resolve.sh` (cwd-only; no walk-up).
- If `wiki-resolve.sh` exits 11 (cwd unconfigured), the wrapper prompts the user once, persists the choice in `.wiki-config` (project + optional `fork_to_main`) or `.wiki-mode` (main-only).
- Future sessions read the persisted choice; no re-prompt.

## Pass criterion

After Leg 2 ships:
- `bin/wiki capture --kind chat-only --title T <<< "$BODY"` in `~/dev/myapp/` (no `.wiki-config`, pointer valid) prompts the user for project / main / both. The chosen mode is persisted. Subsequent captures in the same cwd do NOT re-prompt.
- The walk-up sibling-match bug cannot fire from `bin/wiki capture` because the resolver is cwd-only.
```

- [ ] **Step 2: Commit**

```bash
git add tests/red/RED-leg2-resolver-prose.md
git commit -m "test(red): RED scenario for v2.4 Leg 2 resolver enforcement"
```

---

### Task 2: Failing test — `wiki-init.sh` accepts standalone project (no main arg)

**Files:**
- Create: `tests/unit/test-wiki-init-standalone-project.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-init.sh project <path> works without a main_path argument.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# Standalone project mode: no third argument
bash "${INIT}" project "${TESTDIR}/wiki" >/dev/null \
  || fail "wiki-init.sh project <path> (no main) must succeed"

# Verify config has role = "project" and NO main field
config="${TESTDIR}/wiki/.wiki-config"
[[ -f "${config}" ]] || fail "no .wiki-config written"
grep -q '^role = "project"' "${config}" || fail "config role != \"project\""
if grep -q '^main = ' "${config}"; then
  fail "standalone project should NOT have a main field"
fi

# Required structure
for f in index.md log.md schema.md .manifest.json .gitignore; do
  [[ -e "${TESTDIR}/wiki/${f}" ]] || fail "missing ${f}"
done

# Existing two-arg form still works
bash "${INIT}" project "${TESTDIR}/wiki2" "${TESTDIR}/wiki" >/dev/null \
  || fail "wiki-init.sh project <path> <main> must still succeed"
grep -q '^main = ' "${TESTDIR}/wiki2/.wiki-config" || fail "with-main form lost main field"

echo "PASS: wiki-init.sh standalone project mode"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-init-standalone-project.sh`
Expected: FAIL — current `wiki-init.sh` requires a main path for project mode (lines 33-35).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-init-standalone-project.sh
git commit -m "test(unit): add failing test for standalone project init"
```

---

### Task 3: Failing test — `wiki-init.sh` is re-runnable on existing wikis

**Files:**
- Create: `tests/unit/test-wiki-init-rerun-idempotent.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-init.sh on an existing wiki is idempotent (skips existing
# artifacts) and adds new pieces (inbox/, .raw-staging/, README.md).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# 1. Initial main wiki creation
bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null \
  || fail "first init must succeed"

# 2. Hand-edit an existing artifact to verify it's preserved on re-run
echo "USER EDIT" > "${TESTDIR}/wiki/index.md"
echo "USER README" > "${TESTDIR}/wiki/README.md"
mtime_before=$(stat -f %m "${TESTDIR}/wiki/.wiki-config" 2>/dev/null || stat -c %Y "${TESTDIR}/wiki/.wiki-config")

# 3. Delete inbox/ and .raw-staging/ to simulate v2.3-pre-upgrade state
rm -rf "${TESTDIR}/wiki/inbox" "${TESTDIR}/wiki/.raw-staging"

# 4. Re-run init
sleep 1  # ensure mtime granularity
bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null \
  || fail "re-run must succeed"

# 5. User edits preserved
grep -q "USER EDIT" "${TESTDIR}/wiki/index.md" || fail "user-edited index.md was overwritten"
grep -q "USER README" "${TESTDIR}/wiki/README.md" || fail "user-edited README.md was overwritten"

# 6. Missing pieces created
[[ -d "${TESTDIR}/wiki/inbox" ]] || fail "re-run did not create inbox/"
[[ -d "${TESTDIR}/wiki/.raw-staging" ]] || fail "re-run did not create .raw-staging/"

# 7. .wiki-config not rewritten (preserves created date)
mtime_after=$(stat -f %m "${TESTDIR}/wiki/.wiki-config" 2>/dev/null || stat -c %Y "${TESTDIR}/wiki/.wiki-config")
[[ "${mtime_before}" == "${mtime_after}" ]] || fail ".wiki-config was rewritten on re-run"

# 8. Fresh init writes a README (the user one was preserved above; verify a fresh
#    init would produce a README too)
TESTDIR2="$(mktemp -d)"
bash "${INIT}" main "${TESTDIR2}/wiki" >/dev/null
[[ -f "${TESTDIR2}/wiki/README.md" ]] || fail "fresh init did not create README.md"
grep -q -i 'inbox' "${TESTDIR2}/wiki/README.md" || fail "README does not mention inbox/"
grep -q -i 'raw' "${TESTDIR2}/wiki/README.md" || fail "README does not mention raw/ rule"
rm -rf "${TESTDIR2}"

echo "PASS: wiki-init.sh re-runnable + creates v2.4 pieces"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-init-rerun-idempotent.sh`
Expected: FAIL — current `wiki-init.sh` does not create `inbox/`, `.raw-staging/`, or `README.md`.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-init-rerun-idempotent.sh
git commit -m "test(unit): add failing test for re-runnable wiki-init.sh"
```

---

### Task 4: Modify `wiki-init.sh` — standalone project, idempotency, new directories, README

**Files:**
- Modify: `scripts/wiki-init.sh`

- [ ] **Step 1: Allow project mode without main argument**

Find the validation block in `scripts/wiki-init.sh` (lines 29-37):

```bash
case "${role}" in
  main)
    [[ -z "${main_path}" ]] || { echo >&2 "main role takes no main_path arg"; usage; }
    ;;
  project)
    [[ -n "${main_path}" ]] || { echo >&2 "project role requires main_path"; usage; }
    ;;
  *) usage ;;
esac
```

Change the `project` branch to allow an empty `main_path`:

```bash
case "${role}" in
  main)
    [[ -z "${main_path}" ]] || { echo >&2 "main role takes no main_path arg"; usage; }
    ;;
  project)
    # main_path is optional — standalone project wikis are first-class in v2.4.
    ;;
  *) usage ;;
esac
```

Also relax the argument count check at the top:

```bash
[[ $# -ge 2 ]] || usage
```

stays the same (project mode still needs `<wiki_path>` as the second arg).

- [ ] **Step 2: Make `.wiki-config` writing handle missing main**

Find the `.wiki-config` write block (~lines 68-95). The project branch currently writes:

```bash
cat > "${wiki}/.wiki-config" <<EOF
role = "project"
main = "${main_path}"
created = "${today}"

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
EOF
```

Change it to omit `main = ...` when `main_path` is empty:

```bash
{
  echo "role = \"project\""
  if [[ -n "${main_path}" ]]; then
    echo "main = \"${main_path}\""
  fi
  echo "created = \"${today}\""
  echo "fork_to_main = false"
  echo ""
  echo "[platform]"
  echo "agent_cli = \"claude\""
  echo "headless_command = \"claude -p\""
  echo ""
  echo "[settings]"
  echo "auto_commit = true"
} > "${wiki}/.wiki-config"
```

Note `fork_to_main = false` is the v2.4 default; `wiki use both` flips it.

The `main` branch is unchanged.

- [ ] **Step 3: Add `inbox/` and `.raw-staging/` to the directory creation**

Find the directory creation loop (~line 60):

```bash
for d in concepts entities queries ideas raw .wiki-pending .locks .obsidian; do
  mkdir -p "${wiki}/${d}"
done
```

Change to:

```bash
for d in concepts entities queries ideas raw inbox .wiki-pending .locks .obsidian .raw-staging; do
  mkdir -p "${wiki}/${d}"
done
```

`inbox/` is the v2.4 drop zone. `.raw-staging/` is the ingester's staging area (used by Leg 3 for atomic writes to `raw/`).

- [ ] **Step 4: Add README.md generation**

After the existing `index.md`, `log.md`, `schema.md` creation blocks, add a README block:

```bash
if [[ ! -f "${wiki}/README.md" ]]; then
  cat > "${wiki}/README.md" <<EOF
# ${role} wiki — ${today}

This wiki is auto-managed by the karpathy-wiki plugin. Most of the time
you should not edit files directly — captures, ingestion, and page
writes happen through the plugin's tooling.

## Where to drop files

**\`inbox/\`** — the universal drop zone for ingestion. Put anything
that should become a wiki page here:

- Obsidian Web Clipper exports (configure your template's "Note
  location" to \`inbox\` and "Vault" to this wiki — see "Web Clipper
  setup" below).
- Research reports from subagents (the agent typically moves these
  for you).
- Manual file drops: downloaded articles, PDF→markdown exports,
  meeting notes.

After you drop a file, ingestion happens on the next agent session
start (silent), or immediately if you run \`wiki ingest-now <this-wiki-path>\`.

**Do NOT put files in \`raw/\`.** That directory is the ingester's
archive — every file there has a manifest entry tracking origin,
sha256, and which wiki pages reference it. If you put a file there
by accident, the next ingest will move it to \`inbox/\` and process
it normally (a WARN gets logged, but no data is lost).

## Web Clipper setup

In Obsidian Web Clipper settings → Templates → (your template) →
Location:

- **Note name:** \`{{title}}\` (or whatever filename pattern you prefer)
- **Note location:** \`inbox\`
- **Vault:** select this wiki's directory

That's it. Clip a page; the file lands in \`inbox/\`; next agent session
ingests it.

## Other top-level directories

- \`concepts/\`, \`entities/\`, \`queries/\`, \`ideas/\` — wiki content,
  written by the ingester. Editing pages directly is allowed but the
  ingester will eventually re-rate / re-link them.
- \`archive/\` — old content the ingester decided to retire.
- \`raw/\` — the ingester's archive (see above).
- \`.wiki-pending/\` — pending captures (transient).
- \`.locks/\` — concurrency primitives (transient).
- \`.raw-staging/\` — ingester staging area (transient).
- \`.manifest.json\`, \`.ingest.log\`, \`.ingest-issues.jsonl\` — machine
  state.

## Schema

See \`schema.md\` for the live category list, tag taxonomy, and
thresholds.
EOF
fi
```

The `if [[ ! -f ... ]]` guard means re-running init on an existing wiki preserves any user edits to README.md.

- [ ] **Step 5: Run the failing tests to verify they pass**

```bash
bash tests/unit/test-wiki-init-standalone-project.sh
bash tests/unit/test-wiki-init-rerun-idempotent.sh
```

Both expected: PASS.

- [ ] **Step 6: Run the existing init test to verify no regression**

Run: `bash tests/unit/test-init.sh`
Expected: PASS. The existing tests assert the original artifacts (`index.md`, `log.md`, `schema.md`, `.wiki-config`, `.manifest.json`, `.gitignore`) are present; `inbox/` and `.raw-staging/` and `README.md` are additions, not replacements.

- [ ] **Step 7: Commit**

```bash
git add scripts/wiki-init.sh
git commit -m "feat(init): standalone project mode + idempotent re-run + inbox/ + README.md"
```

---

### Task 5: Failing test — `wiki-resolve.sh` exit-code matrix

**Files:**
- Create: `tests/unit/test-wiki-resolve.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-resolve.sh exit codes for every combination of pointer
# state x cwd state. ≥ 14 cases per spec test surface.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOLVE="${REPO_ROOT}/scripts/wiki-resolve.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${RESOLVE}" ]] || fail "wiki-resolve.sh missing or not executable"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# Use a pointer file inside TESTDIR to avoid touching the user's real ~/.wiki-pointer
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"

# Helper: assert exit code from wiki-resolve.sh in a given cwd
assert_exit() {
  local desc="$1"
  local cwd="$2"
  local expected="$3"
  local actual
  ( cd "${cwd}" && bash "${RESOLVE}" >/dev/null 2>&1 ) && actual=0 || actual=$?
  [[ "${actual}" == "${expected}" ]] || \
    fail "${desc}: expected exit ${expected}, got ${actual}"
}

# Helper: assert stdout from wiki-resolve.sh contains a path
assert_returns() {
  local desc="$1"
  local cwd="$2"
  local expected="$3"
  local actual
  actual=$( cd "${cwd}" && bash "${RESOLVE}" 2>/dev/null )
  echo "${actual}" | grep -qF "${expected}" || \
    fail "${desc}: expected output to contain '${expected}', got '${actual}'"
}

# Set up fixtures
MAIN="${TESTDIR}/main-wiki"
PROJECT="${TESTDIR}/proj"
bash "${INIT}" main "${MAIN}" >/dev/null
mkdir -p "${PROJECT}"
bash "${INIT}" project "${PROJECT}/wiki" "${MAIN}" >/dev/null

# Project-pointer config at PROJECT
cat > "${PROJECT}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "./wiki"
created = "2026-05-06"
fork_to_main = false
EOF

UNCONFIGURED="${TESTDIR}/scratch"
mkdir -p "${UNCONFIGURED}"

# Case 1: pointer missing → exit 10
rm -f "${WIKI_POINTER_FILE}"
assert_exit "pointer missing" "${UNCONFIGURED}" 10

# Case 2: pointer = none + cwd has .wiki-config (fork_to_main = false) → 0
echo "none" > "${WIKI_POINTER_FILE}"
assert_exit "pointer=none + cwd has config (fork=false)" "${PROJECT}" 0
assert_returns "pointer=none + cwd has config (fork=false)" "${PROJECT}" "${PROJECT}/wiki"

# Case 3: pointer = none + cwd has .wiki-config with fork_to_main = true → 12
sed -i.bak 's/fork_to_main = false/fork_to_main = true/' "${PROJECT}/.wiki-config"
assert_exit "pointer=none + cwd has fork_to_main=true" "${PROJECT}" 12
sed -i.bak 's/fork_to_main = true/fork_to_main = false/' "${PROJECT}/.wiki-config"

# Case 4: pointer = none + cwd unconfigured → 11
assert_exit "pointer=none + cwd unconfigured" "${UNCONFIGURED}" 11

# Case 5: pointer valid + cwd has project-pointer (fork=false) → 0, returns project wiki
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
assert_exit "pointer valid + project-pointer + fork=false" "${PROJECT}" 0
assert_returns "pointer valid + project-pointer + fork=false" "${PROJECT}" "${PROJECT}/wiki"

# Case 6: pointer valid + cwd has project-pointer (fork=true) → 0, returns [project, main]
sed -i.bak 's/fork_to_main = false/fork_to_main = true/' "${PROJECT}/.wiki-config"
output=$( cd "${PROJECT}" && bash "${RESOLVE}" )
echo "${output}" | grep -qF "${PROJECT}/wiki" || fail "fork mode: project wiki missing"
echo "${output}" | grep -qF "${MAIN}" || fail "fork mode: main wiki missing"
sed -i.bak 's/fork_to_main = true/fork_to_main = false/' "${PROJECT}/.wiki-config"

# Case 7: cwd has .wiki-mode = main-only + pointer valid → 0, returns [main]
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "cwd .wiki-mode=main-only + pointer valid" "${UNCONFIGURED}" 0
assert_returns "cwd .wiki-mode=main-only + pointer valid" "${UNCONFIGURED}" "${MAIN}"
rm "${UNCONFIGURED}/.wiki-mode"

# Case 8: cwd has .wiki-mode = main-only + pointer = none → 12
echo "none" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "cwd .wiki-mode=main-only + pointer=none" "${UNCONFIGURED}" 12
rm "${UNCONFIGURED}/.wiki-mode"

# Case 9: cwd has BOTH .wiki-config AND .wiki-mode → 13
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${PROJECT}/.wiki-mode"
assert_exit "cwd has both .wiki-config and .wiki-mode" "${PROJECT}" 13
rm "${PROJECT}/.wiki-mode"

# Case 10: cwd has .wiki-config role=main but missing schema.md → 14
HALF="${TESTDIR}/half-built"
mkdir -p "${HALF}/.wiki-pending"
cat > "${HALF}/.wiki-config" <<EOF
role = "main"
created = "2026-05-06"
fork_to_main = false
EOF
echo "{}" > "${HALF}/.manifest.json"
echo "# Index" > "${HALF}/index.md"
# schema.md is missing
assert_exit "cwd half-built (no schema.md)" "${HALF}" 14
echo "# Schema" > "${HALF}/schema.md"
# index.md is now present, schema.md present, .wiki-pending/ present — should resolve fine
assert_exit "cwd fully built" "${HALF}" 0

# Case 11: pointer-target half-built (project-pointer's wiki dir missing schema) → 14
BROKEN_MAIN="${TESTDIR}/broken-main"
mkdir -p "${BROKEN_MAIN}/.wiki-pending"
cat > "${BROKEN_MAIN}/.wiki-config" <<EOF
role = "main"
created = "2026-05-06"
fork_to_main = false
EOF
echo "{}" > "${BROKEN_MAIN}/.manifest.json"
echo "# Index" > "${BROKEN_MAIN}/index.md"
# schema.md missing
echo "${BROKEN_MAIN}" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "pointer target half-built" "${UNCONFIGURED}" 14
rm "${UNCONFIGURED}/.wiki-mode"
rm -rf "${BROKEN_MAIN}"

# Case 12: pointer points at non-main wiki (role=project) → 10
PROJ_AS_POINTER="${TESTDIR}/proj-as-pointer"
bash "${INIT}" project "${PROJ_AS_POINTER}" >/dev/null
echo "${PROJ_AS_POINTER}" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "pointer target role=project (not main)" "${UNCONFIGURED}" 10
rm "${UNCONFIGURED}/.wiki-mode"

# Case 13: broken pointer (path doesn't exist) → 10
echo "/nonexistent/path/to/wiki" > "${WIKI_POINTER_FILE}"
assert_exit "broken pointer path" "${UNCONFIGURED}" 10

# Case 14: pointer is a symlink to a valid main → 0
echo "${MAIN}" > "${WIKI_POINTER_FILE}.target"
ln -sf "${WIKI_POINTER_FILE}.target" "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "symlink pointer to valid main" "${UNCONFIGURED}" 0
rm "${UNCONFIGURED}/.wiki-mode"
rm -f "${WIKI_POINTER_FILE}" "${WIKI_POINTER_FILE}.target"

echo "PASS: wiki-resolve.sh exit-code matrix (14 cases)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-resolve.sh`
Expected: FAIL with "wiki-resolve.sh missing or not executable" (the script doesn't exist yet).

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-resolve.sh
git commit -m "test(unit): add failing test for wiki-resolve.sh exit-code matrix"
```

---

### Task 6: Implement `scripts/wiki-resolve.sh`

**Files:**
- Create: `scripts/wiki-resolve.sh`

- [ ] **Step 1: Write the resolver**

```bash
#!/bin/bash
# wiki-resolve.sh — non-interactive wiki resolver.
#
# Determines which wiki(s) a chat-driven capture should target based on
# cwd's .wiki-config or .wiki-mode and the user's main-wiki pointer.
# Returns target wiki paths on stdout (one per line) and exit 0, OR
# exits with one of these specific codes signaling user input is needed:
#
#   10 — pointer missing or broken (need bootstrap or re-init)
#   11 — cwd unconfigured (need per-cwd prompt)
#   12 — config requires main but pointer is none/missing
#   13 — both .wiki-config AND .wiki-mode present at cwd (conflict)
#   14 — half-built wiki (cwd or pointer target missing required files)
#
# Cwd-only resolution: walks NO parents. The SessionStart hook handles
# its own walk-up via wiki_root_from_cwd; this resolver is for
# user-driven CLI commands (bin/wiki capture, bin/wiki ingest-now).
#
# Override $WIKI_POINTER_FILE for testing (default: ~/.wiki-pointer).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"

# Read main wiki pointer.
main_wiki=""
if [[ ! -e "${POINTER_FILE}" ]]; then
  exit 10
fi
# Follow symlinks for the pointer file itself
pointer_content="$(cat "${POINTER_FILE}" 2>/dev/null | tr -d '[:space:]')"
case "${pointer_content}" in
  "")
    exit 10  # Empty pointer file
    ;;
  none)
    main_wiki=""
    ;;
  *)
    if [[ ! -f "${pointer_content}/.wiki-config" ]]; then
      exit 10
    fi
    # Validate role = "main" on the pointer target
    if ! grep -q '^role = "main"' "${pointer_content}/.wiki-config"; then
      exit 10
    fi
    # Validate structure
    for required in schema.md index.md .wiki-pending; do
      if [[ ! -e "${pointer_content}/${required}" ]]; then
        exit 14
      fi
    done
    main_wiki="${pointer_content}"
    ;;
esac

# Read cwd state.
config_present=0
mode_present=0
[[ -f "$(pwd)/.wiki-config" ]] && config_present=1
[[ -f "$(pwd)/.wiki-mode" ]] && mode_present=1

# Conflict: both files present.
if [[ "${config_present}" == 1 && "${mode_present}" == 1 ]]; then
  exit 13
fi

wiki_root=""
fork=0

if [[ "${config_present}" == 1 ]]; then
  config="$(pwd)/.wiki-config"
  role=$(grep '^role = ' "${config}" | head -1 | sed 's/^role = "\(.*\)"/\1/')

  case "${role}" in
    main|project)
      wiki_root="$(pwd)"
      # Validate structure
      for required in schema.md index.md .wiki-pending; do
        if [[ ! -e "${wiki_root}/${required}" ]]; then
          exit 14
        fi
      done
      ;;
    project-pointer)
      sub=$(grep '^wiki = ' "${config}" | head -1 | sed 's/^wiki = "\(.*\)"/\1/')
      [[ -n "${sub}" ]] || exit 14
      # Resolve relative path against cwd
      if [[ "${sub}" == /* ]]; then
        wiki_root="${sub}"
      else
        wiki_root="$(pwd)/${sub#./}"
      fi
      # Validate structure
      [[ -f "${wiki_root}/.wiki-config" ]] || exit 14
      for required in schema.md index.md .wiki-pending; do
        if [[ ! -e "${wiki_root}/${required}" ]]; then
          exit 14
        fi
      done
      ;;
    *)
      # Unknown role — treat as conflict-equivalent
      exit 13
      ;;
  esac

  # Read fork_to_main (default false)
  if grep -q '^fork_to_main = true' "${config}"; then
    fork=1
  fi

elif [[ "${mode_present}" == 1 ]]; then
  mode_value=$(head -1 "$(pwd)/.wiki-mode" | tr -d '[:space:]')
  case "${mode_value}" in
    main-only)
      [[ -n "${main_wiki}" ]] || exit 12
      wiki_root="${main_wiki}"
      fork=0
      ;;
    *)
      # Unknown .wiki-mode value
      exit 13
      ;;
  esac
else
  # No config, no mode — unconfigured cwd.
  exit 11
fi

# Build target list.
if [[ "${fork}" == 1 ]]; then
  [[ -n "${main_wiki}" ]] || exit 12
  echo "${wiki_root}"
  if [[ "${main_wiki}" != "${wiki_root}" ]]; then
    echo "${main_wiki}"
  fi
else
  echo "${wiki_root}"
fi

exit 0
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/wiki-resolve.sh
```

- [ ] **Step 3: Run the failing test from Task 5**

Run: `bash tests/unit/test-wiki-resolve.sh`
Expected: PASS (all 14 cases).

If any case fails, debug the resolver against that specific case. Common issues:

- Missing `tr -d '[:space:]'` on pointer/mode content (extra newline confuses string match).
- Symlink resolution: `cat "${POINTER_FILE}"` follows symlinks already; ensure the test's symlink-target file has a trailing newline removed.
- Relative wiki path in project-pointer: ensure `${sub#./}` strips a leading `./`.

- [ ] **Step 4: Commit**

```bash
git add scripts/wiki-resolve.sh
git commit -m "feat(scripts): add wiki-resolve.sh non-interactive resolver (5 exit codes)"
```

---

### Task 7: Failing test — `wiki-init-main.sh` bootstrap

**Files:**
- Create: `tests/unit/test-wiki-init-main.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-init-main.sh bootstraps ~/.wiki-pointer correctly.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT_MAIN="${REPO_ROOT}/scripts/wiki-init-main.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
export WIKI_INIT_MAIN_HOME="${TESTDIR}/home"  # Override $HOME-scan root for testing
mkdir -p "${WIKI_INIT_MAIN_HOME}"

# Case 1: silent migration when a unique main wiki exists at depth ≤ 2
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI_INIT_MAIN_HOME}/wiki" >/dev/null
echo "n" | bash "${INIT_MAIN}" 2>/dev/null  # 'n' is a safe choice if the script prompts
[[ -f "${WIKI_POINTER_FILE}" ]] || fail "silent migration: pointer not written"
[[ "$(cat "${WIKI_POINTER_FILE}")" == "${WIKI_INIT_MAIN_HOME}/wiki" ]] \
  || fail "silent migration: pointer points at wrong path: $(cat "${WIKI_POINTER_FILE}")"

# Case 2: pointer-already-exists no-op
mtime_before=$(stat -f %m "${WIKI_POINTER_FILE}" 2>/dev/null || stat -c %Y "${WIKI_POINTER_FILE}")
sleep 1
bash "${INIT_MAIN}" >/dev/null 2>&1
mtime_after=$(stat -f %m "${WIKI_POINTER_FILE}" 2>/dev/null || stat -c %Y "${WIKI_POINTER_FILE}")
[[ "${mtime_before}" == "${mtime_after}" ]] || fail "pointer-already-exists: pointer was rewritten"

# Case 3: 'none' choice (no main wiki)
rm -f "${WIKI_POINTER_FILE}"
rm -rf "${WIKI_INIT_MAIN_HOME}"
mkdir -p "${WIKI_INIT_MAIN_HOME}"
# Simulate user choosing 2 (no main wiki)
echo "2" | bash "${INIT_MAIN}" 2>/dev/null
[[ "$(cat "${WIKI_POINTER_FILE}")" == "none" ]] \
  || fail "'no main' choice: pointer should be 'none'"

# Case 4: multi-candidate prompt
rm -f "${WIKI_POINTER_FILE}"
rm -rf "${WIKI_INIT_MAIN_HOME}"
mkdir -p "${WIKI_INIT_MAIN_HOME}"
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI_INIT_MAIN_HOME}/wiki" >/dev/null
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI_INIT_MAIN_HOME}/work-wiki" >/dev/null
# Simulate user choosing option 1 (first candidate)
echo "1" | bash "${INIT_MAIN}" 2>/dev/null
ptr=$(cat "${WIKI_POINTER_FILE}")
[[ "${ptr}" == "${WIKI_INIT_MAIN_HOME}/wiki" || "${ptr}" == "${WIKI_INIT_MAIN_HOME}/work-wiki" ]] \
  || fail "multi-candidate: pointer should be one of the two; got '${ptr}'"

echo "PASS: wiki-init-main.sh bootstrap"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-init-main.sh`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-init-main.sh
git commit -m "test(unit): add failing test for wiki-init-main.sh bootstrap"
```

---

### Task 8: Implement `scripts/wiki-init-main.sh`

**Files:**
- Create: `scripts/wiki-init-main.sh`

- [ ] **Step 1: Write the bootstrap script**

```bash
#!/bin/bash
# wiki-init-main.sh — interactive bootstrap of ~/.wiki-pointer.
#
# Behavior:
# 1. If $WIKI_POINTER_FILE already exists → no-op (do not re-prompt).
# 2. Find candidate main wikis at depth ≤ 2 in $HOME (or
#    $WIKI_INIT_MAIN_HOME for testing). A candidate is a directory
#    with .wiki-config containing role = "main".
# 3. If exactly ONE candidate → silent migration (write pointer; no prompt).
# 4. If MULTIPLE candidates → prompt user to pick.
# 5. If ZERO candidates → prompt user: yes (create new) | no (write 'none').
#
# Override $WIKI_POINTER_FILE for testing (default: ~/.wiki-pointer).
# Override $WIKI_INIT_MAIN_HOME for testing (default: $HOME).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"
SCAN_HOME="${WIKI_INIT_MAIN_HOME:-${HOME}}"

# Step 1: pointer already exists → no-op.
if [[ -f "${POINTER_FILE}" || -L "${POINTER_FILE}" ]]; then
  exit 0
fi

# Step 2: find candidate main wikis.
candidates=()
while IFS= read -r config; do
  if grep -q '^role = "main"' "${config}"; then
    candidates+=("$(dirname "${config}")")
  fi
done < <(find "${SCAN_HOME}" -maxdepth 3 -name '.wiki-config' -type f 2>/dev/null)

case "${#candidates[@]}" in
  1)
    # Silent migration.
    echo "${candidates[0]}" > "${POINTER_FILE}"
    echo "wiki-init-main: silent migration — pointer set to ${candidates[0]}" >&2
    exit 0
    ;;
  0)
    # No candidate — prompt for create vs none.
    cat <<'EOF'

You don't have a main (global) wiki yet.
A main wiki collects general patterns reusable across projects.
You can have project-only wikis without one.

  1) yes — create a main wiki (you'll be asked where)
  2) no  — project wikis only

EOF
    read -p "Reply with 1 or 2: " choice
    case "${choice}" in
      1)
        cat <<EOF

Where should the main wiki live?
  Default: \$HOME/wiki/

EOF
        read -p "Reply 'default' or a path: " path
        if [[ "${path}" == "default" || -z "${path}" ]]; then
          path="${SCAN_HOME}/wiki"
        fi
        bash "${SCRIPT_DIR}/wiki-init.sh" main "${path}"
        echo "${path}" > "${POINTER_FILE}"
        ;;
      2)
        echo "none" > "${POINTER_FILE}"
        ;;
      *)
        echo >&2 "wiki-init-main: invalid choice; aborting"
        exit 1
        ;;
    esac
    ;;
  *)
    # Multi-candidate — prompt.
    echo
    echo "Found existing main wiki(s):"
    local i=1
    for c in "${candidates[@]}"; do
      echo "  ${i}) ${c}"
      i=$((i + 1))
    done
    local nopt=$((${#candidates[@]} + 1))
    local nopt2=$((nopt + 1))
    echo "  ${nopt}) other (enter a path)"
    echo "  ${nopt2}) none — project wikis only"
    echo
    read -p "Which one should be the main wiki for v2.4? " choice
    if [[ "${choice}" -ge 1 && "${choice}" -le "${#candidates[@]}" ]]; then
      echo "${candidates[$((choice - 1))]}" > "${POINTER_FILE}"
    elif [[ "${choice}" == "${nopt}" ]]; then
      read -p "Enter path: " path
      bash "${SCRIPT_DIR}/wiki-init.sh" main "${path}"
      echo "${path}" > "${POINTER_FILE}"
    elif [[ "${choice}" == "${nopt2}" ]]; then
      echo "none" > "${POINTER_FILE}"
    else
      echo >&2 "wiki-init-main: invalid choice; aborting"
      exit 1
    fi
    ;;
esac

exit 0
```

- [ ] **Step 2: Make it executable and run the test**

```bash
chmod +x scripts/wiki-init-main.sh
bash tests/unit/test-wiki-init-main.sh
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/wiki-init-main.sh
git commit -m "feat(scripts): add wiki-init-main.sh bootstrap (silent migration + prompts)"
```

---

### Task 9: Failing test — `wiki-use.sh`

**Files:**
- Create: `tests/unit/test-wiki-use.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify wiki-use.sh subcommands and refusal cases.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
USE="${REPO_ROOT}/scripts/wiki-use.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

# Case 1: wiki use project (fresh cwd)
PROJ="${TESTDIR}/proj1"
mkdir -p "${PROJ}"
( cd "${PROJ}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project failed"
[[ -d "${PROJ}/wiki" ]] || fail "wiki use project did not create ./wiki/"
[[ -f "${PROJ}/.wiki-config" ]] || fail "wiki use project did not write .wiki-config"
grep -q '^role = "project-pointer"' "${PROJ}/.wiki-config" || fail "config role != project-pointer"
grep -q '^fork_to_main = false' "${PROJ}/.wiki-config" || fail "fork_to_main should be false"

# Case 2: wiki use project (idempotent re-run)
( cd "${PROJ}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project re-run failed"

# Case 3: wiki use main (fresh cwd, no pre-existing config)
PROJ_MAIN="${TESTDIR}/proj2"
mkdir -p "${PROJ_MAIN}"
( cd "${PROJ_MAIN}" && bash "${USE}" main ) >/dev/null \
  || fail "wiki use main failed"
[[ "$(cat "${PROJ_MAIN}/.wiki-mode")" == "main-only" ]] \
  || fail "wiki use main did not write 'main-only'"

# Case 4: wiki use main inside an existing wiki (refused)
( cd "${PROJ}" && bash "${USE}" main ) 2>/dev/null \
  && fail "wiki use main inside existing wiki should refuse"

# Case 5: wiki use both (fresh cwd)
PROJ_BOTH="${TESTDIR}/proj3"
mkdir -p "${PROJ_BOTH}"
( cd "${PROJ_BOTH}" && bash "${USE}" both ) >/dev/null \
  || fail "wiki use both failed"
grep -q '^fork_to_main = true' "${PROJ_BOTH}/.wiki-config" || fail "wiki use both: fork_to_main should be true"

# Case 6: wiki use both (when pointer = none) — refused
echo "none" > "${WIKI_POINTER_FILE}"
PROJ_BOTH_NOMAIN="${TESTDIR}/proj4"
mkdir -p "${PROJ_BOTH_NOMAIN}"
( cd "${PROJ_BOTH_NOMAIN}" && bash "${USE}" both ) 2>/dev/null \
  && fail "wiki use both should refuse when pointer = none"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

# Case 7: wiki use both (existing project, flips fork_to_main)
( cd "${PROJ}" && bash "${USE}" both ) >/dev/null \
  || fail "wiki use both on existing project failed"
grep -q '^fork_to_main = true' "${PROJ}/.wiki-config" || fail "wiki use both: did not flip fork_to_main"

# Case 8: wiki use project flips back
( cd "${PROJ}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project (flip back) failed"
grep -q '^fork_to_main = false' "${PROJ}/.wiki-config" || fail "fork_to_main should be false again"

echo "PASS: wiki-use.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-use.sh`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-use.sh
git commit -m "test(unit): add failing test for wiki-use.sh"
```

---

### Task 10: Implement `scripts/wiki-use.sh`

**Files:**
- Create: `scripts/wiki-use.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# wiki-use.sh — change per-cwd wiki mode.
#
# Subcommands:
#   wiki-use.sh project   — write .wiki-config (project-pointer, fork=false)
#   wiki-use.sh main      — write .wiki-mode = main-only (refuses if cwd has .wiki-config)
#   wiki-use.sh both      — write .wiki-config with fork_to_main = true (refuses if pointer = none)
#
# Idempotent: re-running with the current state is a no-op.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

POINTER_FILE="${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}"

mode="${1:-}"
[[ -n "${mode}" ]] || { echo >&2 "usage: wiki use project|main|both"; exit 1; }

read_main_wiki() {
  if [[ ! -f "${POINTER_FILE}" ]]; then
    echo "none"
    return
  fi
  cat "${POINTER_FILE}" | tr -d '[:space:]'
}

write_project_pointer_config() {
  local fork="$1"
  local main="$2"
  local cwd_config="$(pwd)/.wiki-config"
  local today="$(date +%Y-%m-%d)"
  {
    echo "role = \"project-pointer\""
    echo "wiki = \"./wiki\""
    echo "created = \"${today}\""
    if [[ -n "${main}" && "${main}" != "none" ]]; then
      echo "main = \"${main}\""
    fi
    echo "fork_to_main = ${fork}"
  } > "${cwd_config}"
}

case "${mode}" in
  project)
    main="$(read_main_wiki)"
    if [[ ! -d "$(pwd)/wiki" ]]; then
      if [[ "${main}" == "none" ]]; then
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" >/dev/null
      else
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" "${main}" >/dev/null
      fi
    fi
    write_project_pointer_config "false" "${main}"
    rm -f "$(pwd)/.wiki-mode"
    echo "wiki use project: $(pwd)/wiki/ (fork_to_main = false)"
    ;;

  main)
    if [[ -f "$(pwd)/.wiki-config" ]]; then
      cat >&2 <<EOF
wiki use main: refused — cwd already has .wiki-config (cwd is itself a wiki).
'main-only' mode would orphan the local wiki. To stop using this wiki,
'cd' out of it first. Got role: $(grep '^role = ' "$(pwd)/.wiki-config" | head -1)
EOF
      exit 1
    fi
    echo "main-only" > "$(pwd)/.wiki-mode"
    if [[ -d "$(pwd)/wiki" ]]; then
      cat >&2 <<EOF
wiki use main: warning — local ./wiki/ exists from a prior project mode.
Captures will no longer go there. To remove it: rm -rf ./wiki/
EOF
    fi
    echo "wiki use main: captures go to main wiki"
    ;;

  both)
    main="$(read_main_wiki)"
    if [[ "${main}" == "none" || -z "${main}" ]]; then
      cat >&2 <<EOF
wiki use both: refused — \$WIKI_POINTER_FILE is 'none' or missing.
'both' mode requires a main wiki to fork to. Run 'wiki init-main' first
or 'wiki use project' for a project-only setup.
EOF
      exit 1
    fi
    if [[ -f "$(pwd)/.wiki-config" ]]; then
      role=$(grep '^role = ' "$(pwd)/.wiki-config" | head -1 | sed 's/^role = "\(.*\)"/\1/')
      case "${role}" in
        project-pointer|main|project)
          # Set fork_to_main = true in place
          if grep -q '^fork_to_main = ' "$(pwd)/.wiki-config"; then
            sed -i.bak 's/^fork_to_main = .*/fork_to_main = true/' "$(pwd)/.wiki-config"
            rm -f "$(pwd)/.wiki-config.bak"
          else
            echo "fork_to_main = true" >> "$(pwd)/.wiki-config"
          fi
          rm -f "$(pwd)/.wiki-mode"
          echo "wiki use both: fork_to_main = true on existing config (role=${role})"
          ;;
        *)
          echo >&2 "wiki use both: unknown role '${role}' in existing .wiki-config"
          exit 1
          ;;
      esac
    else
      # Fresh cwd
      if [[ ! -d "$(pwd)/wiki" ]]; then
        bash "${SCRIPT_DIR}/wiki-init.sh" project "$(pwd)/wiki" "${main}" >/dev/null
      fi
      write_project_pointer_config "true" "${main}"
      rm -f "$(pwd)/.wiki-mode"
      echo "wiki use both: created project wiki + fork_to_main = true"
    fi
    ;;

  *)
    echo >&2 "wiki use: unknown mode '${mode}'; valid: project|main|both"
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make it executable and run the test**

```bash
chmod +x scripts/wiki-use.sh
bash tests/unit/test-wiki-use.sh
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/wiki-use.sh
git commit -m "feat(scripts): add wiki-use.sh (project/main/both, idempotent, refusal cases)"
```

---

### Task 11: Failing test — `bin/wiki capture` body input + headless fallback + orphan preservation

**Files:**
- Create: `tests/unit/test-wiki-capture-cli.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify bin/wiki capture body-input contract, headless fallback,
# orphan preservation. Does NOT spawn a real ingester (uses a mock
# headless_command).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
# Override headless_command with no-op for testing
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${MAIN}/.wiki-config"
rm -f "${MAIN}/.wiki-config.bak"

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
export HOME_FOR_ORPHANS="${TESTDIR}/home"
export WIKI_ORPHANS_DIR="${HOME_FOR_ORPHANS}/.wiki-orphans"
export CLAUDE_HEADLESS=1  # Force headless mode in tests

# Case 1: chat-only via stdin
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
echo "main-only" > "${PROJ}/.wiki-mode"
BODY=$(printf 'A real chat-only body that exceeds 1500 bytes.\n%.0s' {1..40})
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "Test" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "chat-only via stdin failed"
ls "${MAIN}/.wiki-pending/" | grep -q '\.md$' || fail "no capture appeared in main pending"

# Case 2: chat-only via --body-file
TMPBODY="$(mktemp)"
echo "${BODY}" > "${TMPBODY}"
( cd "${PROJ}" && bash "${WIKI_BIN}" capture --title "Test2" --kind chat-only --suggested-action create --body-file "${TMPBODY}" ) >/dev/null \
  || fail "chat-only via --body-file failed"

# Case 3: missing body (no stdin, no --body-file) → error
( cd "${PROJ}" && bash "${WIKI_BIN}" capture --title "Test3" --kind chat-only --suggested-action create < /dev/null ) 2>/dev/null \
  && fail "missing body should error"

# Case 4: max-body limit (256 KB)
HUGE_BODY=$(yes "x" | head -c 270000)
( cd "${PROJ}" && echo "${HUGE_BODY}" | bash "${WIKI_BIN}" capture --title "Huge" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "body > 256 KB should error"

# Case 5: headless + unconfigured cwd + no pointer → orphan-preserve
rm -f "${WIKI_POINTER_FILE}"
SCRATCH="${TESTDIR}/scratch"
mkdir -p "${SCRATCH}"
( cd "${SCRATCH}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "OrphanTest" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "headless + no pointer + unconfigured cwd should abort"
[[ -d "${WIKI_ORPHANS_DIR}" ]] || fail "no orphan dir created"
ls "${WIKI_ORPHANS_DIR}/" | grep -q '\.md$' || fail "no orphan file in $WIKI_ORPHANS_DIR/"

# Case 6: headless + unconfigured cwd + valid pointer → auto-select main-only
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
SCRATCH2="${TESTDIR}/scratch2"
mkdir -p "${SCRATCH2}"
( cd "${SCRATCH2}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "AutoMain" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "headless + valid pointer + unconfigured should auto-select main-only"
[[ -f "${SCRATCH2}/.wiki-mode" ]] || fail "auto-select main-only did not write .wiki-mode"
[[ "$(cat "${SCRATCH2}/.wiki-mode")" == "main-only" ]] || fail ".wiki-mode != main-only"

echo "PASS: bin/wiki capture body input + headless fallback + orphan preservation"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-wiki-capture-cli.sh`
Expected: FAIL — `bin/wiki capture` subcommand doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-wiki-capture-cli.sh
git commit -m "test(unit): add failing test for bin/wiki capture body+fallback+orphan"
```

---

### Task 12: Implement `scripts/wiki-orphan.sh` (helper for orphan preservation)

**Files:**
- Create: `scripts/wiki-orphan.sh`

- [ ] **Step 1: Write the orphan helper**

```bash
#!/bin/bash
# wiki-orphan.sh — preserve a capture body when bin/wiki capture must abort.
#
# Usage:
#   wiki-orphan.sh --title <title> --reason <reason> --body-file <path>
#
# Writes the body to ${WIKI_ORPHANS_DIR:-$HOME/.wiki-orphans}/<timestamp>-<slug>.md
# with a frontmatter explaining why the capture was aborted.
#
# Env overrides for testing:
#   WIKI_ORPHANS_DIR — orphan directory (default: ~/.wiki-orphans)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

ORPHANS_DIR="${WIKI_ORPHANS_DIR:-${HOME}/.wiki-orphans}"

title=""
reason=""
body_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) title="$2"; shift 2 ;;
    --reason) reason="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    *) echo >&2 "wiki-orphan: unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "${title}" && -n "${reason}" && -n "${body_file}" ]] \
  || { echo >&2 "wiki-orphan: --title --reason --body-file all required"; exit 1; }
[[ -f "${body_file}" ]] || { echo >&2 "wiki-orphan: body file missing: ${body_file}"; exit 1; }

mkdir -p "${ORPHANS_DIR}"

ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
slug="$(slugify "${title}")"
out="${ORPHANS_DIR}/${ts}-${slug}.md"

cat > "${out}" <<EOF
---
title: "${title}"
orphaned_at: "${ts}"
reason: "${reason}"
---

EOF
cat "${body_file}" >> "${out}"

echo "${out}"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/wiki-orphan.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/wiki-orphan.sh
git commit -m "feat(scripts): add wiki-orphan.sh body-preservation helper"
```

---

### Task 13: Implement `bin/wiki capture` subcommand

**Files:**
- Modify: `bin/wiki`

- [ ] **Step 1: Add the `capture` case to `bin/wiki`**

In `bin/wiki`, find the `case "${sub}" in` block and add a `capture` case BEFORE the `*)` default. The implementation:

```bash
  capture)
    # bin/wiki capture — single entry point for chat-driven captures.
    # Reads body from stdin OR --body-file, validates, runs resolver,
    # handles prompts/headless fallback, writes capture(s), spawns ingester(s).

    title=""
    kind=""
    suggested_action="create"
    body_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title) title="$2"; shift 2 ;;
        --kind) kind="$2"; shift 2 ;;
        --suggested-action) suggested_action="$2"; shift 2 ;;
        --body-file) body_file="$2"; shift 2 ;;
        *) echo >&2 "wiki capture: unknown arg: $1"; exit 1 ;;
      esac
    done
    [[ -n "${title}" ]] || { echo >&2 "wiki capture: --title required"; exit 1; }
    [[ -n "${kind}" ]] || { echo >&2 "wiki capture: --kind required (chat-only|chat-attached|raw-direct)"; exit 1; }

    # Body input: --body-file OR stdin (must be a pipe/file, not TTY)
    body_buf="$(mktemp)"
    trap 'rm -f "${body_buf}"' EXIT
    if [[ -n "${body_file}" ]]; then
      [[ -f "${body_file}" ]] || { echo >&2 "wiki capture: body file missing: ${body_file}"; exit 1; }
      cp "${body_file}" "${body_buf}"
    elif [[ ! -t 0 ]]; then
      cat > "${body_buf}"
    else
      echo >&2 "wiki capture: no body provided. Pipe on stdin or use --body-file <path>."
      exit 1
    fi
    body_size=$(wc -c < "${body_buf}")
    if [[ "${body_size}" -gt 262144 ]]; then
      echo >&2 "wiki capture: body is ${body_size} bytes (max 256 KB). Use raw-direct ingest: mv <file> <wiki>/inbox/ && wiki ingest-now."
      exit 1
    fi

    # Validate body against kind floor
    case "${kind}" in
      chat-only)      floor=1500 ;;
      chat-attached)  floor=1000 ;;
      raw-direct)     floor=0 ;;
      *) echo >&2 "wiki capture: unknown --kind '${kind}'"; exit 1 ;;
    esac
    if [[ "${body_size}" -lt "${floor}" ]]; then
      echo >&2 "wiki capture: body is ${body_size} bytes; floor for kind=${kind} is ${floor}. Expand the body."
      exit 1
    fi

    # Run resolver
    resolver_out="$(bash "${REPO_ROOT}/scripts/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0 || resolver_exit=$?

    # Headless detection: any of WIKI_CAPTURE / CLAUDE_HEADLESS=1 / no TTY+no CLAUDE_AGENT_INTERACTIVE / CLAUDE_AGENT_PARENT.
    is_headless=0
    if [[ -n "${WIKI_CAPTURE:-}" || "${CLAUDE_HEADLESS:-0}" == "1" || -n "${CLAUDE_AGENT_PARENT:-}" ]]; then
      is_headless=1
    elif [[ ! -t 0 && -z "${CLAUDE_AGENT_INTERACTIVE:-}" ]]; then
      is_headless=1
    fi

    case "${resolver_exit}" in
      0)
        # Success — proceed with returned wikis
        ;;
      10)
        # Pointer missing
        if [[ "${is_headless}" == 1 ]]; then
          if [[ -f "$(pwd)/.wiki-config" ]]; then
            # Cwd has its own config — proceed with cwd's wiki only,
            # if and only if fork_to_main is false. (true → exit 12 path.)
            if grep -q '^fork_to_main = true' "$(pwd)/.wiki-config"; then
              orphan="$(bash "${REPO_ROOT}/scripts/wiki-orphan.sh" \
                --title "${title}" \
                --reason "headless: cwd .wiki-config requests fork_to_main=true but pointer is missing" \
                --body-file "${body_buf}")"
              echo >&2 "wiki capture: aborted; body preserved at ${orphan}"
              exit 1
            fi
            # Re-run resolver: it will succeed on cwd alone now.
            resolver_out="$(bash "${REPO_ROOT}/scripts/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0 || true
          else
            orphan="$(bash "${REPO_ROOT}/scripts/wiki-orphan.sh" \
              --title "${title}" \
              --reason "headless: pointer missing AND cwd unconfigured" \
              --body-file "${body_buf}")"
            echo >&2 "wiki capture: aborted; body preserved at ${orphan}"
            exit 1
          fi
        else
          # Interactive: bootstrap pointer, then re-run capture
          bash "${REPO_ROOT}/scripts/wiki-init-main.sh"
          exec bash "${BASH_SOURCE[0]}" capture --title "${title}" --kind "${kind}" --suggested-action "${suggested_action}" --body-file "${body_buf}"
        fi
        ;;
      11)
        # Cwd unconfigured
        if [[ "${is_headless}" == 1 ]]; then
          # Read pointer to decide fallback
          ptr=$(cat "${WIKI_POINTER_FILE:-${HOME}/.wiki-pointer}" 2>/dev/null | tr -d '[:space:]')
          if [[ -z "${ptr}" || "${ptr}" == "none" ]]; then
            orphan="$(bash "${REPO_ROOT}/scripts/wiki-orphan.sh" \
              --title "${title}" \
              --reason "headless: cwd unconfigured AND pointer = none/missing" \
              --body-file "${body_buf}")"
            echo >&2 "wiki capture: aborted; body preserved at ${orphan}"
            exit 1
          fi
          # Auto-select main-only
          echo "main-only" > "$(pwd)/.wiki-mode"
          echo >&2 "wiki capture: headless auto-selected main-only for cwd"
          resolver_out="$(bash "${REPO_ROOT}/scripts/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0
        else
          # Interactive: prompt user for project | main | both
          # (Implementation: read from /dev/tty, persist via wiki-use.sh,
          # then re-run resolver.)
          echo
          echo "This directory isn't configured for the wiki yet. How should captures here flow?"
          echo "  1) project — create a project wiki at ./wiki/, captures stay local."
          echo "  2) main    — captures go to the main wiki (the default)."
          echo "  3) both    — fork: write the same capture into both wikis."
          echo
          read -r -p "Reply with 1, 2, or 3: " choice </dev/tty
          case "${choice}" in
            1) bash "${REPO_ROOT}/scripts/wiki-use.sh" project ;;
            2) bash "${REPO_ROOT}/scripts/wiki-use.sh" main ;;
            3) bash "${REPO_ROOT}/scripts/wiki-use.sh" both ;;
            *) echo >&2 "wiki capture: invalid choice '${choice}'; aborting"; exit 1 ;;
          esac
          resolver_out="$(bash "${REPO_ROOT}/scripts/wiki-resolve.sh" 2>/dev/null)" && resolver_exit=0
        fi
        ;;
      12|13|14)
        # Configuration error / conflict / half-built
        case "${resolver_exit}" in
          12) reason="resolver exit 12: cwd requires main wiki but pointer is none/missing" ;;
          13) reason="resolver exit 13: cwd has BOTH .wiki-config and .wiki-mode (conflict)" ;;
          14) reason="resolver exit 14: half-built wiki (cwd or pointer target missing required files)" ;;
        esac
        orphan="$(bash "${REPO_ROOT}/scripts/wiki-orphan.sh" \
          --title "${title}" \
          --reason "${reason}" \
          --body-file "${body_buf}")"
        echo >&2 "wiki capture: aborted; ${reason}; body preserved at ${orphan}"
        exit 1
        ;;
      *)
        echo >&2 "wiki capture: resolver returned unexpected exit ${resolver_exit}"
        exit 1
        ;;
    esac

    # At this point resolver_out has one or more target wiki paths (one per line).
    if [[ -z "${resolver_out}" ]]; then
      echo >&2 "wiki capture: resolver returned no targets despite exit 0"
      exit 1
    fi

    # Build frontmatter + body for each target wiki and spawn ingester
    ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
    slug="$(slugify "${title}")"
    fork_id="fk-$(date +%s)-$$"
    target_count=0
    while IFS= read -r target_wiki; do
      [[ -n "${target_wiki}" ]] || continue
      target_count=$((target_count + 1))
      capture_path="${target_wiki}/.wiki-pending/${ts}-${slug}.md"

      # Resolve evidence_type from kind
      case "${kind}" in
        chat-only)     evidence_type="conversation"; evidence="conversation" ;;
        chat-attached) evidence_type="mixed"; evidence="conversation" ;;  # caller may override later
        raw-direct)    evidence_type="file"; evidence="conversation" ;;   # not used by capture; raw-direct via inbox
      esac

      {
        echo "---"
        echo "title: \"${title}\""
        echo "evidence: \"${evidence}\""
        echo "evidence_type: \"${evidence_type}\""
        echo "capture_kind: \"${kind}\""
        echo "suggested_action: \"${suggested_action}\""
        echo "suggested_pages: []"
        echo "captured_at: \"${ts/-/-}\""  # ts is already ISO-friendly
        echo "captured_by: \"in-session-agent\""
        echo "propagated_from: null"
        echo "---"
        echo
        cat "${body_buf}"
      } > "${capture_path}"

      bash "${REPO_ROOT}/scripts/wiki-spawn-ingester.sh" "${target_wiki}" "${capture_path}" &
      disown 2>/dev/null || true
    done <<< "${resolver_out}"

    # Write fork-coordination record if multi-target
    if [[ "${target_count}" -gt 1 ]]; then
      forks_log="${HOME}/.wiki-forks.jsonl"
      mkdir -p "$(dirname "${forks_log}")"
      printf '{"fork_id":"%s","captured_at":"%s","title":"%s","wikis":%s}\n' \
        "${fork_id}" "${ts}" "${title}" \
        "$(echo "${resolver_out}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')" \
        >> "${forks_log}"
    fi

    echo "wiki capture: ${target_count} target(s) — ${title}"
    ;;
```

- [ ] **Step 2: Add `init-main`, `use`, and `ingest-now` subcommand stubs**

Add these cases too (to the same `case "${sub}" in` block, before `*)`):

```bash
  init-main)
    bash "${REPO_ROOT}/scripts/wiki-init-main.sh" "$@"
    ;;
  use)
    bash "${REPO_ROOT}/scripts/wiki-use.sh" "$@"
    ;;
  ingest-now)
    # Leg 3 implements this; placeholder for now
    if [[ -f "${REPO_ROOT}/scripts/wiki-ingest-now.sh" ]]; then
      bash "${REPO_ROOT}/scripts/wiki-ingest-now.sh" "$@"
    else
      echo >&2 "wiki ingest-now: not implemented (Leg 3 ships this)."
      exit 1
    fi
    ;;
```

- [ ] **Step 3: Update the `help` block to document the new subcommands**

Replace the existing `help|--help|-h)` case body with:

```bash
  help|--help|-h)
    cat <<EOF
usage: wiki <subcommand>

subcommands:
  capture        Write a chat-driven capture (the agent's canonical entry point)
                   wiki capture --title T --kind chat-only|chat-attached --suggested-action <act> [--body-file <path>]
                   Body via stdin (pipe) OR --body-file. Max 256 KB.
  ingest-now     Drift-scan + drain inbox/ on demand (Leg 3)
                   wiki ingest-now [<wiki-path>]
  use            Change per-cwd wiki mode
                   wiki use project|main|both
  init-main      Bootstrap ~/.wiki-pointer (interactive)
  status         Read-only health report
  doctor         Deep lint + fix (post-MVP)
  help           This message
EOF
    ;;
```

- [ ] **Step 4: Run the failing test**

Run: `bash tests/unit/test-wiki-capture-cli.sh`
Expected: PASS.

If it fails, common issues:

- The `evidence_type/evidence` mapping for `chat-attached` and `raw-direct` is a placeholder; if the test inspects evidence values, refine.
- Headless detection: if the test runs with `CLAUDE_HEADLESS=1` exported but the script's check sees something else, debug with `set -x` inside the case branch.
- The `${ts/-/-}` substitution is a no-op (placeholder); plain `${ts}` is fine.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/run-all.sh`
Expected: PASS — no regressions in existing tests.

- [ ] **Step 6: Commit**

```bash
git add bin/wiki
git commit -m "feat(bin/wiki): add capture, ingest-now, use, init-main subcommands"
```

---

### Task 14: Integration test — Leg 2 end-to-end

**Files:**
- Create: `tests/integration/test-leg2-end-to-end.sh`

- [ ] **Step 1: Write the integration test**

```bash
#!/bin/bash
# Integration test for Leg 2: bootstrap → per-cwd prompt → capture →
# ingester spawn (mocked). Three modes: project / main / both.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${MAIN}/.wiki-config"
rm -f "${MAIN}/.wiki-config.bak"

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
export WIKI_ORPHANS_DIR="${TESTDIR}/.wiki-orphans"
export CLAUDE_HEADLESS=1

BODY=$(printf 'Real chat-only body that easily exceeds the 1500-byte floor.\n%.0s' {1..40})

# Project mode: pre-configure cwd
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
( cd "${PROJ}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" project ) >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${PROJ}/wiki/.wiki-config"
rm -f "${PROJ}/wiki/.wiki-config.bak"
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "ProjTest" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "project mode capture failed"
ls "${PROJ}/wiki/.wiki-pending/" | grep -q '\.md$' || fail "project capture not in proj/wiki/.wiki-pending"
ls "${MAIN}/.wiki-pending/" | wc -l | grep -q '0' \
  || ! ls "${MAIN}/.wiki-pending/" | grep -q ProjTest \
  || fail "project mode leaked capture to main wiki"

# Both mode: pre-configure cwd with fork_to_main = true
BOTH="${TESTDIR}/both"
mkdir -p "${BOTH}"
( cd "${BOTH}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" both ) >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${BOTH}/wiki/.wiki-config"
rm -f "${BOTH}/wiki/.wiki-config.bak"
( cd "${BOTH}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "BothTest" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "both mode capture failed"
ls "${BOTH}/wiki/.wiki-pending/" | grep -q BothTest || fail "both mode: project capture missing"
ls "${MAIN}/.wiki-pending/" | grep -q BothTest || fail "both mode: main capture missing"
[[ -f "${HOME}/.wiki-forks.jsonl" ]] || fail "both mode: fork-coordination record missing"

# Main-only mode: pre-configure cwd with .wiki-mode
MAIN_ONLY="${TESTDIR}/main-only"
mkdir -p "${MAIN_ONLY}"
( cd "${MAIN_ONLY}" && bash "${REPO_ROOT}/scripts/wiki-use.sh" main ) >/dev/null
( cd "${MAIN_ONLY}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "MainOnlyTest" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "main-only capture failed"
ls "${MAIN}/.wiki-pending/" | grep -q MainOnlyTest || fail "main-only: capture not in main"

echo "PASS: Leg 2 end-to-end (project / main / both modes)"
```

- [ ] **Step 2: Run the integration test**

Run: `bash tests/integration/test-leg2-end-to-end.sh`
Expected: PASS.

- [ ] **Step 3: Run the full test suite**

Run: `bash tests/run-all.sh`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test-leg2-end-to-end.sh
git commit -m "test(integration): Leg 2 end-to-end (project/main/both, headless fallback)"
```

---

## Self-review checklist

Before declaring Leg 2 done:

- [ ] `wiki-resolve.sh` returns 0 with target wikis on stdout, OR exits 10/11/12/13/14 per the spec's pseudocode.
- [ ] `wiki-init-main.sh` silent-migrates if exactly one main candidate exists; prompts otherwise; "none" path works.
- [ ] `wiki-use.sh` is idempotent and refuses invalid combinations (`use main` inside a wiki; `use both` with no main).
- [ ] `wiki-init.sh` accepts standalone project mode (no main arg), creates `inbox/` and `.raw-staging/`, writes README idempotently.
- [ ] `bin/wiki capture` reads body from stdin OR `--body-file`; rejects missing/oversized bodies; validates against kind floor.
- [ ] Headless contexts: orphan-preserve when no valid target; auto-select main-only when pointer is valid + cwd unconfigured.
- [ ] Both-mode: writes capture into BOTH wikis; logs to `~/.wiki-forks.jsonl`.
- [ ] Resolver `fork_to_main = true` + pointer = none → exit 12 (not silent fallback).
- [ ] Half-built wiki (cwd or pointer target missing schema/index/.wiki-pending) → exit 14.
- [ ] `bash tests/run-all.sh` passes; no regressions.
- [ ] RED scenario committed before script changes.

## Verification gate

After Leg 2 ships, the spec's exit criteria for Leg 2 hold:

- First capture in unconfigured cwd (interactive) prompts; choice persisted.
- `wiki use project|main|both` flips the persisted choice idempotently.
- Conflicts (`.wiki-config` + `.wiki-mode`) → exit 13; user-visible reconciliation.
- Half-built wiki at cwd or pointer → exit 14.
- Headless fallback never silently sets pointer = none; never loses a body.

## Next leg

Leg 3 plan: `docs/superpowers/plans/2026-05-06-karpathy-wiki-v2.4-leg3-raw-direct.md` — adds the `inbox/` queue + `wiki ingest-now` + `raw/` write-staging discipline + recovery. Depends on this leg's resolver.
