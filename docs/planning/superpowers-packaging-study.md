# Superpowers Packaging Layer Study

**Subject:** `obra/superpowers` at commit `8a5edab282632443`, release **v5.0.7** (2026-03-31), 164k stars.
**Primary source:** `/Users/lukaszmaj/dev/bigbrain/research/obra-superpowers-8a5edab282632443.txt` (22,088 lines) plus live GitHub API via `gh`.
**Scope:** Packaging and distribution layer **outside** `skills/`. Cross-platform install surfaces (AGENTS.md / CLAUDE.md / GEMINI.md, `.claude-plugin/`, `.codex/`, `.cursor-plugin/`, `.opencode/`, Gemini extension manifest), hooks, install scripts, tests, versioning, release management.
**Goal:** Inform the packaging strategy for our `karpathy-wiki` v2 skill (Claude Code MVP, cross-platform later).

---

## Section 1 — File-by-file audit at repo root

Directory listing of the live `obra/superpowers` repo root (`gh api repos/obra/superpowers/contents/`):

```
AGENTS.md              (symlink → CLAUDE.md, git mode 120000)
CLAUDE.md              (canonical contributor guidelines, 6,490 bytes)
CODE_OF_CONDUCT.md     (Contributor Covenant 2.x)
GEMINI.md              (two-line @imports file)
LICENSE                (MIT)
README.md              (user-facing install + overview)
RELEASE-NOTES.md       (chronological changelog per version)
gemini-extension.json  (4-field Gemini extension manifest)
package.json           (npm shell: name, version, "type": "module", main)
.version-bump.json     (drives cross-manifest version sync)
.gitattributes         (LF line endings for .sh, .cmd, .md, .json, .js)
.gitignore             (.worktrees/, .private-journal/, .claude/, .DS_Store, node_modules/, inspo, triage/)
.claude-plugin/        (Claude Code plugin + marketplace manifests)
.codex/                (Codex INSTALL.md only — no manifest)
.cursor-plugin/        (Cursor plugin.json)
.opencode/             (INSTALL.md + plugins/superpowers.js)
.github/               (ISSUE_TEMPLATE/, PULL_REQUEST_TEMPLATE.md, FUNDING.yml — NO workflows/)
agents/                (repo-level agents, 1 file: code-reviewer.md)
commands/              (3 deprecated slash commands)
docs/                  (README.codex.md, README.opencode.md, testing.md, plans/, superpowers/, windows/polyglot-hooks.md)
hooks/                 (hooks.json, hooks-cursor.json, run-hook.cmd, session-start)
scripts/               (bump-version.sh, sync-to-codex-plugin.sh)
skills/                (14 skills — NOT the subject of this study)
tests/                 (brainstorm-server/, claude-code/, explicit-skill-requests/, opencode/, skill-triggering/, subagent-driven-dev/)
```

Roles:

- **`AGENTS.md → CLAUDE.md` symlink:** vendor-neutral entry point. Tools that read `AGENTS.md` (Codex CLI, now supported by many agentic tools) transparently get CLAUDE.md content. `gh api repos/obra/superpowers/git/trees/HEAD` confirms `"mode":"120000"` for AGENTS.md and `"mode":"100644"` for CLAUDE.md, with different SHAs (the AGENTS.md blob stores the literal string `CLAUDE.md`, not the content).
- **`CLAUDE.md`:** despite the filename, this is **contributor guidelines for AI agents submitting PRs**, not a skill-level context file. It opens with "If You Are an AI Agent / Stop. Read this section before doing anything." and spends 90 lines on the 94% PR rejection rate, prohibited PR types, and the PR template. It is not a routine memory/context file — it's a gate.
- **`GEMINI.md`:** two lines, pure `@` imports (Gemini's file-inclusion syntax): `@./skills/using-superpowers/SKILL.md` and `@./skills/using-superpowers/references/gemini-tools.md`. Uses Gemini CLI's context injection to achieve the SKILL.md-loading effect that Claude Code gets natively.
- **`README.md`:** user-facing. Install instructions for 7 platforms (Claude Code Official marketplace, Claude Code Superpowers marketplace, OpenAI Codex CLI, OpenAI Codex App, Cursor, OpenCode, Copilot CLI, Gemini CLI).
- **`gemini-extension.json`:** minimal Gemini extension manifest (see Section 3).
- **`package.json`:** four-field npm manifest — `name`, `version`, `"type": "module"`, `"main": ".opencode/plugins/superpowers.js"`. Exists primarily so OpenCode can install via `git+https://...` (PR #753, v5.0.4: "Added package.json so OpenCode can install superpowers as an npm package from git").
- **`.version-bump.json`:** declares five files whose version field is kept in lockstep by `scripts/bump-version.sh`.
- **`.claude-plugin/`:** Claude Code plugin manifest (`plugin.json`) + marketplace manifest (`marketplace.json`).
- **`.codex/`:** contains **only `INSTALL.md`**, no manifest — Codex discovers skills natively via `~/.agents/skills/` symlink (see Section 4).
- **`.cursor-plugin/`:** Cursor plugin manifest (`plugin.json`) only.
- **`.opencode/`:** `INSTALL.md` + `plugins/superpowers.js` — a JavaScript plugin that auto-registers the skills directory at startup (no manifest needed for OpenCode).
- **`.github/`:** templates + funding link only. **No `workflows/` directory exists** (confirmed: `gh api repos/obra/superpowers/contents/.github` returns only `FUNDING.yml`, `ISSUE_TEMPLATE/`, `PULL_REQUEST_TEMPLATE.md`). No CI runs on PRs.
- **`agents/`:** one file, `code-reviewer.md`. Claude Code agent definition with elaborate `<example>` tags. Also exposed to Cursor via `.cursor-plugin/plugin.json` `"agents": "./agents/"`.
- **`commands/`:** three slash-command shims (`brainstorm.md`, `execute-plan.md`, `write-plan.md`), each just a deprecation notice telling the agent to use the skill. Exposed to Cursor via `"commands": "./commands/"`.
- **`hooks/`:** four files — `hooks.json` (Claude Code format), `hooks-cursor.json` (Cursor camelCase format), `run-hook.cmd` (polyglot wrapper), `session-start` (extensionless bash script). See Section 5.
- **`scripts/`:** `bump-version.sh` (in-tree version sync) and `sync-to-codex-plugin.sh` (rsync-based mirror to Codex plugins monorepo). No `install.sh` — each platform has its own install documented in per-platform `INSTALL.md` files.
- **`tests/`:** Six test suites, all shell-based, no CI integration. See Section 6.

---

## Section 2 — The AGENTS.md + vendor-wrapper pattern

### 2.1 The pattern, in one diagram

```
AGENTS.md  ─symlink→  CLAUDE.md   (the canonical file)
                          │
                          └── agent-agnostic contributor guidelines
GEMINI.md                   (separate file)
  ├── @./skills/using-superpowers/SKILL.md
  └── @./skills/using-superpowers/references/gemini-tools.md
```

### 2.2 What each file contains

**`CLAUDE.md`** (the canonical target) is titled `# Superpowers — Contributor Guidelines`. Key sections, verbatim:

> **If You Are an AI Agent**
> Stop. Read this section before doing anything.
>
> This repo has a 94% PR rejection rate. Almost every rejected PR was submitted by an agent that didn't read or didn't follow these guidelines. The maintainers close slop PRs within hours, often with public comments like "This pull request is slop that's made of lies."
>
> **Your job is to protect your human partner from that outcome.**

It then enumerates the PR preflight:

> Before you open a PR against this repo, you MUST:
>
> 1. **Read the entire PR template** at `.github/PULL_REQUEST_TEMPLATE.md` and fill in every section with real, specific answers. Not summaries. Not placeholders.
> 2. **Search for existing PRs** — open AND closed — that address the same problem. If duplicates exist, STOP and tell your human partner. Do not open another duplicate.
> 3. **Verify this is a real problem.** …
> 4. **Confirm the change belongs in core.** …
> 5. **Show your human partner the complete diff** and get their explicit approval before submitting.

The rest lists explicit rejection categories ("Third-party dependencies", "'Compliance' changes to skills", "Project-specific or personal configuration", "Bulk or spray-and-pray PRs", "Speculative or theoretical fixes", "Domain-specific skills", "Fork-specific changes", "Fabricated content", "Bundled unrelated changes"). Then "Skill Changes Require Evaluation" and "Understand the Project Before Contributing".

**AGENTS.md** is identical content — by virtue of being a git symlink (mode 120000, blob contents: the literal string `CLAUDE.md`). The GitHub REST API (`/contents/AGENTS.md`) resolves the symlink and returns the target's bytes with the wrong SHA; the git tree API exposes it correctly:

```json
{"mode":"120000","path":"AGENTS.md","sha":"681311eb9cf453d0faddf3aacaec7357e97ba8e9","type":"blob"}
{"mode":"100644","path":"CLAUDE.md","sha":"3a50e0fd6388843c50ea1d7b3001819591783563","type":"blob"}
```

**GEMINI.md** (verbatim, entire file):

```
@./skills/using-superpowers/SKILL.md
@./skills/using-superpowers/references/gemini-tools.md
```

Gemini CLI treats `@path` as a file-include. The manifest (`gemini-extension.json`) names this file as the `contextFileName`, so Gemini loads it fully at startup and, via the `@` imports, injects the `using-superpowers` skill body + Gemini-specific tool-name mapping as always-on context. This is how Gemini (which doesn't support Agent Skills) gets equivalent behaviour.

### 2.3 Who reads AGENTS.md

From `skills/using-superpowers/SKILL.md` (line 12741 of the bundle), superpowers itself documents the pattern:

> 1. **User's explicit instructions** (CLAUDE.md, GEMINI.md, AGENTS.md, direct requests) — highest priority
> …
> If CLAUDE.md, GEMINI.md, or AGENTS.md says "don't use TDD" and a skill says "always use TDD," follow the user's instructions. The user is in control.

Tools that read `AGENTS.md` by default (documented or de-facto in 2025-2026): **Codex CLI** (treats `AGENTS.md` as repo context at load), **OpenCode** (honoured alongside `.opencode/agents/`), **Cursor** (via its plugin system's "agents" path), and increasingly many IDEs that follow the emerging "agents.md" convention for vendor-neutral agent instructions. Claude Code reads **CLAUDE.md**; the symlink bridges them. Gemini CLI reads only what `contextFileName` points at in `gemini-extension.json` — hence the separate `GEMINI.md`.

### 2.4 Source of truth vs wrappers

In superpowers the structure is:

- **`CLAUDE.md`** = source of truth (6,490 bytes, hand-authored contributor guidelines)
- **`AGENTS.md`** = thin wrapper (a 9-byte symlink — the literal string `CLAUDE.md`)
- **`GEMINI.md`** = thin wrapper (two `@` imports, 77 bytes; totally different content target — it loads the `using-superpowers` SKILL body, not the contributor guidelines)

This is not "one source with shims" — it's **two distinct documents with different audiences**. CLAUDE.md/AGENTS.md targets contributors (anyone editing the repo); GEMINI.md targets end-users (runtime skill activation for Gemini CLI users). The symlink only exists because CLAUDE.md and AGENTS.md happen to serve the same role on different tools.

There is **no CLAUDE.md that imports AGENTS.md** (or vice versa). The directionality in the common "CLAUDE.md is a thin wrapper over AGENTS.md" pattern is **inverted here**: AGENTS.md is the thin wrapper.

---

## Section 3 — Plugin manifest formats per platform

### 3.1 Claude Code — `.claude-plugin/`

Two files. `plugin.json`:

```json
{
  "name": "superpowers",
  "description": "Core skills library for Claude Code: TDD, debugging, collaboration patterns, and proven techniques",
  "version": "5.0.7",
  "author": { "name": "Jesse Vincent", "email": "jesse@fsck.com" },
  "homepage": "https://github.com/obra/superpowers",
  "repository": "https://github.com/obra/superpowers",
  "license": "MIT",
  "keywords": ["skills", "tdd", "debugging", "collaboration", "best-practices", "workflows"]
}
```

`marketplace.json` (enables the repo itself to be installed as a marketplace via `/plugin marketplace add obra/superpowers-marketplace`):

```json
{
  "name": "superpowers-dev",
  "description": "Development marketplace for Superpowers core skills library",
  "owner": { "name": "Jesse Vincent", "email": "jesse@fsck.com" },
  "plugins": [
    {
      "name": "superpowers",
      "description": "Core skills library for Claude Code: …",
      "version": "5.0.7",
      "source": "./",
      "author": { "name": "Jesse Vincent", "email": "jesse@fsck.com" }
    }
  ]
}
```

Note: neither file declares skills, hooks, commands, or agents — Claude Code **auto-discovers** `./skills/`, `./hooks/hooks.json`, `./commands/`, `./agents/` by convention once the plugin is installed. This is the lightest manifest of the four platforms.

### 3.2 Codex — `.codex/INSTALL.md` only (no JSON manifest in repo)

`.codex/` contains a single file — `INSTALL.md`. Key verbatim excerpt:

```bash
git clone https://github.com/obra/superpowers.git ~/.codex/superpowers
mkdir -p ~/.agents/skills
ln -s ~/.codex/superpowers/skills ~/.agents/skills/superpowers
```

Codex has no in-repo manifest because it discovers skills natively by scanning `~/.agents/skills/`. The symlink makes `skills/` visible in the scan path. A Codex-side plugin manifest **does exist** but is generated at sync time by `scripts/sync-to-codex-plugin.sh` and committed to `prime-radiant-inc/openai-codex-plugins` (separate fork), not stored in the main repo. That generated manifest (from `sync-to-codex-plugin.sh`) looks like:

```json
{
  "name": "superpowers",
  "version": "$version",
  "description": "…",
  "author": { "name": "Jesse Vincent", "email": "jesse@fsck.com", "url": "https://github.com/obra" },
  "skills": "./skills/",
  "interface": {
    "displayName": "Superpowers",
    "shortDescription": "Planning, TDD, debugging, and delivery workflows for coding agents",
    "longDescription": "…",
    "developerName": "Jesse Vincent",
    "category": "Coding",
    "capabilities": ["Interactive", "Read", "Write"],
    "defaultPrompt": [
      "I've got an idea for something I'd like to build.",
      "Let's add a feature to this project."
    ],
    "brandColor": "#F59E0B",
    "composerIcon": "./assets/superpowers-small.svg",
    "logo": "./assets/app-icon.png"
  }
}
```

The `interface` block is the Codex App overlay (brand, icon, suggested prompts) required to appear in the Codex App plugin gallery. It's managed outside this repo because Codex's install surface is a curated fork.

### 3.3 Cursor — `.cursor-plugin/plugin.json`

One file. Unlike Claude Code's minimal manifest, Cursor declares every artifact path explicitly:

```json
{
  "name": "superpowers",
  "displayName": "Superpowers",
  "description": "Core skills library: TDD, debugging, collaboration patterns, and proven techniques",
  "version": "5.0.7",
  "author": { "name": "Jesse Vincent", "email": "jesse@fsck.com" },
  "homepage": "https://github.com/obra/superpowers",
  "repository": "https://github.com/obra/superpowers",
  "license": "MIT",
  "keywords": ["skills", "tdd", "debugging", "collaboration", "best-practices", "workflows"],
  "skills": "./skills/",
  "agents": "./agents/",
  "commands": "./commands/",
  "hooks": "./hooks/hooks-cursor.json"
}
```

**Cursor is the only platform that needs a separate hooks file** (`hooks-cursor.json`, camelCase event names, `version: 1`). Cursor also registers commands + agents from the repo-level `commands/` and `agents/` directories — Claude Code auto-discovers them from the same dirs without needing them declared.

### 3.4 OpenCode — JS plugin, no manifest

`.opencode/plugins/superpowers.js` is an ES module that does two things at load time:

1. **Injects bootstrap context** via `experimental.chat.messages.transform` (prepends a user message to the first turn with the `using-superpowers` SKILL body wrapped in `<EXTREMELY_IMPORTANT>…</EXTREMELY_IMPORTANT>`).
2. **Registers the skills directory** via the `config` hook so OpenCode finds `skills/` without manual symlinks or `skills.paths` config.

Key excerpt:

```javascript
export const SuperpowersPlugin = async ({ client, directory }) => {
  const homeDir = os.homedir();
  const superpowersSkillsDir = path.resolve(__dirname, '../../skills');

  return {
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(superpowersSkillsDir)) {
        config.skills.paths.push(superpowersSkillsDir);
      }
    },

    'experimental.chat.messages.transform': async (_input, output) => {
      const bootstrap = getBootstrapContent();
      if (!bootstrap || !output.messages.length) return;
      const firstUser = output.messages.find(m => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;
      if (firstUser.parts.some(p => p.type === 'text' && p.text.includes('EXTREMELY_IMPORTANT'))) return;
      const ref = firstUser.parts[0];
      firstUser.parts.unshift({ ...ref, type: 'text', text: bootstrap });
    }
  };
};
```

The comments explain why: *"Using a user message instead of a system message avoids: 1. Token bloat from system messages repeated every turn (#750). 2. Multiple system messages breaking Qwen and other models (#894)."*

OpenCode install is then trivial — `opencode.json` gets one line: `"plugin": ["superpowers@git+https://github.com/obra/superpowers.git"]`. `package.json`'s `"main": ".opencode/plugins/superpowers.js"` points Bun at the plugin when OpenCode installs the npm-style dependency from git.

### 3.5 Gemini — `gemini-extension.json`

Four fields, entire file:

```json
{
  "name": "superpowers",
  "description": "Core skills library: TDD, debugging, collaboration patterns, and proven techniques",
  "version": "5.0.7",
  "contextFileName": "GEMINI.md"
}
```

`contextFileName` is the pointer to the always-on context file. Install is a single CLI command: `gemini extensions install https://github.com/obra/superpowers`.

### 3.6 Summary matrix: who declares what

| Platform | Manifest file | Skills declared? | Hooks declared? | Commands declared? | Agents declared? |
|---|---|---|---|---|---|
| Claude Code | `.claude-plugin/plugin.json` | No (auto-discovered) | No (auto-discovers `hooks/hooks.json`) | No (auto) | No (auto) |
| Codex | none in-repo; gen'd `.codex-plugin/plugin.json` in a separate fork | `"skills": "./skills/"` | none | none | none |
| Cursor | `.cursor-plugin/plugin.json` | `"skills": "./skills/"` | `"hooks": "./hooks/hooks-cursor.json"` | `"commands": "./commands/"` | `"agents": "./agents/"` |
| OpenCode | code — `.opencode/plugins/superpowers.js` | programmatic (`config.skills.paths.push(...)`) | none (no OpenCode hook API) | none | none |
| Gemini | `gemini-extension.json` | none | none | none (commands via `commands/*.toml` not present here) | none |

---

## Section 4 — Install / uninstall / bootstrap flow

### 4.1 Per-platform install (from README verbatim)

**Claude Code — official marketplace:**
```bash
/plugin install superpowers@claude-plugins-official
```

**Claude Code — Superpowers marketplace:**
```bash
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

**Codex CLI (in-app):**
```bash
/plugins
superpowers
```
(search + Install Plugin button)

**Codex App:** GUI — click Plugins in sidebar, click `+` next to Superpowers.

**Cursor:**
```
/add-plugin superpowers
```

**OpenCode** (in `opencode.json`):
```json
{ "plugin": ["superpowers@git+https://github.com/obra/superpowers.git"] }
```

**Copilot CLI:**
```bash
copilot plugin marketplace add obra/superpowers-marketplace
copilot plugin install superpowers@superpowers-marketplace
```

**Gemini CLI:**
```bash
gemini extensions install https://github.com/obra/superpowers
```

### 4.2 Manual installation for Codex (from `.codex/INSTALL.md` and `docs/README.codex.md`)

Unix:
```bash
git clone https://github.com/obra/superpowers.git ~/.codex/superpowers
mkdir -p ~/.agents/skills
ln -s ~/.codex/superpowers/skills ~/.agents/skills/superpowers
```

Windows (junction instead of symlink):
```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.agents\skills"
cmd /c mklink /J "$env:USERPROFILE\.agents\skills\superpowers" "$env:USERPROFILE\.codex\superpowers\skills"
```

Then, for subagent-using skills:
```toml
[features]
multi_agent = true
```

**How it registers:** a symlink from `~/.agents/skills/superpowers` to the cloned `skills/` directory. Codex scans `~/.agents/skills/` at startup. Nothing else to do.

### 4.3 Uninstall

Codex:
```bash
rm ~/.agents/skills/superpowers
# optional: rm -rf ~/.codex/superpowers
```

OpenCode (from `docs/README.opencode.md`, the migration section):
```bash
rm -f ~/.config/opencode/plugins/superpowers.js
rm -rf ~/.config/opencode/skills/superpowers
rm -rf ~/.config/opencode/superpowers
# remove the superpowers line from opencode.json
```

Claude Code / Cursor / Gemini: uninstall is via platform command (`/plugin remove`, `gemini extensions uninstall superpowers`). No in-repo uninstall script.

### 4.4 Platform detection

Superpowers **does not detect platforms at install time**. Each platform's install command is invoked by the user, and the install mechanism touches only that platform's config surface. There is no `install.sh` that probes the environment.

The detection that *does* exist is runtime: the `hooks/session-start` script detects platforms via environment variables at hook-fire time, to emit the right JSON output shape (see Section 5).

### 4.5 Bootstrap mechanism on session start

Each platform independently injects the `using-superpowers` SKILL body into every session's context at startup:

- **Claude Code:** SessionStart hook runs `hooks/session-start`, which emits `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "<EXTREMELY_IMPORTANT>…using-superpowers body…</EXTREMELY_IMPORTANT>"}}`.
- **Cursor:** `hooks-cursor.json` runs the same `hooks/session-start` script; it emits `{"additional_context": "…"}` (snake_case).
- **Copilot CLI:** same script; emits `{"additionalContext": "…"}` (SDK standard, top-level).
- **OpenCode:** `.opencode/plugins/superpowers.js` does it via `experimental.chat.messages.transform`, prepending to the first user message.
- **Gemini CLI:** `GEMINI.md` @imports `using-superpowers/SKILL.md` — always-on static inclusion, no hook.
- **Codex CLI:** nothing. Codex doesn't inject context — users have to discover the skill via description match or explicit `/skills` lookup.

This is the single most load-bearing piece of cross-platform plumbing: one `session-start` script that branches on env vars, plus one JS plugin for OpenCode, plus one static `@import` for Gemini.

---

## Section 5 — Where hooks actually live (correcting prior research)

### 5.1 The bundled-repo answer

Everything is **repo-level**, in `hooks/`. There are no per-skill `hooks.json` files anywhere in the tree. The skills themselves are pure prose; hook registration is outside them.

```
hooks/
├── hooks.json         # Claude Code hook manifest (hookEventName: "SessionStart")
├── hooks-cursor.json  # Cursor hook manifest (sessionStart, version: 1)
├── run-hook.cmd       # Polyglot .cmd/.sh wrapper
└── session-start      # Extensionless bash script (the actual hook logic)
```

**Claude Code** — `hooks/hooks.json` verbatim:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start",
            "async": false
          }
        ]
      }
    ]
  }
}
```

**Cursor** — `hooks/hooks-cursor.json` verbatim:

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "command": "./hooks/session-start" }
    ]
  }
}
```

Observations:
- **Exactly one hook event:** SessionStart. No Stop, no PreToolUse, no PostToolUse, no SubagentStop.
- **`matcher: "startup|clear|compact"`** on Claude Code — a deliberate narrowing. `resume` and `submit-prompt` do not fire. Per v5.0.3 release notes: *"Stop firing SessionStart hook on `--resume` — the startup hook was re-injecting context on resumed sessions, which already have the context in their conversation history."*
- **`type: command`** — shell, not LLM. No `type: prompt` anywhere.
- Cursor's format is different enough (camelCase event names, `version: 1`, no nested `hooks[]` array, no matcher) that a separate file is required.

### 5.2 The polyglot wrapper — why and how

`hooks/run-hook.cmd` is a single file that is **valid syntax in both CMD.exe and bash**. From the bundle, the file in full is only 50 lines. The key trick (verbatim from the file):

```cmd
: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for hook scripts.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).
REM
REM Hook scripts use extensionless filenames (e.g. "session-start" not
REM "session-start.sh") so Claude Code's Windows auto-detection -- which
REM prepends "bash" to any command containing .sh -- doesn't interfere.

if "%~1"=="" ( echo run-hook.cmd: missing script name >&2 & exit /b 1 )
set "HOOK_DIR=%~dp0"

if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
REM No bash found - exit silently rather than error
exit /b 0
CMDBLOCK

# Unix: run the named script directly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

Mechanism:
- **On Windows CMD:** `:` is a label, `<< 'CMDBLOCK'` is ignored. The `@echo off`…`exit /b`…`CMDBLOCK` block runs as CMD. The unix tail is never reached.
- **On Unix bash:** `:` is a no-op builtin; `<< 'CMDBLOCK'` starts a heredoc. Everything to `CMDBLOCK` is consumed by the heredoc and discarded. The tail starting at `# Unix:` runs.

This lets `hooks.json` point at a single file path — `run-hook.cmd` — that works on Windows, macOS, and Linux. It passes the first argument (`session-start`) as the actual script to run. The docs at `docs/windows/polyglot-hooks.md` (~215 lines) explain the technique in full, including the `.sh`-extension gotcha: Claude Code on Windows auto-prepends `bash` when a command contains `.sh`, causing double-invocation. Naming the inner script `session-start` (no extension) avoids it.

The `.gitattributes` file (verbatim) enforces LF line endings on this polyglot file:

```
*.sh text eol=lf
hooks/session-start text eol=lf
*.cmd text eol=lf
*.md text eol=lf
*.json text eol=lf
*.js text eol=lf
*.mjs text eol=lf
*.ts text eol=lf
*.png binary
*.jpg binary
*.gif binary
```

Windows Git can't auto-convert to CRLF because CRLF would break bash's parsing of the polyglot file.

### 5.3 What `session-start` actually does

Verbatim excerpt:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check for legacy skills directory — warning if it exists
# (omitted — builds warning_message string)

using_superpowers_content=$(cat "${PLUGIN_ROOT}/skills/using-superpowers/SKILL.md" 2>&1 || …)

# JSON-escape via bash parameter substitution (one C-level pass each)
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

using_superpowers_escaped=$(escape_for_json "$using_superpowers_content")
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill…**\n\n${using_superpowers_escaped}\n…\n</EXTREMELY_IMPORTANT>"

# Platform-specific JSON output
if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
  printf '{\n  "additional_context": "%s"\n}\n' "$session_context"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -z "${COPILOT_CLI:-}" ]; then
  printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$session_context"
else
  # Copilot CLI or SDK-standard
  printf '{\n  "additionalContext": "%s"\n}\n' "$session_context"
fi
exit 0
```

Three observations that contradict earlier assumptions in our prior research notes:

1. **The hook always injects `using-superpowers` SKILL.md content**. It's not conditional on anything. Every SessionStart fires this injection — which is exactly what issue #1220 measured at ~17.8k tokens across 13 firings (startup/clear/compact). This is the cost the `matcher` narrowing reduces but doesn't eliminate.
2. **No Stop hook exists.** Prior research ("our first superpowers research found one `SessionStart` hook") is correct — SessionStart is the only event. No PostToolUse, no Stop, no sub-agent hooks.
3. **The hook emits static context**, never LLM-reasoned output. `type: prompt` is not used anywhere.

### 5.4 The `.gitattributes` polyglot wrapper connection

The polyglot trick works only if line endings are LF. If git auto-converts `run-hook.cmd` to CRLF on checkout to Windows (the default with `core.autocrlf=true`), the bash heredoc delimiter `CMDBLOCK\r\n` doesn't match `CMDBLOCK\n`, and bash reads past the heredoc into the CMD block. `.gitattributes` nails every text file to LF to prevent this.

### 5.5 Summary — where hooks live

| Platform | Hook registration | Hook script |
|---|---|---|
| Claude Code | `hooks/hooks.json` (auto-discovered) | `hooks/run-hook.cmd` → `hooks/session-start` |
| Cursor | `hooks/hooks-cursor.json` (declared in `.cursor-plugin/plugin.json`) | same `hooks/session-start` |
| Copilot CLI | uses Claude Code's `hooks/hooks.json` format (same session-start hook) | same script, different env-var branch |
| OpenCode | no hook system; logic in `.opencode/plugins/superpowers.js` | n/a |
| Gemini | no hooks; always-on context via `GEMINI.md` | n/a |
| Codex | no session-start injection of any kind | n/a |

---

## Section 6 — Testing and release infrastructure

### 6.1 Tests — six subdirectories

```
tests/
├── brainstorm-server/           Node tests for the brainstorming skill's companion server
├── claude-code/                 Integration tests for skills via headless `claude -p`
├── explicit-skill-requests/     Multi-turn/Haiku tests for skill triggering
├── opencode/                    OpenCode plugin loading + tool tests (bash, no Node)
├── skill-triggering/            Prompts for each skill to verify description matches
└── subagent-driven-dev/         End-to-end Go + Svelte demo plans exercised by subagent-driven-development
```

**`tests/claude-code/`** — bash-driven. `test-helpers.sh` defines a `run_claude` helper:

```bash
# run-skill-tests.sh --integration → runs a real `claude -p` session
# Verifies skill invocation via grep on the session transcript JSONL
if grep -q '"name":"Skill".*"skill":"your-skill-name"' "$SESSION_FILE"; then
    echo "[PASS] Skill was invoked"
fi
```

Tests run the real Claude Code CLI in headless mode, parse the JSONL transcript from `~/.claude/projects/...`, and assert on presence/order of skill invocations, TodoWrite calls, and Task dispatches. `analyze-token-usage.py` breaks cost down by subagent.

**`tests/opencode/`** — bash setup script creates an isolated `$HOME`, copies the skills dir and plugin file, creates symlinks, and writes two test skills (`PERSONAL_SKILL_MARKER_12345`, `PROJECT_SKILL_MARKER_67890`) to verify priority resolution. Verbatim from `setup.sh`:

```bash
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
export OPENCODE_CONFIG_DIR="$TEST_HOME/.config/opencode"

SUPERPOWERS_DIR="$OPENCODE_CONFIG_DIR/superpowers"

mkdir -p "$SUPERPOWERS_DIR"
cp -r "$REPO_ROOT/skills" "$SUPERPOWERS_DIR/"
mkdir -p "$(dirname "$SUPERPOWERS_PLUGIN_FILE")"
cp "$REPO_ROOT/.opencode/plugins/superpowers.js" "$SUPERPOWERS_PLUGIN_FILE"
mkdir -p "$OPENCODE_CONFIG_DIR/plugins"
ln -sf "$SUPERPOWERS_PLUGIN_FILE" "$OPENCODE_CONFIG_DIR/plugins/superpowers.js"
```

This is the only per-platform install test. Claude Code tests run against the user's installed plugin; Cursor/Codex/Gemini have no per-platform install tests at all.

**`tests/brainstorm-server/`** — Node tests (`package.json` at `tests/brainstorm-server/package.json`) for the WS server shipped with `skills/brainstorming/`. Includes a `windows-lifecycle.test.sh` for the Windows path edge cases.

### 6.2 No CI workflows

`gh api repos/obra/superpowers/contents/.github` returns `FUNDING.yml`, `ISSUE_TEMPLATE/`, `PULL_REQUEST_TEMPLATE.md` — no `workflows/`. Tests run locally; there is no GitHub Actions pipeline.

### 6.3 Versioning — `.version-bump.json` + `scripts/bump-version.sh`

`.version-bump.json` declares five files to keep in lockstep:

```json
{
  "files": [
    { "path": "package.json", "field": "version" },
    { "path": ".claude-plugin/plugin.json", "field": "version" },
    { "path": ".cursor-plugin/plugin.json", "field": "version" },
    { "path": ".claude-plugin/marketplace.json", "field": "plugins.0.version" },
    { "path": "gemini-extension.json", "field": "version" }
  ],
  "audit": {
    "exclude": ["CHANGELOG.md", "RELEASE-NOTES.md", "node_modules", ".git", ".version-bump.json", "scripts/bump-version.sh"]
  }
}
```

`scripts/bump-version.sh` has three modes:
- `bump-version.sh 5.0.8` — bumps every declared file to 5.0.8 using `jq`, prints diff, then runs audit.
- `bump-version.sh --check` — reports current versions, flags drift (any file whose version disagrees).
- `bump-version.sh --audit` — greps the whole repo for the current version string, lists any matches that are not in the declared-files list (so the maintainer can add them or exclude them).

Key design: **audit is paranoid**. After every bump, it greps the repo for the new version string and flags anything the declared-files list didn't cover. This catches version leaks in SKILL.md, READMEs, test assertions, etc.

### 6.4 Release management — `RELEASE-NOTES.md`

One chronological markdown file at repo root. Release notes are **grouped per version in reverse chronological order**, with inner sections by platform or theme. The v5.0.7 entry:

```markdown
## v5.0.7 (2026-03-31)

### GitHub Copilot CLI Support
- **SessionStart context injection** — Copilot CLI v1.0.11 added support for
  `additionalContext` in sessionStart hook output. The session-start hook
  now detects the `COPILOT_CLI` environment variable and emits the SDK-
  standard `{ "additionalContext": "..." }` format, giving Copilot CLI
  users the full superpowers bootstrap at session start. (Original fix by
  @culinablaz in PR #910)
- **Tool mapping** — added `references/copilot-tools.md` with the full
  Claude Code to Copilot CLI tool equivalence table
- **Skill and README updates** — added Copilot CLI to the `using-superpowers`
  skill's platform instructions and README installation section

### OpenCode Fixes
- **Skills path consistency** …
- **Bootstrap as user message** …
```

Patterns:
- Version + date as `## vX.Y.Z (YYYY-MM-DD)` header.
- Subsection headers by platform (`### GitHub Copilot CLI Support`, `### OpenCode Fixes`, `### Cursor Support`) — the vast majority of v5.0.x changes are cross-platform plumbing, not skill content.
- Bullets use bold lead-in (`- **Skills path consistency** —`) with issue/PR references inline (`#916`, `PR #910 by @culinablaz`).
- Platform-specific changes are flagged in the section header, not in the bullet. A reader scanning for Cursor changes finds them by `### Cursor` headers.

Git tags match releases (`v5.0.7`, `v5.0.6`, `v5.0.5`, `v5.0.4`…). GitHub releases are created but carry only the release-notes excerpt, not binary artifacts.

---

## Section 7 — Recommended repo structure for karpathy-wiki

Our MVP target is Claude Code only; full cross-platform planned later. Best strategy: **ship superpowers' exact conventions from day one, stub the per-platform surfaces we don't need yet with placeholders**, so adding each platform later is a small diff rather than a repo-wide refactor.

### 7.1 Day-one (MVP, Claude Code only) directory tree

```
karpathy-wiki/
├── README.md                        User-facing install + overview. Links to per-platform docs (to be added).
├── CLAUDE.md                        Contributor guidelines (agent-facing: PR rules, eval requirements). Canonical.
├── AGENTS.md → CLAUDE.md            Symlink. Seeds the vendor-neutral path for future Codex/Cursor users.
├── LICENSE                          MIT.
├── package.json                     { "name": "karpathy-wiki", "version": "0.1.0", "type": "module",
│                                      "main": ".opencode/plugins/karpathy-wiki.js" }. Minimal; no deps.
├── .gitignore                       .worktrees/, .DS_Store, node_modules/, .wiki-test-output/
├── .gitattributes                   LF line endings on *.sh, *.cmd, *.md, *.json, *.js — required if we adopt
│                                    the polyglot wrapper. Ship day one.
├── .version-bump.json               Declares package.json, .claude-plugin/plugin.json today.
│                                    Extended as other manifests are added.
├── RELEASE-NOTES.md                 One file, reverse-chronological, per-version with per-platform subsections
│                                    (even when only Claude Code exists — leaves the shape ready).
│
├── .claude-plugin/
│   ├── plugin.json                  { name, description, version: 0.1.0, author, license, keywords }.
│   └── marketplace.json             Optional day-one; only needed if we want to publish under our own
│                                    marketplace. Deferrable.
│
├── skills/
│   └── wiki/                        The single skill (merges wiki + project-wiki from v1).
│       ├── SKILL.md                 Superpowers-style 250-350 line body; Hermes-borrowed SCHEMA template.
│       ├── references/              Sibling-level refs (one level deep; no nesting).
│       │   ├── capturing.md         Capture-file schema.
│       │   ├── ingesting.md         Ingester algorithm, locking, manifest rules.
│       │   ├── commands.md          `wiki doctor` / `wiki status` exact behaviour.
│       │   ├── platform-support.md  Cross-platform headless-command table (Claude/Codex/OpenCode/etc.).
│       │   └── schema.md            Starter SCHEMA.md template.
│       └── scripts/                 Extensionless bash helpers (polyglot-ready naming).
│           ├── drift-check          SessionStart drift detection (SHA-256 manifest).
│           ├── drain-ingest         Stop-hook drain spawner (headless detached ingester).
│           ├── wiki-status          Status report helper.
│           └── wiki-doctor          Doctor helper (delegates heavy lifting to an LLM subprocess).
│
├── agents/                          Claude Code agent definitions, also consumed by Cursor later.
│   └── wiki-ingester.md             Ingester agent (Haiku-pinned, restricted tools).
│
├── commands/                        Slash commands; exposed to Cursor later via "commands": "./commands/".
│   ├── wiki-status.md               → runs `scripts/wiki-status`
│   └── wiki-doctor.md               → runs `scripts/wiki-doctor`
│
├── hooks/
│   ├── hooks.json                   SessionStart (matcher "startup|clear|compact") + Stop
│   │                                — both `type: command`, never `type: prompt`. Calls run-hook.cmd.
│   ├── run-hook.cmd                 Polyglot wrapper (copy-paste superpowers' pattern verbatim).
│   ├── session-start                Shell drift-check + drain-spawn. Emits zero context (issue #1220 lesson).
│   └── stop-sweep                   Shell drain-spawn + optional transcript-sweep toggle.
│
├── docs/                            Per-platform install runbooks, ready to receive new files.
│   └── README.claude-code.md        Claude Code install + troubleshooting (mirrors docs/README.codex.md style).
│
├── scripts/
│   └── bump-version.sh              Same as superpowers'. Drives cross-manifest version sync + audit.
│
└── tests/
    └── claude-code/                 Bash harness: isolated $HOME, real `claude -p`, parse JSONL transcript,
        ├── test-helpers.sh           assert on skill invocation + capture creation + ingester spawn.
        ├── test-wiki-trigger.sh
        ├── test-capture-ingest.sh
        └── run-skill-tests.sh
```

**Files explicitly deferred for Claude Code MVP** (but the directory tree leaves space for them):
- `GEMINI.md`, `gemini-extension.json` (Gemini CLI adapter)
- `.codex/INSTALL.md`, the Codex-plugin fork sync script (Codex)
- `.cursor-plugin/plugin.json`, `hooks/hooks-cursor.json` (Cursor)
- `.opencode/INSTALL.md`, `.opencode/plugins/karpathy-wiki.js` (OpenCode)
- `docs/README.codex.md`, `docs/README.opencode.md`, `docs/README.cursor.md` (per-platform runbooks)
- `tests/opencode/`, `tests/cursor/` (per-platform install tests)

### 7.2 Full cross-platform tree (post-MVP target)

Add these deltas to the day-one tree:

```
karpathy-wiki/
├── GEMINI.md                        @./skills/wiki/SKILL.md
│                                    @./skills/wiki/references/platform-support.md
├── gemini-extension.json            { name, description, version, contextFileName: "GEMINI.md" }
│
├── .claude-plugin/
│   └── marketplace.json             (add if shipping via our own marketplace)
│
├── .codex/
│   └── INSTALL.md                   Manual-install runbook (git clone + ~/.agents/skills symlink).
│
├── .cursor-plugin/
│   └── plugin.json                  Declares skills, agents, commands, hooks: "./hooks/hooks-cursor.json".
│
├── .opencode/
│   ├── INSTALL.md                   `"plugin": ["karpathy-wiki@git+https://…"]` one-liner.
│   └── plugins/
│       └── karpathy-wiki.js         JS plugin: config hook pushes skills dir; bootstrap via
│                                    experimental.chat.messages.transform injection.
│
├── hooks/
│   └── hooks-cursor.json            { version: 1, hooks: { sessionStart: [{ command: "./hooks/session-start" }] } }
│
├── docs/
│   ├── README.claude-code.md
│   ├── README.codex.md
│   ├── README.cursor.md
│   ├── README.opencode.md
│   ├── README.gemini.md
│   └── windows/polyglot-hooks.md    Copy-paste the superpowers doc; it's Apache-style prose, not repo-specific.
│
├── scripts/
│   ├── bump-version.sh              (already present day one)
│   └── sync-to-codex-plugin.sh      Only needed if we ship to a Codex plugins monorepo.
│
└── tests/
    ├── claude-code/                 (already present day one)
    ├── opencode/                    setup.sh + test-plugin-loading.sh + test-tools.sh + test-priority.sh
    ├── cursor/                      (light — test manifest parses, hooks resolve)
    └── gemini/                      (light — test gemini-extension.json parses, GEMINI.md @imports resolve)
```

Then update `.version-bump.json` to declare every new manifest:

```json
{
  "files": [
    { "path": "package.json", "field": "version" },
    { "path": ".claude-plugin/plugin.json", "field": "version" },
    { "path": ".claude-plugin/marketplace.json", "field": "plugins.0.version" },
    { "path": ".cursor-plugin/plugin.json", "field": "version" },
    { "path": "gemini-extension.json", "field": "version" }
  ],
  "audit": { "exclude": ["RELEASE-NOTES.md", "node_modules", ".git", ".version-bump.json", "scripts/bump-version.sh"] }
}
```

### 7.3 Why this structure, line by line

- **`AGENTS.md` as symlink from day one.** Zero cost on Claude Code (nothing reads it), opens the door for Codex/OpenCode/Cursor later without a file rename. The symlink direction (AGENTS→CLAUDE) matches superpowers exactly.
- **`package.json` from day one** even without OpenCode support. Costs four lines, unlocks `npm`-style version comprehension and OpenCode-later without a second install mechanism.
- **`.gitattributes` from day one** even without Windows support. If we adopt the polyglot hook wrapper (we should — it's a 50-line freebie), CRLF conversion would silently break it on Windows users' clones long before we're ready to test there.
- **`hooks/` with `run-hook.cmd` polyglot + extensionless scripts from day one.** This is a proven pattern with nothing platform-specific about the Unix side. Adopting it now means cross-platform hook wiring is done once.
- **`RELEASE-NOTES.md` with per-platform subsections from day one.** v0.1.0 will have only a "Claude Code" subsection, which is fine — the reader shape is set.
- **`docs/` directory from day one, with only `README.claude-code.md` inside.** Parallels superpowers' `docs/README.codex.md` / `docs/README.opencode.md` pattern. Easy to add peer files per platform.
- **`skills/wiki/`, not `skills/karpathy-wiki/`.** Per superpowers-skill-style-guide research: name the skill by its function (`wiki`), not its lineage. The repo name can carry "karpathy-wiki" branding.
- **`.claude-plugin/marketplace.json` as optional day one.** Only required if we want `/plugin marketplace add toolboxmd/karpathy-wiki` to work. Can be added in v0.2.x when we have users asking for it.
- **`tests/claude-code/` from day one** matching superpowers' shape: isolated `$HOME`, real `claude -p`, transcript parsing. This is the only way to assert "did the skill fire on this prompt?".
- **No `install.sh` at the repo root.** Superpowers doesn't have one, and adding one creates a fourth install surface users have to choose between. Each platform's native install mechanism is the documented path; the repo contains the artifacts each platform expects.
- **No `.github/workflows/` yet.** Superpowers itself doesn't run CI. Ship it once we have enough testable surfaces; shipping empty workflow files adds noise.

### 7.4 One concrete bootstrap-compatibility trick

Superpowers' biggest cost line is `using-superpowers/SKILL.md` being reinjected on every `startup|clear|compact` fire (issue #1220, ~17.8k tokens over 57 hours). Our wiki skill should *not* inject SKILL.md at SessionStart — the description-match will load it on demand. **Our `hooks/session-start` should emit zero `additionalContext`** and do only shell-side housekeeping (drift check + drain ingester spawn). This is both cheaper and more robust.

Specifically:

```bash
# Our session-start (abbreviated)
[ -d "$PWD/wiki" ] || exit 0              # no wiki in cwd? nothing to do
# run drift-check against .manifest.json
bash "$SCRIPT_DIR/drift-check" "$PWD/wiki"
# drain any pending captures by spawning a detached headless ingester
bash "$SCRIPT_DIR/drain-ingest" "$PWD/wiki" &
disown
# emit empty context
printf '{}\n'
exit 0
```

The one-line `printf '{}\n'` satisfies Claude Code's hook protocol without injecting anything. Matches the "never use hooks for LLM work" principle that superpowers-skill-style-guide.md already codified.

---

## Closing note

The superpowers packaging layer is remarkably disciplined for a 164k-star repo. The design can be summed up in five rules:

1. **One canonical contributor file, one symlink, one Gemini file** — not a one-size-fits-all agents file.
2. **One manifest per platform, as thin as the platform allows** — auto-discovery beats declaration where available (Claude Code).
3. **One hook script + one polyglot wrapper + one per-platform JSON** — all logic in one bash file that branches on env vars.
4. **One `.version-bump.json` + one script to keep manifests in lockstep + one paranoid audit** — versions can't drift silently.
5. **Local bash tests, no CI** — integration tests run real CLIs in headless mode and parse transcripts.

Adopting this shape on day one for karpathy-wiki costs us about 15 files that are each under 50 lines, and leaves every later platform expansion as an additive one-file diff rather than a restructuring.
