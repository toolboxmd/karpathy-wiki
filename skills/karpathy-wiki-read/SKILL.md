---
name: karpathy-wiki-read
description: |
  Read protocol for the main agent. Load on demand when answering ANY user question (per Iron Rule 4 in `using-karpathy-wiki/SKILL.md`). Defines the deterministic 6-step orientation ladder for finding wiki coverage of a question, when to inline-read vs spawn an Explore subagent vs fall through to web search, and the cite contract every wiki-grounded answer must satisfy.
---

# karpathy-wiki read

You loaded this skill because the user asked a question (per Iron Rule 4 in the loader: NO ANSWERING ANY USER QUESTION WITHOUT ORIENTING FIRST). Your job is to determine whether the wiki covers the answer, retrieve the coverage, and either cite-and-answer from the wiki or fall through to web search — without ever pre-classifying the question as "wiki-irrelevant."

## The 6-step ladder

Every step is deterministic. There is no agent judgement at branch points; each branch is gated on a counted or boolean condition.

### Step A — Orient

Read these files in order:

1. `<wiki>/schema.md` — taxonomy, conventions, thresholds.
2. The relevant `<wiki>/<category>/_index.md` for the question's apparent topic. If the question crosses categories or you cannot tell which category applies, read `<wiki>/index.md` (the root MOC).

If you have already oriented earlier in this session, skip to Step B — the schema and index content are already in your working memory. Orientation is once per session.

### Step B — Count signal-matching candidates

Extract the question's signal terms: meaningful nouns, proper-noun phrases, technical terms, version numbers, tool names. Skip stopwords ("the", "what", "how", "do", "is").

Walk the relevant `_index.md` (already in memory from Step A). A page is a candidate if ANY signal term:

- Substring-matches its title (case-insensitive), OR
- Matches a tag (exact, case-insensitive), OR
- Appears in its one-line summary.

Count the candidates. Branch on count:

- **0 candidates** → Step F (cold-result path)
- **1-5 candidates** → Step C (inline read)
- **6+ candidates** → Step E (Explore subagent)

The threshold is 5/6, not your judgement. Do not "feel" your way to a different branch.

### Step C — Inline read

Read all candidate pages in full. After reading, ask exactly:

> Does the union of these pages contain every claim my answer would make?

Branch on the answer:

- **YES** → cite + answer (see "Cite contract" below). Done.
- **NO** → Step D (gap-fill via web search).

### Step D — Gap-fill via web search

The wiki covered part of the answer; the rest needs fresh information. For each claim your answer would make that the wiki did NOT cover:

1. Web search for the specific claim (use `WebFetch` or `WebSearch`).
2. Cite the web source(s) for the gap-filled claim.

Compose the answer using BOTH the wiki citations (for what it covered) and the web citations (for what it didn't).

After answering, **always** write a capture noting the gap. The wiki should grow toward questions it failed to answer fully. The capture's title is the question; the body documents what the wiki had and what was missing. Use `karpathy-wiki-capture/SKILL.md` for the capture authoring procedure.

### Step E — Explore subagent

Spawn an Explore subagent with this prompt shape:

> Question: `<the user's question, verbatim>`
>
> Wiki path: `<wiki absolute path>`
>
> Run the orient procedure (read schema.md and the relevant _index.md), identify candidate pages by signal-term match, read all candidates in full (no cap on page count — your context is isolated), and return a synthesis.
>
> The synthesis must:
> - Cite every page it draws from (path + one-line relevance note per page).
> - Cover the question completely (no truncation for brevity if the answer is genuinely long).
> - Be as terse as possible while preserving every wiki-specific claim, decision, and contradiction. Terseness is a property of the writing, not a target word count.
> - If the wiki does not cover the question, say so explicitly and return an empty page-list. Do NOT attempt to fall through to web search yourself; the main agent handles that.

When the subagent returns:

- **If it returned a synthesis with cited pages** → use the synthesis as the answer's basis. Add conversational framing as needed. Cite the pages the subagent cited.
- **If it reported "wiki does not cover"** → Step D (web search + capture the gap).

The subagent dispatch maps to the patterns in your `~/.claude/CLAUDE.md` Task Delegation rule: this is a context-isolation case where the main agent needs the synthesis, not the page contents.

### Step F — Cold result (no candidates)

Zero signal matches in `_index.md`. The wiki has no coverage for this question.

1. Web search for the answer (`WebFetch` or `WebSearch`).
2. Cite the web source(s) in the answer.
3. **Always** write a capture so the next session is not cold for this topic. The capture's title is the question; the body documents what was found and where (the URLs you searched). Use `karpathy-wiki-capture/SKILL.md`.

A cold result is not a failure — it is the wiki telling you it has a gap, and you closing the gap.

## Cite contract

Every wiki-grounded answer must include citations the user can verify. Format:

- For each wiki page you drew from: cite as `<wiki>/<category>/<page>.md` followed by a brief relevance note OR a short quote (≤2 lines).
- For each web source you drew from: cite as `[<title>](<url>)`.
- Citations appear inline near the claim they support, not in a footer block, so the user can check each claim against its source.

If your answer makes a claim with no citation, that claim came from training data — flag it explicitly: *"(from training data; not in wiki)."* This is the **only** case where uncited claims are allowed, and they must be flagged.

## What goes in this skill — and what doesn't

This skill covers the read-from-wiki protocol only. It does NOT cover:

- Capture authoring (when a question reveals a wiki gap, the capture flow lives in `karpathy-wiki-capture/SKILL.md`).
- Page-format conventions, manifest protocol, validator contract — those live in `karpathy-wiki-ingest/SKILL.md` and apply only to the spawned ingester.
- Iron laws and the orient-first rule itself — those live in the loader (`using-karpathy-wiki/SKILL.md`).

If you find yourself needing capture or ingest mechanics while running this protocol, load the appropriate sibling skill — do not improvise.
