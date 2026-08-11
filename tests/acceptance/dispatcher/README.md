# Dispatcher acceptance evidence

This directory holds sanitized, reviewable summaries for explicit real-provider
acceptance runs. Raw provider JSONL, local paths, and diagnostic output live in
the Git-ignored `raw/` subdirectory.

The real Codex Spark harness is opt-in because it consumes provider quota:

```bash
RUN_CODEX_SPARK_ACCEPTANCE=1 \
  bash tests/integration/test-codex-spark-ingest.sh
```

The harness always creates a disposable project wiki whose path contains
spaces. It never discovers, opens, migrates, or mutates an existing wiki. It
requests `gpt-5.3-codex-spark` with medium reasoning exactly, retains safe
invocation metadata, and fails rather than substituting another model or
effort.

The three semantic cases are:

1. cold ingest;
2. exact duplicate at the same evidence path;
3. related augmentation.

It also checks deterministic completion, one archive and terminal event per
run, absence of slot/processing leaks, missing-CodexBar behavior, path safety,
and command transcripts for nested agentic CLI delegation. This qualifies the
Codex adapter lifecycle only. It does not add Spark to a production author or
fallback chain.
