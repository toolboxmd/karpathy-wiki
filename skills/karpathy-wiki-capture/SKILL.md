---
name: karpathy-wiki-capture
description: |
  Capture-authoring protocol for the main agent. Read on demand when a TRIGGER fires (per `using-karpathy-wiki/SKILL.md`). Defines how to format a capture, how to invoke `bin/wiki capture`, body-size floors, and the subagent-report workflow.
---

# karpathy-wiki capture

You loaded this skill because a TRIGGER fired (per the loader). Your job
is to write a capture file (or move a file into `inbox/` for raw-direct
ingest), then return to the user's task.

## Single capture entry point

All chat-driven captures go through ONE command:

```bash
echo "$BODY" | bin/wiki capture \
  --title "<one-line title>" \
  --kind chat-only \
  --suggested-action create|update|augment
```

For chat-attached (a real file accompanies the conversation), pass the
absolute path of that file via `--evidence-path`:

```bash
echo "$BODY" | bin/wiki capture \
  --title "<one-line title>" \
  --kind chat-attached \
  --suggested-action create|update|augment \
  --evidence-path /absolute/path/to/source/file.ext
```

Or for long bodies:

```bash
bin/wiki capture \
  --title "<one-line title>" \
  --kind chat-only \
  --suggested-action create \
  --body-file /tmp/body.md
```

`--evidence-path` is REQUIRED for `--kind chat-attached` and
`--kind raw-direct`, REJECTED for `--kind chat-only`. The path lands
verbatim in the capture's `evidence:` frontmatter and propagates to
the manifest's `origin` field — the iron-rule contract that lets the
ingester trace every wiki page back to its source.

`bin/wiki capture` handles wiki resolution (which wiki the capture goes
to), prompts the user for setup if needed, writes the capture file,
and spawns the detached ingester. You do NOT write to
`.wiki-pending/` directly. You do NOT call `wiki-spawn-ingester.sh`
directly.

## Trigger

Triggers are listed in the loader (`using-karpathy-wiki/SKILL.md`).
This skill assumes a trigger has fired and you're now writing.

## Capture file format

See `references/capture-schema.md` for the canonical frontmatter
schema. Key fields you set when invoking `bin/wiki capture`:

- `--title`: one-line title (becomes filename slug + capture title).
- `--kind`: `chat-only` (no file evidence) | `chat-attached` (file +
  conversation delta) | `raw-direct` (you do NOT write this; it's for
  drop-zone ingestion).
- `--suggested-action`: `create` (new page) | `update` (replace
  existing) | `augment` (add to existing).

The body is read from stdin OR `--body-file <path>`.

## Body sufficiency

Per `references/capture-schema.md`:

| Kind | Floor | What goes in the body |
|---|---|---|
| `chat-only` | 1500 b | Every durable claim, exact details (URLs, version numbers, error messages), every decision-with-rationale, every gotcha, sources cited. |
| `chat-attached` | 1000 b | The conversation-delta — what the conversation added that the file doesn't cover. The file is the bulk; you owe the delta in full. |
| `raw-direct` | none | You don't write raw-direct bodies. The SessionStart hook or `wiki ingest-now` auto-generates them when a file appears in `inbox/`. |

A `chat-only` body must clear 1500 bytes with content, not filler. Required:

- Every durable CLAIM — fact, number, version, commit, percentage, decision.
- Every CONCRETE DETAIL the ingester cannot guess — exact URLs, package names, error messages, command snippets, code examples (5-15 lines), numeric thresholds, version ranges.
- Every DECISION made WITH its rationale — *"we chose X because Y failed on Z"* is a complete unit. *"we chose X"* alone is not.
- Every CONTRADICTION, GOTCHA, OR CAVEAT observed.
- SOURCES — doc URLs, arxiv IDs, GitHub repos with star counts as-of the session.

NOT in the body:

- Pleasantries, meta-commentary, "let me check", "good question".
- Process over output: wrong turns, reasoning trail, "I thought X but then Y". Keep the resolution; drop the detour.
- The user's questions verbatim — they're context, not content. Capture the ANSWER, not the question.

If the ingester rejects your capture (`needs-more-detail: true`), expand the body in place and re-spawn. Do NOT ignore the rejection.

## Subagent reports — DO NOT write a capture body

When a research subagent returns a file with durable findings, the report IS the capture. Move the file to `<wiki>/inbox/`:

```bash
mv <subagent-report-path> <wiki>/inbox/<basename>
wiki ingest-now <wiki>          # or wait for next SessionStart
```

`wiki ingest-now` triggers the same drift-scan + drain that SessionStart runs, but on demand. Use this when the user is still in the active session and wants the report ingested before they close the terminal.

Subagent-report bodies frequently exceed several KB; rewriting them as a `chat-only` capture body wastes tokens AND produces an inferior wiki page (the body summarizes what the file already says).

## Mode change

If the user asks to change the wiki mode for this directory:

```bash
wiki use project    # captures go to ./wiki/ only
wiki use main       # captures go to ~/wiki/ only
wiki use both       # captures fork to ./wiki/ AND ~/wiki/
```

Confirm in one line. The mode is persisted in `<cwd>/.wiki-config`
(project or both) or `<cwd>/.wiki-mode` (main-only). See
`references/capture-schema.md` and the v2.4 spec for details.

## Order matters: reply first, then capture

Reply to the user FIRST. The user is waiting; capture mechanics are
not. After your reply emits, write any captures whose triggers fired
(via `bin/wiki capture`), then run a turn-closure check.

## Turn closure — before you stop

Before emitting your final assistant message, check:

```bash
ls "<wiki_root>/.wiki-pending/" 2>/dev/null | grep -v '^archive$\|^schema-proposals$' | head -20
```

If the output lists any `.md` file OR any `.md.processing` file older
than 10 minutes, the turn is NOT done. Handle the pending captures
first (rejection-handling, stalled-recovery, missed-capture from
earlier turns), then re-check, then close the turn.

This is a self-discipline rule until a Stop-hook gate is wired.

## What's NOT in this skill

- The ingester's behavior (orientation, page format, manifest
  protocol). That lives in `karpathy-wiki-ingest/SKILL.md` and is
  loaded by the spawned ingester only. The main agent never reads it.
- Iron laws and announce-line contract. Those live in the loader
  (`using-karpathy-wiki/SKILL.md`) — single source of truth.
