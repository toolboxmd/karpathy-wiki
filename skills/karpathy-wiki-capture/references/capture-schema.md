# Capture frontmatter schema (canonical)

This is the single source of truth for capture file format. Both the
`karpathy-wiki-capture` skill (main agent) and the
`karpathy-wiki-ingest` skill (spawned ingester) reference this file.
Do not duplicate the contents in the skill bodies.

## File location

Captures live at `<wiki>/.wiki-pending/<timestamp>-<slug>.md` where
`<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC, hyphens not colons in
the time portion to keep the filename POSIX-friendly).

## Frontmatter fields

```yaml
---
title: "<one-line title>"
evidence: "<absolute path OR the literal string conversation>"
evidence_type: "file" | "mixed" | "conversation"
capture_kind: "raw-direct" | "chat-attached" | "chat-only"
suggested_action: "create" | "update" | "augment" | "auto"
suggested_pages:
  - concepts/<slug>.md
attachments:
  - "/absolute/path/to/additional-image.jpg"
captured_at: "<ISO-8601 UTC timestamp>"
captured_by: "<source identifier>"
capture_id: "cap-<portable opaque id>" | "prom-<stable promotion id>"
promotion_policy: "none" | "selective"
promotion_decision: null | "keep-local" | "promoted"
promotion_id: null | "prom-<stable promotion id>"
propagated_from: null | "cap-<source capture id>"
---
```

`attachments` is optional and defaults to an empty list for legacy captures.
It contains additional absolute file paths that belong to the same file-backed
evidence bundle as `evidence`. The primary `evidence` file comes first at
provider time when it is an image, followed by `attachments` in their recorded
order. The adapter never scans a directory or the wider wiki for images.

## `capture_kind` enum (canonical)

| `capture_kind` | `evidence_type` | Body floor | Body source |
|---|---|---|---|
| `raw-direct` | `file` | none | hook-generated boilerplate |
| `chat-attached` | `mixed` | 1000 b | main agent writes (the conversation-delta) |
| `chat-only` | `conversation` | 1500 b | main agent writes (the conversation IS the evidence) |

Body bytes are measured AFTER the closing `---` of frontmatter. Captures
under their floor are rejected by the ingester with `needs-more-detail: true`.

## Backward-compat for legacy captures (no `capture_kind` field)

Pre-v2.4 captures that lack `capture_kind` are mapped at ingest-time, in
priority order:

1. **Legacy drift override.** If `captured_by == "session-start-drift"` OR
   the title starts with `Drift:` → `capture_kind = raw-direct`. These
   are existing v2.x drift captures; they always meant raw-direct
   semantically.
2. **Path evidence.** If rule 1 doesn't match AND `evidence` is a
   filesystem path (starts with `/` or `~`) → `capture_kind = chat-attached`.
3. **Conversation evidence.** If `evidence == "conversation"` →
   `capture_kind = chat-only`.

The validator enforces `capture_kind` presence on new captures written
by v2.4-and-later code; legacy captures pass through these rules.

Legacy captures without the promotion fields are treated as
`promotion_policy: "none"`. They are ingested normally and are never
retrospectively promoted.

## `evidence` field

- For `capture_kind: raw-direct` and `chat-attached` → absolute path to
  the file on disk. NEVER the string `"file"`, `"mixed"`, or a
  wiki-relative path.
- For `capture_kind: chat-only` → the literal string `conversation`.

## `attachments` field

- Allowed only for `chat-attached` and `raw-direct` captures.
- Every value is an absolute path recorded explicitly by the capture protocol.
- Every additional path must resolve within the canonical parent directory of
  the primary `evidence` file. Symlinks cannot escape that capture-scoped root.
- Ordering is stable: primary image evidence first, then additional paths in
  frontmatter order.
- Missing, unreadable, or unsupported declared images are provider preflight
  failures. They are never silently omitted.
- For Grok native image delivery, supported formats are JPEG and PNG detected
  from file signatures. A filename extension or user-provided MIME string is
  not trusted as the MIME source.
- Each original remains part of the normal raw-evidence and manifest protocol.
  Native provider delivery does not replace raw retention.

## `propagated_from`

- `null` for original captures.
- The portable `capture_id` of the originating project capture for new
  derived main-wiki captures.
- Legacy absolute project-wiki paths remain readable for backward
  compatibility, but new captures must not write machine-specific paths.

## Selective promotion fields

- `capture_id` is assigned once when a capture is published and remains stable
  through pending, processing, failed, and archived states.
- `promotion_policy: "selective"` means this project capture originated under
  `both` mode and requires one durable semantic decision before completion.
- `promotion_decision` records that decision. `keep-local` publishes nothing;
  `promoted` means exactly one derived main capture is durable.
- `promotion_id` is deterministic from the source `capture_id`. It is null for
  keep-local and non-promotable captures.
- Main and project-only captures use `promotion_policy: "none"`.

## Filename slug

Slug is lowercased title with non-alphanumerics replaced by `-`,
collapsed, and trimmed. Generated by `scripts/wiki-lib.sh`'s `slugify`
function. Capture base length capped at 200 chars before adding `.md`.
