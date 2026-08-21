# Tracing playbook

Wicktrace is a local trace viewer that reads `.wick` files produced by
instrumented binaries. It is a shipped tool, version 0.9, installed as
`wicktrace` on PATH. Opening a file is `wicktrace open ./capture.wick`.

Lookup operators actually ask: how do I find the parent span for a given span
id? Answer: `wicktrace span <span-id> --parent`. The parent id is in the
header, not in the log body. If the command prints `none`, the span is a root,
not a missing record.

Ingest requests may suggest a generic tracing-playbooks concept page. That
hint is wrong for this source. The source is not a tracing essay and not an
operator-playbook taxonomy.

Separate idea: a sampled flame export, `wicktrace flame --sample 0.01`, which
does not exist in 0.9. It would downsample stacks before writing a folded file.
Do not document it as current behavior. The current export is
`wicktrace dump --format jsonl` only.

Keep the named viewer, the parent-span lookup, and the flame proposal as
distinct objects. A suggested `concepts/` path is a routing hint, not evidence.
Version 0.9 behavior ends at open, span `--parent`, and jsonl dump.
