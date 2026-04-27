# Agentic CLI Headless & Subagent Mechanics

Research for the Karpathy Wiki v2 ingestion design. The wiki skill captures a note in the active session, then needs to hand off ingestion (classify, merge into topic pages, dedupe, backlink) to a background worker so the foreground agent stays responsive. Two abstract handoff mechanisms exist:

1. **Headless invocation** — spawn a detached OS process of the CLI with `-p "prompt"` (or equivalent); the process runs to completion and exits.
2. **Subagent delegation** — within the current session, spawn a child agent that runs concurrently with the main conversation; no new OS process.

Sources: `claude --help` / `hermes --help` / `codex --help` / `codex exec --help` output captured locally; Anthropic docs (`code.claude.com/docs/en/headless`, `/sub-agents`, `/agent-teams`); OpenAI Codex docs (`developers.openai.com/codex/noninteractive`); OpenCode docs (`opencode.ai/docs/cli`, `/agents`); Cursor docs (`cursor.com/docs/cli/headless`); Gemini CLI docs (`github.com/google-gemini/gemini-cli`); Hermes source read directly at `/Users/lukaszmaj/dev/research/hermes-agent/` (`hermes_cli/main.py`, `cli.py`, `tools/delegate_tool.py`, `run_agent.py`).

## Section 1 — Quick comparison matrix

| Platform        | Headless flag            | Stdin input | Auto-exits | Detach-safe (nohup/setsid) | In-session subagent               | Concurrent subagents | Model per subagent |
|-----------------|--------------------------|-------------|------------|----------------------------|-----------------------------------|----------------------|--------------------|
| **Claude Code** | `claude -p "..."`         | yes          | yes         | yes                         | Task tool + subagent defs         | yes                   | yes                 |
| **OpenCode**    | `opencode run "..."`      | not documented | yes      | yes (normal process)        | `@subagent` / auto-delegate       | yes ("general" agent) | yes (per agent cfg) |
| **Codex CLI**   | `codex exec "..."`        | yes (piped as context, or `-`) | yes | yes                | no first-class subagent tool       | n/a                   | n/a                 |
| **Cursor CLI**  | `cursor-agent -p "..."`   | implied (scriptable) | yes | yes                         | not documented                     | n/a                   | n/a                 |
| **Gemini CLI**  | `gemini -p "..."`         | implied (auto-detects non-TTY) | yes | yes             | not documented                     | n/a                   | n/a                 |
| **Hermes**      | `hermes chat -q "..."` (`-Q` for quiet) | no (`_require_tty` guard on TUI cmds; chat -q is fine piped) | yes | yes | `delegate_task` tool + `/background` slash cmd | yes (`ThreadPoolExecutor`, default 3) | yes (different model/provider) |

Key: "Detach-safe" means the process can be launched with `setsid`/`nohup` and survives the parent session's exit — true for any normal Unix process, unless the CLI attaches aggressively to a controlling TTY. None of these CLIs in headless/`-p` mode require a TTY.

## Section 2 — Per-platform deep dive

### 2.1 Claude Code (`claude`)

**Headless.** `claude -p "prompt"` (alias `--print`). All regular CLI flags compose:

```bash
claude -p "Ingest capture at /tmp/cap_123.md into the wiki" \
  --allowedTools "Read,Edit,Write,Bash(git *)" \
  --model claude-haiku-4-5 \
  --output-format json \
  --bare
```

- **Stdin:** supported (`gh pr diff X | claude -p "Review this"` is in the official docs).
- **Exit:** always auto-exits on completion.
- **Detach:** `nohup claude -p "..." >/tmp/bg.log 2>&1 &` or `setsid` works. Claude Code does not hold the parent TTY in `-p` mode.
- **Auth:** interactive uses OAuth/keychain; `--bare` ignores both and requires `ANTHROPIC_API_KEY` (or `apiKeyHelper` via `--settings`). Recommended for spawned workers because it's deterministic and CI-safe.
- **Tools:** Bash/Read/Edit/Write are all available in `-p`. Pre-approve with `--allowedTools` or `--permission-mode acceptEdits|dontAsk`. No interactive permission prompts; the run aborts if it hits a disallowed tool.
- **Model choice:** `--model` (e.g. `haiku` / `sonnet` / full ID) — use Haiku for cheap ingest.
- **Output:** stdout (final text, JSON, or JSONL depending on `--output-format`), stderr for progress/errors. `--output-format stream-json` + `--verbose` streams events.
- **Idempotency:** no built-in idempotency. Running twice does the work twice unless your prompt/skill checks state first.

**Subagent.** The Task tool (configured via `--agents` JSON, `~/.claude/agents/*.md`, or plugins) delegates into a fresh context; only the summary returns. Callers can set `run_in_background: true` (harness-level flag in Claude Code) to make the parent proceed while the child runs. Multiple Task calls in one message run concurrently. Each subagent definition can pin its own `model` (e.g. `haiku`) and `tools` allowlist. Result is a single summary string.

Separate from Task: **agent teams** (experimental, gated on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) spawn full peer sessions with a shared task list and inter-agent messaging — overkill for ingestion. Not recommended.

### 2.2 OpenCode (`opencode`)

**Headless.** `opencode run "prompt"` with flags:

```bash
opencode run "Ingest capture file X into wiki" \
  --model anthropic/claude-haiku-4-5 \
  --agent wiki-ingester \
  --format json
```

- **Stdin:** not documented in the CLI reference. Safe assumption: pass via positional arg or `--file` attachment.
- **Exit:** yes, `run` is explicitly the non-interactive entry and exits.
- **Detach:** standard process, `setsid` OK.
- **Auth:** `opencode auth` (same as interactive).
- **Model:** `-m provider/model`.
- **Output:** stdout; `--format json` for structured parse.

**Subagent.** OpenCode has a proper agent taxonomy: **primary agents** (Build, Plan) and **subagents**. Primary agents invoke subagents automatically via description match, or users `@mention` them. The built-in `general` subagent is documented as the one "to run multiple units of work in parallel." Each agent is its own config file (`.opencode/agent/<name>.md` equivalent) with its own prompt, model, and tool allowlist. You can navigate child sessions with `session_child_first` / `session_child_cycle` / `session_parent` keybinds, implying genuine parent/child session hierarchy rather than a summary-only wrapper.

### 2.3 Codex CLI (`codex`)

**Headless.** `codex exec "prompt"` (alias `codex e`):

```bash
codex exec "Ingest capture at /tmp/cap_123.md into the wiki" \
  -m gpt-5-mini \
  --sandbox workspace-write \
  --full-auto \
  --json \
  -o /tmp/ingest-result.txt
```

- **Stdin:** yes — two modes. (a) `echo "prompt" | codex exec -` reads the full prompt from stdin. (b) `cat file.md | codex exec "summarize this"` treats stdin as extra context for the given instruction.
- **Exit:** yes. Progress goes to stderr, final message to stdout. `-o <path>` also writes final message to a file.
- **Detach:** standard process.
- **Auth:** CI/headless path is `CODEX_API_KEY` env var. `codex login` is the interactive equivalent.
- **Sandbox:** defaults to read-only; `--full-auto` = `workspace-write` + on-request approvals. For a detached worker you'll want `--full-auto` or `--sandbox workspace-write` so the ingester can actually write wiki files. `--dangerously-bypass-approvals-and-sandbox` exists but should be avoided.
- **Git requirement:** Codex refuses to run outside a git repo. Pass `--skip-git-repo-check` when running inside a non-git wiki dir, otherwise the worker hard-fails.
- **Model:** `-m`.
- **Output:** stdout (final text) + stderr (progress). `--json` emits JSONL event stream; `--output-schema` constrains the final message.
- **Idempotency:** `codex exec resume --last "next task"` (or target a session ID). Useful for retries.

**Subagent.** No first-class "Task" tool documented. Codex's parallelism story is: use `codex exec` in a shell fan-out, or in the interactive UI, request parallel commands. There is a "guardian subagent" concept in the Codex Smart Approvals feature (referenced even in Hermes source: `tools/approval.py:540` — "Inspired by OpenAI Codex's Smart Approvals guardian subagent"), but that's an internal approval reviewer, not a user-exposed delegation primitive.

**Implication for our skill:** on Codex, we must use headless spawn. In-session parallel subagents are not a supported mechanism.

### 2.4 Cursor CLI (`cursor-agent`)

**Headless.** `cursor-agent -p "prompt"` (or `--print`):

```bash
cursor-agent -p "Ingest capture into wiki" \
  --force \
  --output-format json
```

- **Stdin:** the headless mode is scriptable; specific stdin flag not documented in the public snippet — positional prompt is the canonical path.
- **Exit:** yes.
- **Auth:** `CURSOR_API_KEY` env var.
- **Permissions:** `--force` (aka `--yolo`) lets it write files without confirmation; needed for unattended workers.
- **Output:** `--output-format text|json|stream-json`; `--stream-partial-output` for streaming deltas.
- **Exit codes:** standard 0/nonzero.

**Subagent.** Not documented. For our purposes, treat Cursor CLI as headless-only.

### 2.5 Gemini CLI (`gemini`)

**Headless.** `gemini -p "prompt"` (or `--prompt`). Non-interactive mode also auto-activates on non-TTY environments:

```bash
gemini -p "Ingest this capture" \
  -m gemini-2.5-flash \
  --output-format json
```

- **Stdin:** non-TTY auto-detection implies piping works. Not explicitly spelled out in the doc snippet, but in practice `echo ... | gemini -p "..."` is the intended script pattern.
- **Exit codes:** `0` success, `1` general/API error, `42` input error, `53` turn limit exceeded — the most detailed exit-code taxonomy of the group.
- **Output:** `--output-format text|json|stream-json` with event types `init`, `message`, `tool_use`, `tool_result`, `error`, `result`.
- **Auth:** Google auth (OAuth or API key) — same as interactive.

**Subagent.** Not documented. Headless-only mechanism for our skill.

### 2.6 Hermes Agent (`hermes`)

Read directly from `/Users/lukaszmaj/dev/research/hermes-agent/`.

**Headless.** `hermes chat -q "query" -Q` — `-q/--query` is explicitly "Single query (non-interactive mode)"; `-Q/--quiet` is "Quiet mode for programmatic use: suppress banner, spinner, and tool previews. Only output the final response and session info." (`hermes_cli/main.py` argparse definitions around line 4593/4625.)

```bash
hermes chat -q "Ingest capture at /tmp/cap_123.md into the wiki" \
  -Q \
  -m anthropic/claude-haiku-4-5 \
  -t file,web,terminal \
  --yolo \
  --source tool
```

- **Stdin:** *interactive* Hermes commands (`hermes setup`, `hermes model`, etc.) have a `_require_tty` guard (`hermes_cli/main.py:53`) that hard-exits if stdin isn't a TTY — to prevent the curses TUI from spinning at 100% CPU. But `hermes chat -q "..."` is not TTY-guarded; it's the scriptable path.
- **Exit:** yes.
- **Detach:** standard process, `setsid` OK.
- **Dangerous ops:** `--yolo` bypasses dangerous-command approvals (essential for unattended workers).
- **Source tag:** `--source tool` keeps the spawned session out of the user's session list.
- **Model / provider / toolsets:** fully parameterisable per invocation (`-m`, `--provider`, `-t`).

**Subagent.** Two distinct in-session primitives, both backed by `ThreadPoolExecutor`:

1. **`delegate_task` tool** (`tools/delegate_tool.py`) — the agent calls this mid-conversation. Child gets a fresh conversation, restricted toolsets, its own `task_id`, its own iteration budget. Parent blocks until children complete. `MAX_DEPTH = 2` (no grandchildren). Default max concurrent children = 3 (`DELEGATION_MAX_CONCURRENT_CHILDREN` env or `delegation.max_concurrent_children` in config). Children can target a different provider/model (see comment at `delegate_tool.py:261` — "routing subagents to a different provider:model pair (e.g. cheap/fast"). Result returned to parent as summary only.

2. **`/background <prompt>` slash command** (`cli.py:5657` `_handle_background_command`) — spawns an entirely new `AIAgent` in a daemon thread with its own session ID. Parent can keep chatting; when the background task completes, its result prints to the CLI *outside* the active session's history. Closest analog to Claude's `run_in_background: true` Task tool. Note it runs in the *same process*, not a detached OS process — so it dies if the user kills the CLI. Partner slash `/stop` kills running background tasks.

**Comparison for our skill:** both the headless path (`hermes chat -q`) and the subagent path (`delegate_task` / `/background`) are available. Hermes is the most flexible of the six for this design.

## Section 3 — The common denominator

Every platform we'd realistically target supports one minimal pattern:

```
<cli> <prompt-flag> "<instruction>" [--model X] [--yolo/-auto-approve] [--json] [--output=FILE]
```

- All six have a first-class non-interactive entry: `-p` (Claude/Cursor/Gemini), `run` (OpenCode), `exec` (Codex), `chat -q` (Hermes).
- All six auto-exit on completion.
- All six support a "write without prompting" mode: `--allowedTools`/`--permission-mode` (Claude), `--force`/`--yolo` (Cursor), `--full-auto` (Codex), `--agent` with pre-approved tools (OpenCode), auth-level permissions (Gemini), `--yolo` (Hermes).
- All six produce stdout text plus (optionally) a JSON/JSONL stream.
- None require a TTY in headless mode — all detach-safe.

Subagents are **not** a common denominator. Claude, OpenCode, and Hermes have them; Codex, Cursor, and Gemini do not. A SKILL.md that relies on subagents would exclude half the ecosystem.

## Section 4 — Recommended invocation pattern for our skill

The skill should abstract over one command-line template, configured per-platform via `.wiki-config.yaml`:

```yaml
# .wiki-config.yaml
ingester:
  # Command template. Variables: {capture_path}, {wiki_root}, {prompt}
  cmd: "claude -p {prompt} --bare --allowedTools Read,Edit,Write,Bash --model claude-haiku-4-5 --output-format json"
  detach: true           # launch with setsid, redirect stdout/stderr to log
  log_dir: "{wiki_root}/.wiki/logs"
  env:
    ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
```

**SKILL.md contract** (abstract):

> To ingest a capture, write it to `raw/<timestamp>-<slug>.md`, then spawn the configured ingester command with the prompt "Ingest <capture_path> into the wiki at <wiki_root>". The ingester writes one or more wiki pages under `pages/` and appends to `INDEX.md`. The foreground agent does not wait for the ingester.

**Per-platform `cmd` fill-ins:**

| Platform    | Command template                                                                                                                                               |
|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Claude Code | `claude -p "{prompt}" --bare --allowedTools "Read,Edit,Write,Bash" --model claude-haiku-4-5`                                                                    |
| OpenCode    | `opencode run "{prompt}" --agent wiki-ingester -m anthropic/claude-haiku-4-5 --format json`                                                                      |
| Codex       | `codex exec "{prompt}" -m gpt-5-mini --full-auto --skip-git-repo-check -o {log_dir}/{task_id}.txt`                                                               |
| Cursor      | `cursor-agent -p "{prompt}" --force --output-format json`                                                                                                        |
| Gemini      | `gemini -p "{prompt}" -m gemini-2.5-flash --output-format json`                                                                                                 |
| Hermes      | `hermes chat -q "{prompt}" -Q --yolo -m anthropic/claude-haiku-4-5 -t file,web,terminal --source tool`                                                          |

**Detach wrapper** (platform-agnostic; lives in the skill helper, not duplicated in each template):

```bash
setsid nohup sh -c "$CMD" >"$LOG_DIR/$TASK_ID.out" 2>"$LOG_DIR/$TASK_ID.err" &
echo $! > "$LOG_DIR/$TASK_ID.pid"
disown
```

**Fallback path for platforms with subagent support** (Claude, OpenCode, Hermes): if `detach: false` is set, the skill instructs the foreground agent to call its native subagent tool (Task / `@subagent` / `delegate_task`) with the same prompt and `run_in_background: true`. This avoids process-spawn complexity but ties the ingester's lifetime to the parent session.

The skill's single decision is: **prefer detached headless spawn when available**, fall back to subagent delegation if the platform has no detach path (which, in our survey, none of them truly lack — all six can spawn a detached process). So the subagent fallback is only needed when the user has explicitly configured `detach: false` (e.g. for debugging or for platforms where the API key isn't available out-of-process).

## Section 5 — Edge cases and gotchas

**Auth across spawned workers.**
- Claude Code's `--bare` requires `ANTHROPIC_API_KEY` in the env — the detached worker inherits it only if the parent shell exported it. Launching via an agent tool call may drop env vars; the skill must pass `env:` explicitly.
- Codex reads `CODEX_API_KEY` in CI mode; `codex login` credentials also propagate if on the same machine/user.
- Hermes has a pooled credentials system (`hermes auth add <provider>`) so multiple workers can share quotas without re-authing.
- Cursor (`CURSOR_API_KEY`) and Gemini (Google OAuth or API key) are env-var driven.

**Killed workers when the main session ends.**
- A truly detached process (`setsid` + `nohup`) survives parent exit on macOS and Linux.
- **Subagents do not survive parent exit.** Claude's Task subagent, OpenCode's subagent session, and Hermes's `delegate_task`/`/background` all run inside the parent process; they die when the user quits. This is why detached headless is preferable for long-running ingestion.
- If the skill uses the subagent fallback, it should mark the capture as "ingestion pending" and have a recovery path on next session startup (re-scan `raw/` for un-ingested files).

**Billing/cost per instance.** Each spawned worker = one independent API-billed session. No cached context-window sharing between spawned workers. To keep costs low: route ingesters to cheap models (Haiku / gpt-5-mini / gemini-2.5-flash), use `--bare`-equivalent flags to skip heavy context auto-loading (CLAUDE.md, MCP servers, plugins), and keep prompts focused on one capture at a time. Hermes's pooled credentials let multiple workers share quota; none of the other CLIs have a comparable shared-cache mechanism.

**Rate limits.** None of the CLIs rate-limit their own spawn rate, but the underlying API providers do. A wiki with hundreds of queued captures should throttle by spawning N at a time — a simple FIFO queue file + a launcher loop in the skill is the correct pattern.

**Codex git-repo requirement.** If the wiki root isn't a git repo, `codex exec` fails without `--skip-git-repo-check`. Bake it into the template.

**Hermes `--source tool`.** Without this, every spawned ingester pollutes `hermes sessions list`. Set it so user-visible session pickers stay clean.

**Claude Code `--bare` side effects.** Bare mode skips hooks, MCP servers, CLAUDE.md auto-discovery, and plugin sync. If your ingester *needs* a particular MCP server (e.g. a Notion MCP to write a wiki mirror), pass `--mcp-config` explicitly; don't expect the parent's MCP config to propagate.

**OpenCode stdin gap.** `opencode run` stdin piping is not documented. Pass the capture path as an argument or via `--file`; don't rely on `echo ... | opencode run`.

**Hermes TTY guard.** The `_require_tty` guard in `hermes_cli/main.py:53` applies only to interactive-only commands (`setup`, `model`, `tools`). `hermes chat -q` is exempt — that's the non-interactive hatch the skill should use. Piping through subprocess without a TTY works.

**Detach on macOS vs Linux.** `setsid` is Linux-native; on macOS it's commonly `setsid` from coreutils or else `nohup ... &` + `disown`. The skill helper should detect the platform and use the right incantation.

**Stream-JSON logs.** Claude/Codex/Gemini all emit an event stream on `--output-format stream-json` / `--json`. Detached workers should redirect this to `{log_dir}/{task_id}.jsonl`; a post-run health check can `jq` through it to confirm no errors.

**Idempotency.** None of the platforms dedupe by prompt. The skill must handle idempotency itself: before spawning, check whether the capture has already been ingested (e.g. a `.ingested` marker file or a hash stored in `INDEX.md`). The ingester prompt should also instruct the agent to check for an existing matching page before creating one.

## Bottom line

All six CLIs support detached headless spawn — the pattern at the core of the Karpathy Wiki v2 design works universally. Claude Code, OpenCode, and Hermes additionally offer true in-session subagents if the skill ever wants a "block-on-result" variant; Codex/Cursor/Gemini do not. The skill's `SKILL.md` should commit to the headless-spawn pattern as primary; the per-platform `.wiki-config.yaml` only needs to fill in the command template and auth env vars. No platform-specific branching inside SKILL.md is required.
