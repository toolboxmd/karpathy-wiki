# Agentic CLI Skills Comparison — Cross-Platform SKILL.md Authoring Guide

**Date:** 2026-04-22
**Purpose:** Identify what works in ALL target agentic CLIs so we can write ONE `SKILL.md` (for the Karpathy Wiki v2) that loads and triggers correctly across every platform, and know exactly where each platform needs a parallel adapter file for features the SKILL.md itself can't express.
**Scope:** Skills discovery/loading, invocation/triggering, hooks, SKILL.md conventions, and cross-compat signals. Headless execution is **out of scope** (covered by a parallel investigation).

---

## 1. Quick Comparison Table

| Feature                                  | Claude Code                                                     | OpenCode (sst/opencode)                                                                | Codex CLI (openai/codex)                                        | Cursor CLI (cursor-agent)                                       | Gemini CLI (google-gemini)                   | Hermes Agent (local)                                                       |
| ---------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------------- |
| **Skill format name**                    | Agent Skills                                                    | Agent Skills                                                                           | Agent Skills                                                    | Agent Skills                                                    | Extensions (+ GEMINI.md)                     | Agent Skills (agentskills.io-compatible)                                   |
| **`SKILL.md` supported**                 | Yes (native)                                                    | Yes (native)                                                                           | Yes (native)                                                    | Yes (native)                                                    | **No**                                       | Yes (native)                                                               |
| **Per-user path**                        | `~/.claude/skills/<name>/`                                      | `~/.config/opencode/skills/<name>/`, also reads `~/.claude/skills/` and `~/.agents/skills/` | `$HOME/.agents/skills/<name>/`, admin `/etc/codex/skills/`      | `~/.cursor/skills/<name>/` (inferred from `.cursor/` convention) | `~/.gemini/extensions/<name>/`               | `~/.hermes/skills/[<category>/]<name>/`                                    |
| **Per-project path**                     | `.claude/skills/<name>/`                                        | `.opencode/skills/<name>/`, also `.claude/skills/`, `.agents/skills/`                  | `.agents/skills/<name>/` (walks up to repo root)                | `.cursor/skills/<name>/`                                        | `.gemini/extensions/<name>/`                 | (same single tree; no per-project)                                         |
| **Cross-CLI path compatibility**         | Reads only its own                                              | **Yes** — intentionally reads `.claude/`, `.agents/`                                   | **Yes** — `.agents/` is the designated cross-tool path          | Agent Skills spec–compliant                                     | N/A (different format)                       | Reads only its own                                                         |
| **Invocation**                           | Auto via description (progressive disclosure)                   | Explicit via native `skill` tool (agent calls `skill({name})`)                         | Auto via description **and** explicit (`/skills`, `$prefix`)    | Auto via description **and** explicit slash command             | Load-on-startup context injection            | Auto via description (agent prompt-builder injects metadata)               |
| **Progressive disclosure** (metadata→body→refs) | Yes (3 levels)                                          | Yes (name+description → full body on tool call)                                        | Yes (3 levels)                                                  | Yes                                                             | **No** — full context file loaded at startup | Yes (`skills_list` → `skill_view`)                                         |
| **`references/` / `scripts/` / `assets/`** | Yes (all three)                                              | SKILL.md only per docs; sub-files work if agent reads them                             | Yes (all three)                                                 | Yes (all three)                                                 | `commands/*.toml` + MCP servers              | Yes                                                                        |
| **Markdown link following**              | Yes (agent reads linked files via Bash/Read)                    | Yes (agent can Read linked files)                                                      | Yes                                                             | Yes                                                             | N/A                                          | Yes (`skill_view("name", "references/x.md")`)                              |
| **Hooks supported in skill dir**         | **No** — hooks live in `settings.json` (user/project), separate | **No hooks documented**                                                                | **No hooks** declared in skills                                 | **Yes, via plugin** (bundles skills+hooks+rules)                | No hooks                                     | **Yes** — via separate plugin system (`~/.hermes/plugins/<name>/plugin.yaml`) |
| **Hook events**                          | SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStop, StopFailure | none                                                        | none                                                            | SessionStart, beforeSubmitPrompt, PreToolUse, PostToolUse, Stop | none                                         | `on_session_start`, `on_session_end`, `on_session_reset`, `pre_tool_call`, `post_tool_call`, `pre_llm_call`, `post_llm_call`, `pre_api_request`, `post_api_request`, `on_session_finalize` |
| **Hook format**                          | JSON matchers + shell commands in `settings.json`               | —                                                                                      | —                                                               | JSON matchers in Cursor config; can run shell / modify prompt   | —                                            | Python callbacks in plugin `__init__.py:register(ctx)`                     |
| **Plugins (bundled distribution)**       | Yes (Plugins)                                                   | No (skills only, via `plugins/` dir for code plugins)                                  | Yes (Plugins wrap skills)                                       | Yes (Marketplace, `/add-plugin`, bundles skills+hooks+rules)    | Extensions are the unit                      | Yes (Python plugins)                                                       |
| **agentskills.io compatibility**         | Reference implementation                                        | Claims compatibility                                                                   | Compatible + `agents/openai.yaml` extension                     | Compatible                                                      | Not compatible                               | Compatible (comments in `skills_tool.py` explicitly cite spec)             |

---

## 2. Per-Platform Deep Dive

### 2.1 Claude Code (reference baseline)

- **Paths:** User skills at `~/.claude/skills/<name>/`; project at `./.claude/skills/<name>/`. Plugins (which bundle skills, hooks, commands) live at `~/.claude/plugins/` with an optional install via marketplace.
- **SKILL.md frontmatter:** required `name` (≤64 chars, lowercase/hyphens, no "anthropic"/"claude" reserved words, no XML tags), required `description` (≤1024 chars, no XML tags). Optional `license`, `compatibility`, `metadata`, `allowed-tools` (experimental). [[Claude Agent Skills docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)]
- **Discovery:** at startup. All installed skills' `name` + `description` are injected into the system prompt (Level 1, ~100 tokens each). Full `SKILL.md` body is loaded (Level 2) when Claude decides the skill matches (typically via `Read` tool). Referenced files (scripts/, references/, assets/) are Level 3.
- **Invocation:** purely description-driven auto-invoke. Users don't type anything — Claude's model sees the descriptions in its system prompt and decides.
- **Hooks:** separate from skills. Declared in `.claude/settings.json` (project), `~/.claude/settings.json` (user), or `.claude/settings.local.json`. Events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `StopFailure`, `PreCompact`. Hook JSON has `matcher` regex + `hooks[]` array with `type: "command"` and shell `command`. Env: `$CLAUDE_PROJECT_DIR`, `$CLAUDE_PLUGIN_ROOT`. A plugin can ship a `hooks.json` alongside its skill. [[Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide)]
- **Markdown link following:** yes — instructions like "see [references/ops.md](references/ops.md)" cause Claude to call `Read references/ops.md`.

### 2.2 OpenCode (opencode.ai / sst/opencode)

- **Paths (searches all, walks up to git worktree root):** `.opencode/skills/`, `.claude/skills/`, `.agents/skills/` at project level; `~/.config/opencode/skills/`, `~/.claude/skills/`, `~/.agents/skills/` globally. [[OpenCode Skills docs](https://opencode.ai/docs/skills/)]
- **Frontmatter:** `name` (1–64, `^[a-z0-9]+(-[a-z0-9]+)*$`), `description` (1–1024). Optional `license`, `compatibility`, `metadata`. Strictly agentskills.io.
- **Discovery:** on-demand. Agent sees skills via the native `skill` tool's tool description (name + description). To load the body it calls `skill({name: "git-release"})`.
- **Invocation:** **explicit tool call** — not a pure description auto-invoke. The model still decides when to call `skill()`, but it must issue the tool call. This means our description still drives behaviour, but we can't assume "the model is pre-primed" — it must choose to invoke.
- **Hooks:** **not documented**. OpenCode has `agents/`, `commands/`, `modes/`, `plugins/`, `skills/`, `tools/`, `themes/` dirs but no skill-side hook mechanism. [[OpenCode Config docs](https://opencode.ai/docs/config/)]
- **Sub-files:** not formally documented, but because OpenCode honours agentskills.io, relative-path markdown links work by virtue of the agent having Read tools.

### 2.3 Codex CLI (openai/codex)

- **Paths:** scans `.agents/skills/` walking up from cwd to repo root (repo-level); `$HOME/.agents/skills/` (user); `/etc/codex/skills/` (admin); plus built-in bundled skills (system). [[Codex Skills docs](https://developers.openai.com/codex/skills)]
- **Frontmatter:** `name` + `description` required; agentskills.io frontmatter otherwise. Optional Codex-specific `agents/openai.yaml` sibling file declares `interface` (display name/icon/brand), `policy.allow_implicit_invocation` (default `true`), and `dependencies` (MCP servers). This file is **optional** and degrades gracefully — other CLIs ignore it.
- **Discovery:** progressive disclosure at startup (name + description + path + optional openai.yaml metadata). Full body loaded only when skill is selected.
- **Invocation:** three modes —
  1. **Implicit** (description matching, `policy.allow_implicit_invocation=true` is default)
  2. **Explicit via `/skills`** command
  3. **Explicit via `$prefix`** in prompt
- **Hooks:** none declared on the skill side. Repo-local `AGENTS.md` acts as project-wide persistent context. Skill-like behaviour closer to startup happens through `AGENTS.md`, not hooks.
- **Plugins:** "Skills are the authoring format; plugins are the installable distribution unit." Plugins wrap skills with multi-repo packaging but don't change `SKILL.md` itself.

### 2.4 Cursor CLI (cursor-agent)

- **Paths:** `~/.cursor/skills/<name>/` user; `.cursor/skills/<name>/` project. Skills + rules + commands + hooks + MCP servers are all bundleable into a **Cursor Plugin** installable via `/add-plugin` or cursor.com/marketplace. [[Cursor changelog 2.4](https://cursor.com/changelog/2-4)]
- **Frontmatter:** agentskills.io-compliant `name`, `description`. Same progressive disclosure model as Claude Code. `name` becomes a `/slash-command` for manual invocation.
- **Discovery:** metadata at startup; body loaded on trigger.
- **Invocation:** implicit (description-matching) **and** explicit (`/skill-name` slash command in chat, or `$skill-name` in prompt).
- **Hooks:** `SessionStart`, `beforeSubmitPrompt`, `PreToolUse`, `PostToolUse`, `Stop`. Hooks run shell commands and can modify prompts. Declared in plugin-level config, not in SKILL.md itself. [[Cursor agent plugins forum thread](https://forum.cursor.com/t/agent-plugins-isolated-packaging-lifecycle-management-for-sub-agents-skills-hooks-rules-incl-agent-md-across-cursor-ide-cli/151250)]
- **Plugins:** the canonical way to ship hooks alongside a skill.

### 2.5 Gemini CLI (google-gemini/gemini-cli)

- **Does NOT support Agent Skills / SKILL.md.** Uses a different model: **Extensions**.
- **Paths:** `~/.gemini/extensions/<name>/` with `gemini-extension.json` (manifest) + optional `GEMINI.md` (context) + `commands/*.toml` (custom slash commands) + MCP server declarations. [[Gemini CLI extensions docs](https://google-gemini.github.io/gemini-cli/docs/extensions/)]
- **Discovery:** **no progressive disclosure**. `contextFileName` (defaults to `GEMINI.md`) is loaded fully at startup as hierarchical memory, merged with workspace/user `GEMINI.md` via `/memory` commands.
- **Invocation:** context is always-on (system-prompt style). Commands are slash-invoked. No description-based auto-invoke mechanism.
- **Hooks:** none. Extensions load at startup; no lifecycle events.

Implication: to cover Gemini CLI, we must additionally ship a `GEMINI.md` and a `gemini-extension.json` alongside our SKILL.md. Our skill directory is NOT auto-loaded by Gemini.

### 2.6 Hermes Agent (local)

**Source:** `/Users/lukaszmaj/dev/research/hermes-agent/`.

- **Paths:** `~/.hermes/skills/[<category>/]<name>/` (seeded from bundled `skills/` directory at install). Defined in `tools/skills_tool.py:SKILLS_DIR = HERMES_HOME / "skills"`. Single source of truth — no per-project tree.
- **Frontmatter:** agentskills.io-compatible. Required `name` (≤64), `description` (≤1024). Optional `version`, `license`, `compatibility`, `platforms` (macOS/linux/windows restriction), `prerequisites.env_vars`, `prerequisites.commands`, `metadata.hermes.tags`, `metadata.hermes.category`, `metadata.hermes.related_skills`, `metadata.hermes.config[]` (user-promptable config keys like `wiki.path`). All documented inline in `tools/skills_tool.py` docstring. Example from `skills/research/llm-wiki/SKILL.md`:
  ```yaml
  name: llm-wiki
  description: "Karpathy's LLM Wiki — build and maintain a persistent, interlinked markdown knowledge base..."
  version: 2.0.0
  metadata:
    hermes:
      tags: [wiki, knowledge-base, research]
      config:
        - key: wiki.path
          default: "~/wiki"
  ```
- **Discovery:** progressive disclosure via two tools — `skills_list` (tier 1: all name+description) and `skill_view` (tier 2/3: loads body or a specified sub-file like `skill_view("skill-name", "references/foo.md")`).
- **Invocation:** description-driven auto-invoke (the agent's prompt builder injects all skills' metadata into the system prompt, with caching). Also slash-invokable via `/skills inspect <id>` and the `skills_hub` CLI.
- **Hooks:** **yes**, but they live in the **separate plugin system**, not in skills. Plugins go in `~/.hermes/plugins/<name>/` with `plugin.yaml` + `__init__.py:register(ctx)`. `VALID_HOOKS` (from `hermes_cli/plugins.py`): `pre_tool_call`, `post_tool_call`, `pre_llm_call`, `post_llm_call`, `pre_api_request`, `post_api_request`, `on_session_start`, `on_session_end`, `on_session_finalize`, `on_session_reset`. Hooks are **Python callbacks**, not shell commands.
- **Distribution:** rich hub — `hermes skills search|install|inspect|list|publish|snapshot|tap`. Supports pulling from official (Nous Research), Clawhub, LobeHub, and generic GitHub "taps." Runs a security scanner (`skills_guard`) on every install and maintains a lockfile.

---

## 3. The Common Subset — What Works in ALL of Them

If we want ONE `SKILL.md` that all six platforms can load, we constrain ourselves to the intersection:

**Works everywhere (except Gemini CLI, which doesn't support SKILL.md at all):**

1. **File placement:** a directory named `wiki/` containing `SKILL.md`, symlinked or installed into the per-platform path. `.agents/skills/` is the most portable project path (Codex, OpenCode). `.claude/skills/` is widely honoured as a fallback (Claude Code, OpenCode). For per-user scope, ship both `~/.claude/skills/wiki/` and `~/.agents/skills/wiki/` (and `~/.hermes/skills/research/wiki/` for Hermes).
2. **Frontmatter:** strict agentskills.io minimum — `name` + `description`. Safe optional additions: `license`, `compatibility`, `metadata`. Avoid `allowed-tools` (experimental per spec, not honoured uniformly).
3. **`name` format:** lowercase, hyphens only, ≤64 chars, no "anthropic"/"claude" reserved words (Claude Code constraint), must match parent directory name.
4. **`description` format:** ≤1024 chars, both "what" and "when" signals, keyword-rich for implicit matching. This is the one string the model reads on every startup on every platform — it does the heavy lifting.
5. **Body:** pure markdown. Keep under 500 lines / 5k tokens per spec. Relative links to `references/*.md` and `scripts/*.{py,sh}` are universally honoured because every platform gives the agent a Read/Bash tool.
6. **Sub-directory naming:** `scripts/`, `references/`, `assets/` — canonical per agentskills.io, honoured by Claude Code, Codex, Cursor, Hermes; ignored but harmless on OpenCode.
7. **Progressive disclosure:** keep the SKILL.md body self-sufficient so the skill is useful even without loading sub-files; push detail into `references/` so cheap metadata-only startup stays cheap.

**What does NOT work uniformly and must live outside SKILL.md:**

- Hooks (different format and location everywhere).
- Platform-specific metadata (Codex's `agents/openai.yaml`, Hermes's `metadata.hermes.*`, Cursor's plugin manifest). These are additive — include them as optional sidecars; they're ignored by platforms that don't recognise them.
- Explicit slash command names (Codex's `/skills`, Cursor's `/<name>`, Hermes's `/skills inspect`). The `name` field is what becomes the command when available; don't rely on a specific slash syntax.

---

## 4. Platform-Specific Adapter Patterns (Graceful Degradation)

The skill should work on every platform, but some platforms support features the others don't. Here's how to degrade without adding platform-detection logic inside SKILL.md.

### 4.1 Hooks — the biggest platform split

Our design calls for SessionStart and Stop hooks. Native hook support varies:

| Platform    | Hook story                                                                                              | What to ship                                                                                                               |
| ----------- | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Claude Code | Full — SessionStart, Stop, etc. in `settings.json`                                                      | `hooks.json` in the plugin (or instructions to add to `~/.claude/settings.json`). Shell commands only. No LLM at hook time. |
| Cursor      | Full — declared via plugin manifest                                                                     | Plugin-format hooks file. Same shell-commands-only constraint.                                                             |
| Hermes      | Full — Python callbacks in plugin `__init__.py`                                                         | Ship a sibling `plugins/wiki-hooks/plugin.yaml` + `register(ctx)` implementation.                                          |
| Codex CLI   | **None** on skill side; persistent context via `AGENTS.md`                                              | Degrade: rely on description triggering + manual `wiki status` / `wiki doctor` commands.                                   |
| OpenCode    | **None documented**                                                                                     | Same degradation as Codex.                                                                                                 |
| Gemini CLI  | **None**                                                                                                | Degrade + ship `GEMINI.md` for always-on context.                                                                          |

**Adapter pattern for hooks:** ship hooks as **separate platform-specific files next to the skill**, not inside SKILL.md. An `install.sh` (or documented manual steps) copies the right hook files into the platform's hook location. SKILL.md stays identical everywhere.

In the SKILL.md body, include an opening section: *"If hooks are available on this platform, SessionStart and Stop drift/drain jobs have already been configured. If not, a user-initiated `wiki status` call triggers drift-check manually."* This lets the agent work correctly in both modes.

### 4.2 Auto-invoke vs. explicit-invoke

- Claude Code + Codex + Hermes: auto-invoke from description alone.
- Cursor: auto-invoke **or** explicit `/wiki` slash.
- OpenCode: **requires** explicit `skill({name:"wiki"})` tool call — agent decides but must issue the call.

**Adapter pattern:** the `description` field must do double duty — it's both the "when to trigger" rule for auto-invoke platforms AND the "what's in this skill for me" hook for OpenCode's agent to decide to call `skill()`. Front-load the description with concrete trigger verbs so OpenCode's agent recognises applicability.

### 4.3 Gemini CLI

Not an Agent Skills platform. Ship a parallel `GEMINI.md` (same content as the start of SKILL.md, no frontmatter, no progressive disclosure — pure prompt injection) and a `gemini-extension.json` manifest. Wire it into `~/.gemini/extensions/wiki/`. Gemini users lose progressive disclosure and hooks; they get always-on context plus optional `commands/wiki-status.toml` and `commands/wiki-doctor.toml` for the two user commands.

### 4.4 Referenced files

All platforms that support SKILL.md also give the agent tools to Read relative-path markdown files. Inlining references is optional but **highly compatible** — agents reliably follow links like `[operations guide](references/operations.md)` when described in natural prose. Avoid magic tokens or XML-style includes; they're platform-specific.

### 4.5 Per-project vs. per-user

Our design creates a per-user main wiki (`~/wiki/`) and optional per-project wikis (`<project>/wiki/`). The SKILL.md itself is the same in both cases — the *wiki data* differs, not the skill code. Install the skill once per user in every CLI's per-user skills directory, and let runtime logic (read `.wiki-config` in cwd) pick the right wiki target.

---

## 5. Recommendation for Our SKILL.md

### 5.1 Frontmatter to use

```yaml
---
name: wiki
description: "Karpathy-style LLM wiki — build and maintain a persistent, interlinked markdown knowledge base. Auto-captures wiki-worthy moments during sessions, ingests new sources into raw/, answers questions from the wiki, and lints for consistency. Trigger when: user adds sources to raw/, pastes content to ingest, says 'add to wiki' or 'remember this', asks synthesis or research-recall questions ('what do we know about X', 'how does X relate to Y', 'summarize Y'), or runs 'wiki status' / 'wiki doctor'. Do not trigger for time-sensitive lookups, project source code questions, or routine file operations."
license: MIT
compatibility: "Works in Claude Code, OpenCode, Codex CLI, Cursor CLI, and Hermes Agent. On Gemini CLI, install the sibling GEMINI.md instead. Requires Bash/Read tools. SessionStart/Stop hooks are optional; if present they automate drift-check and ingest-drain."
metadata:
  version: "2.0.0"
  author: "bigbrain"
  repo: "https://github.com/toolboxmd/karpathy-wiki"
---
```

Rationale:

- **`name: wiki`** — short, lowercase, hyphen-safe, matches parent directory, doesn't collide with Claude Code's reserved words.
- **`description`** under 1024 chars, front-loaded with the concept ("Karpathy-style LLM wiki"), packed with trigger verbs ("add", "ingest", "lint", "what do we know", "how does X relate to Y"), and explicit DO-NOT-TRIGGER guidance. This single field drives OpenCode's explicit-invoke decision, Claude Code/Codex/Hermes implicit triggering, Cursor's dual mode, and human searchability.
- **`compatibility`** names every target CLI so users scanning the skill know what they're getting. Spec allows 500 chars; we fit.
- **`metadata`** — generic keys only. No `metadata.hermes.*` at the top level (it's not wrong, just noisy for other platforms). Hermes-specific config can go in a sidecar `hermes.yaml` if we want per-Hermes tuning.
- **Don't use `allowed-tools`** — experimental, support varies.

### 5.2 Description-writing style

- First sentence: one-line "what is this" that works as a catalog entry.
- Second block: **trigger list** with concrete verbs + phrases users say ("add to wiki", "remember this", "what do we know about X", "how does X relate to Y").
- Third block: **do-not-trigger list** to prevent over-activation on unrelated asks.
- Keep specific keywords: "ingest", "wiki", "knowledge base", "lint", "synthesis". These are what OpenCode's tool-description matcher and Claude's description matcher both latch onto.

### 5.3 Directory layout to ship

```
wiki/
├── SKILL.md                     # The main skill (cross-platform)
├── references/
│   ├── operations.md            # ingest / query / lint workflows in depth
│   ├── capture-format.md        # capture file schema
│   ├── schema-examples.md       # starter schema.md templates
│   └── locking.md               # locking + concurrency details
├── scripts/
│   ├── init-wiki.sh             # auto-init bootstrap
│   ├── drift-check.sh           # SessionStart drift detection (hash-based)
│   ├── drain-ingest.sh          # Stop hook drain
│   └── wiki-status.sh           # read-only status report
├── assets/
│   └── schema-starter.md        # default SCHEMA.md content
├── GEMINI.md                    # (optional sidecar) Gemini-compatible always-on context
├── gemini-extension.json        # (optional sidecar) Gemini manifest
└── platform-adapters/
    ├── claude-code-hooks.json   # paste into ~/.claude/settings.json
    ├── cursor-plugin.json       # Cursor plugin manifest with hooks
    └── hermes-plugin/           # Hermes plugin dir with register(ctx)
        ├── plugin.yaml
        └── __init__.py
```

- The **skill core** (`SKILL.md` + `references/` + `scripts/` + `assets/`) is 100% agentskills.io-compliant and drops into Claude Code, Codex, OpenCode, Cursor, and Hermes unchanged.
- **Platform adapters** are additive — an `install.sh` checks which CLI is present and copies the right files into the right config. SKILL.md never branches on platform.

### 5.4 What to avoid

- Platform-specific magic tokens, `@mentions`, or `<xml>` include syntax.
- Depending on `allowed-tools` (experimental, unreliable).
- Having SKILL.md body exceed 500 lines — push detail into `references/`.
- Encoding hooks inside SKILL.md — hooks don't live there on any platform.
- Uppercase, reserved words ("anthropic", "claude") or multi-hyphens in `name`.
- A top-level YAML block specific to one platform — keep sidecar files instead.

### 5.5 Install story (for a reader)

One-liner installs per CLI (for packagers to document):

- **Claude Code:** `cp -r wiki ~/.claude/skills/` + merge `platform-adapters/claude-code-hooks.json` into `~/.claude/settings.json`.
- **Codex CLI:** `cp -r wiki ~/.agents/skills/`.
- **OpenCode:** `cp -r wiki ~/.config/opencode/skills/` (or drop into `~/.claude/skills/` — OpenCode reads that too).
- **Cursor:** `cp -r wiki ~/.cursor/skills/` + install plugin for hooks via `/add-plugin`.
- **Hermes:** `hermes skills install toolboxmd/karpathy-wiki` (hub-installed) or `cp -r wiki ~/.hermes/skills/research/`.
- **Gemini CLI:** `cp -r wiki ~/.gemini/extensions/` and rely on `GEMINI.md` + `gemini-extension.json`, not `SKILL.md`.

---

## Sources

### Specifications and docs
- [Agent Skills Specification — agentskills.io](https://agentskills.io/specification)
- [Claude Code / Claude API — Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Claude Code — Hooks guide](https://code.claude.com/docs/en/hooks-guide)
- [OpenCode — Skills docs](https://opencode.ai/docs/skills/)
- [OpenCode — Config docs](https://opencode.ai/docs/config/)
- [Codex CLI — Skills docs](https://developers.openai.com/codex/skills)
- [Codex CLI — AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md)
- [Cursor — Agent Skills docs (context)](https://cursor.com/docs/context/skills)
- [Cursor — Plugins forum announcement](https://forum.cursor.com/t/agent-plugins-isolated-packaging-lifecycle-management-for-sub-agents-skills-hooks-rules-incl-agent-md-across-cursor-ide-cli/151250)
- [Cursor — CLI overview](https://cursor.com/docs/cli/overview)
- [Gemini CLI — Extensions docs](https://google-gemini.github.io/gemini-cli/docs/extensions/)
- [Anthropic engineering — Equipping agents with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)

### Hermes Agent source citations
- `/Users/lukaszmaj/dev/research/hermes-agent/hermes_cli/plugins.py` — `VALID_HOOKS` definition, plugin loader
- `/Users/lukaszmaj/dev/research/hermes-agent/hermes_cli/skills_hub.py` — hub CLI commands
- `/Users/lukaszmaj/dev/research/hermes-agent/tools/skills_tool.py` — skill loader, progressive disclosure, agentskills.io compatibility notes
- `/Users/lukaszmaj/dev/research/hermes-agent/skills/research/llm-wiki/SKILL.md` — in-tree example of the Karpathy wiki pattern
- `/Users/lukaszmaj/dev/research/hermes-agent/skills/productivity/linear/SKILL.md` — typical Hermes frontmatter with `prerequisites` and `metadata.hermes`

### Context and related
- [Karpathy Wiki v2 design doc](/Users/lukaszmaj/dev/bigbrain/plans/karpathy-wiki-v2-design.md)
- [Karpathy Wiki ecosystem research](/Users/lukaszmaj/dev/bigbrain/research/karpathy_wiki_ecosystem.md)
