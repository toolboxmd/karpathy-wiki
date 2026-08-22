---
title: karpathy-wiki issues
status: living-document
last_reviewed: 2026-08-22
---

# ISSUES

Known bugs, risks, regressions, blocked work, and technical debt for the
plugin. This file is a local scratchpad. It is not the `wiki issues` command,
not `.ingest-issues.jsonl`, not a GitHub Issues replacement, and not a
work-package manifest.

Promote an entry to GitHub Issues only when starting public, collaborative, or
automated work on it. Shipped fixes belong in `CHANGELOG.md`, not here.

## P1: least-privilege containment for detached provider workers

```yaml
status: deferred
priority: p1
effort: large
labels: [security, provider-runtime, blast-radius]
revisit_when:
  "Before unattended ingestion is offered for collaborator-controlled or
  otherwise untrusted captures and source files."
refs:
  - scripts/wiki_dispatch.py (provider environment inheritance)
  - scripts/wiki_providers.py (headless provider permission modes)
  - skills/karpathy-wiki-ingest/SKILL.md (semantic shell workflow)
  - docs/benchmarks/2026-08-20-grok-4.5-vs-4.6-medium.md
```

v0.3.0 treats detached ingesters as trusted local automation. Grok uses
`--always-approve`, Codex is launched with `danger-full-access`, and the
dispatcher passes the launcher's environment to provider processes. A hostile
capture can therefore attempt prompt injection against data and commands
available to the host user.

A Grok 4.5 Low canary on macOS established the useful but incomplete boundary:

- a project `.grok/sandbox.toml` profile based on the worker's current working
  directory can cover arbitrary project-wiki and main-wiki locations;
- `dontAsk` plus explicit read, edit, and command rules denied an unrelated
  test secret while allowing an exact helper;
- denying Grok's authentication file caused `Not signed in`, so provider auth
  cannot simply be placed outside every readable path;
- the production ingest traces use multiple general shell operations rather
  than one already-brokered helper;
- Grok's child-process network restriction is not enforced on macOS.

A complete fix should be provider-neutral and should include all of the
following in one separately reviewed workstream:

1. Construct a minimal explicit environment allowlist instead of copying
   `os.environ`, with no unrelated credentials.
2. Generate a fail-closed per-run path policy for the exact wiki, capture,
   evidence files, Git metadata, runtime files, and plugin-owned helpers.
3. Move locking, parsing, manifest updates, validation, Git publication, and
   completion behind deterministic helpers so the model does not need general
   shell authority.
4. Isolate provider authentication, preferably with a dedicated worker account
   or credential broker, while preserving non-interactive sign-in.
5. Apply equivalent policy to Grok, Codex, and Claude rather than documenting
   one provider as secure while the others retain broad host access.
6. Add adversarial prompt-injection, arbitrary-path, environment-secret,
   network, project-wiki, main-wiki, and `both` promotion canaries on macOS and
   Linux where supported.

Until every item is implemented and tested, unattended ingest remains for
trusted local content only. The v0.3.0 release documents and accepts this
limitation; it does not claim that `--always-approve` is sandboxed.

---
## Future: `allowed-tools` scoping on the four skills

```yaml
status: deferred
priority: p2
effort: medium
labels: [security, blast-radius]
revisit_when:
  "Next read-protocol-cycle planning. Orthogonal to read-protocol
  restoration; was deliberately not folded into 0.2.7 to keep the
  read-protocol commits independently revertable from security-scoping
  commits. Should ship alongside `bin/wiki orient` — the new CLI gives
  the read skill a cleaner `allowed-tools` entry."
refs:
  - skills/using-karpathy-wiki/SKILL.md (loader — no scoping; remains permissive)
  - skills/karpathy-wiki-capture/SKILL.md (capture — scope `bin/wiki capture` + `mv` to `inbox/`)
  - skills/karpathy-wiki-read/SKILL.md (read — scope `bin/wiki orient` + Read/Grep/Glob/WebFetch/WebSearch/Task)
  - skills/karpathy-wiki-ingest/SKILL.md (ingest — scope `scripts/wiki-*` + python3 + git)
```

Today no `karpathy-wiki-*` skill declares `allowed-tools`, so each
skill runs with full tool access when active. The prose narrows intended usage,
but the harness does not enforce that boundary. `allowed-tools` would make the
scope explicit for supported interactive hosts. This does not solve the P1
detached-provider boundary above; that worker is a separate provider process
with its own permission, sandbox, environment, and credential behavior.

Per-skill draft:

| Skill | `allowed-tools` |
|---|---|
| `using-karpathy-wiki` | none — loader, not actor; per upstream pattern, loaders don't restrict |
| `karpathy-wiki-capture` | `Bash(bin/wiki capture:*)`, `Bash(mv * <wiki>/inbox/*)`, `Read`, `Write(/tmp/*)` |
| `karpathy-wiki-read` | `Bash(bin/wiki orient:*)`, `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, `Task` |
| `karpathy-wiki-ingest` | `Bash(scripts/wiki-*:*)`, `Bash(python3 scripts/wiki-*.py:*)`, `Read`, `Edit`, `Write`, `Bash(git ...)`, `Bash(flock ...)` |

The ingester's broad write permissions are scoped to its own spawned
`claude -p` process — main-agent permissions are unaffected.

---
## Future: cold-no-wiki question path — Iron Rule 4 + no resolvable wiki

```yaml
status: open
priority: p2
effort: low
labels: [read-protocol, cold-start, ux]
revisit_when:
  "Surfaces in real sessions where a user asks a question in a directory
  with no wiki AND no ~/.wiki-pointer (so the read protocol's Step A has
  nothing to orient against). Currently the read skill degrades to
  Step F (web search) with the gap-capture skipped because there's
  nowhere to capture to. Acceptable but ungraceful — the user gets the
  answer but the wiki gains nothing from the cold result."
refs:
  - skills/karpathy-wiki-read/SKILL.md (Step F — cold result)
  - skills/using-karpathy-wiki/SKILL.md (Iron Rule 4)
  - scripts/wiki-init-main.sh (interactive bootstrap; prompts on first run)
  - bin/wiki (silent-bootstrap branch added in 0.2.7 for the capture path)
```

**The gap.** When a user asks a question and:

1. cwd has no `.wiki-config` / `.wiki-mode` (walk-up finds nothing), AND
2. `~/.wiki-pointer` is missing OR points to `none`, AND
3. `~/wiki/` doesn't exist (so 0.2.7's silent bootstrap can't fire)

…the read skill's Step A has no wiki to orient against. Step F runs (web search + cite), but the gap-capture (the bit that grows the wiki toward questions it failed to answer) is skipped because there is no capture target.

The capture path handles this case via the interactive `wiki-init-main.sh` prompt on exit 10. The READ path has no equivalent — Iron Rule 4 fires, the read skill loads, and the protocol degrades silently.

**Proposed fix.** When the read skill's Step A finds no resolvable wiki, the agent should — in the same announce line as the answer — surface a one-line note suggesting `wiki init-main`, so the user is prompted to set up a main wiki the first time the cold-no-wiki path fires. After the user runs it, subsequent questions get the full read protocol with capture-the-gap working.

Two flavors to consider during the next read-protocol brainstorm:

- **Prose-only:** karpathy-wiki-read/SKILL.md adds a Step A.0 that says "if no wiki resolvable, the answer should include a one-line nudge: *'(No wiki configured here — run `wiki init-main` to start capturing.)'*" Cheap. Relies on the agent following the prose.
- **Structural:** add a `bin/wiki ensure-main` (or similar) that the read skill calls at Step A. The CLI either resolves a wiki path (success) OR prints the nudge text + exits non-zero. The agent uses the exit code to decide whether to include the nudge.

Lean prose-only — same reasoning as `bin/wiki orient` deferral. Ship the prose first; promote to a CLI gate only if real-session evidence shows the prose nudge gets skipped.

Surfaced 2026-05-06 in conversation about how the wiki behaves in fresh
directories — same conversation that shipped 0.2.7's silent pointer
bootstrap (which closed the equivalent gap on the capture path).

---

## Stop-hook gate for turn-closure enforcement

```yaml
status: deferred
priority: p1
effort: medium
labels: [post-mvp, architecture]
revisit_when:
  "Fresh-session tests show main agent still skipping captures despite the v2.1
  prose gate, OR 3+ real-session misses where the `ls .wiki-pending/`
  pre-stop-turn check didn't fire."
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deferred-to-later
  - skills/karpathy-wiki-capture/SKILL.md (turn-closure prose at "Turn closure — before
    you stop")
```

Wire a `hooks/stop.sh` that runs `ls .wiki-pending/ | grep -v archive` and
refuses the Stop matcher if the output is non-empty, so turn-closure becomes
mechanically enforced rather than self-disciplined. Requires schema changes in
`hooks/hooks.json`. The prose in v2.1 is the contract that hook must satisfy.
This is the "real gate" the v2.1 plan reviewer called out as the ultimate fix
for the missed-capture failure mode.

---
## `--bare` + explicit `--allowedTools` on the spawned ingester

```yaml
status: blocked
priority: p2
effort: medium
labels: [defers-to-anthropic]
revisit_when:
  "Anthropic ships the announced `--bare`-as-default-for-`-p` change (documented
  but undated as of 2026-04-24). When that lands, the `--bare` flag becomes
  default and the karpathy-wiki ingester should explicitly opt IN to loading the
  karpathy-wiki skill via `--append-system-prompt` to avoid breaking."
refs:
  - ~/wiki/concepts/claude-code-headless-subagents.md (flag documentation)
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Token savings and CI reproducibility. The ingester currently relies on skill
discovery to know how to act (its prompt says "Follow the karpathy-wiki skill's
INGEST operation exactly"). `--bare` skips skill discovery, so this change
requires either passing the skill path via `--append-system-prompt` or
documenting the tradeoff explicitly.

---
