# RED: provider-specific skill prose bypasses or contaminates the dispatcher

## Failure evidence

At repository baseline `990cb20`, the ingest skill identified every worker as
a spawned `claude -p` process and the capture skill described the deleted
`wiki-spawn-ingester.sh` path. That prose is incompatible with selecting
Claude Code, Codex, or Grok through one bounded dispatcher.

The failure was observed, not hypothetical. In an external frozen Spark
benchmark, the tested Codex model followed the provider-specific skill
identity and started a nested Claude CLI during case 2. The benchmark corpus
is deliberately outside this general-purpose plugin repository and is not a
runtime dependency.

Command events 64-65 contain the nested `claude -p` invocation. The frozen
artifact SHA-256 recorded by the benchmark is
`3211c263d25f1d93cafc9bcd517203590281a30b26f48a6b63ab16e5389def65`.

## Pressure scenario

Give a clean Codex or Grok ingester the old skill and one already-claimed
capture. The old role text says it is a Claude ingester and the old capture
mechanics name a direct spawner. A literal agent can delegate to Claude or
attempt the obsolete script, bypassing model attribution and the concurrency
ceiling.

## Required behavior

- The ingest skill identifies only a detached provider-neutral ingester.
- The selected model performs the semantic work itself and may not launch or
  delegate to another model or agentic CLI.
- Capture prose requests a bounded dispatcher tick and never names a raw
  spawner.
- Loader prose describes dispatch without embedding provider commands, retry
  loops, or concurrency arithmetic.
- Deterministic tests reject any surviving direct-spawn runtime path.
