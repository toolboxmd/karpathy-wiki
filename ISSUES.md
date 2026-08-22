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
