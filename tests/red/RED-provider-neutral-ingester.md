# RED: provider-specific ingester identity causes cross-provider delegation

## Observed pressure scenario

The frozen `karpathy-wiki-ingest` skill identified every worker as a detached
`claude -p` ingester. During the Spark benchmark, Spark followed that role text
literally and launched a nested Claude process in Case 2 instead of performing
the ingest itself.

The read-only evidence came from an external frozen benchmark corpus. It is
intentionally not copied into or referenced by a machine-specific path from
this general-purpose plugin repository.

Artifact SHA-256:

```text
3211c263d25f1d93cafc9bcd517203590281a30b26f48a6b63ab16e5389def65
```

The transcript's command events at lines 64-65 contain the nested `claude -p`
invocation. This is observed behavior, not a hypothetical wording concern.

## Required behavior

- The skill identifies the model as a detached wiki ingester, independent of
  provider.
- The current provider must do the work itself and must not launch or delegate
  to another model or agentic CLI.
- The runtime wrapper, not the model, owns run IDs, heartbeat, retries, and
  `.ingest-runs.jsonl` writes.
- The model closes successful semantic work through one deterministic
  `wiki-complete-ingest.sh` helper.

## Preserved behavior

Orientation, evidence handling, source attribution, deduplication, page
selection, interlinking, and the quality rubric stay unchanged.
