# Grok 4.6 native ACP image canary

Date: 2026-08-21

Result: **PASS**

This disposable canary exercised one real image ingest through the repository
dispatcher and Grok CLI 1.0.5. It used an isolated temporary wiki and an
isolated temporary runtime config. No live project wiki, runtime config, queue,
or source image was modified.

## Invocation evidence

```json
{
  "provider": "grok",
  "model": "grok-4.6",
  "reasoning_effort": "medium",
  "prompt_transport": "native_acp_content_blocks",
  "content_block_types": ["text", "image"],
  "image_count": 1,
  "images": [
    {
      "ordinal": 1,
      "mime_type": "image/jpeg",
      "bytes": 11847,
      "sha256": "ccef76610852889cd23205f8e555b4f06f88c58af7a47c02506de86a5ab92bce"
    }
  ]
}
```

The retained invocation metadata contains no base64 payload or source-image
copy.

## Semantic proof

The ingested page identified visual facts that were present in the attached
pixels but absent from the capture boilerplate:

- the `TESTING` section header
- the ordered menu entries `A/B`, `Multivariate`, and `Split URL`
- `Split URL` as the selected item
- the selected row's light-blue background

The page also declined to infer a product name, environment URL, results table,
URL editor, or traffic-allocation panel that the image did not show.

## Completion and preservation proof

- Dispatcher run `in-1787324826982077-44084-1` completed with exit code `0`.
- The capture moved from `.processing` to the archive.
- The original was retained under `raw/`.
- The retained raw file and manifest SHA-256 both matched the attached image:
  `ccef76610852889cd23205f8e555b4f06f88c58af7a47c02506de86a5ab92bce`.
- The temporary canary workspace was moved to the user's Trash after this
  non-sensitive record was written, so it remains recoverable until the Trash
  is emptied.
