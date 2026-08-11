# RED: local wall clock mislabeled as UTC

## Observed pressure

During the 2026-08-11 Codex Spark medium dispatcher acceptance, the related
augmentation wrote an `updated` and `rated_at` value two hours ahead of the
actual UTC run time. The value was local Europe/Warsaw wall time with a literal
`Z` suffix, so it passed the ISO-shape validator while stating the wrong
instant.

Sanitized evidence:
`tests/acceptance/dispatcher/2026-08-11-codex-spark-medium.md`.

## Failure mode

An ingester sees that the page convention requires an ISO-8601 UTC string, runs
the default local `date` command, and appends `Z`. The timestamp looks valid but
is false on any machine whose local timezone is not UTC.

## Required behavior

The ingest skill and canonical page convention must tell every provider to
generate `created`, `updated`, and `quality.rated_at` from a UTC clock, with the
shell form `date -u +%Y-%m-%dT%H:%M:%SZ`, and explicitly forbid relabeling local
wall-clock output as UTC.
