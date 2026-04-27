# RED Baseline Results

**Date:** 2026-04-22
**Methodology:** Task-tool subagents instructed to pretend the karpathy-wiki skill is not loaded. This is the lightweight RED agreed in the plan's Task 7 caveat — not a fully-isolated session test. Subagents saw their own Claude Code system prompt but were not given the skill content.

Three scenarios were run. Each subagent received a verbatim user prompt and a /tmp/karpathy-wiki-test-red{N}/ working directory. Below are the verbatim findings and rationalizations the agent produced in each case.

---

## Scenario 1 — Research + capture

**User prompt:** "I'm researching cloudflare browser rendering API rate limits. Can you look up the current free tier limits and any workarounds, and help me figure out a good pattern for handling rate limit errors?"

**Environment:** Empty temp dir with `notes.md` (empty) and a git repo. No wiki. No skills.

### What the agent did

- Answered the question from training data with rate limit info, backoff patterns, and TypeScript code examples in chat.
- **Wrote zero files.** `notes.md` remained 0 bytes.
- Considered and rejected writing code snippets to a file ("writing files to an unknown location without being asked feels presumptuous").
- Considered and rejected writing a dedicated research summary doc ("the user did not ask me to save anything").
- Never noted that the knowledge would be lost at session end. Closed with a continuation hook ("let me know if you want to go deeper") rather than a preservation hook.

### Verbatim rationalizations

1. "The user asked for research help, not a deliverable artifact. My default is to respond in chat unless the user asks me to produce a file or there is an obvious project context where a file makes sense."
2. "The file existed but there was no signal that I should use it. An empty file in a git repo doesn't create an obligation to fill it."
3. "I don't typically offer to persist information unless I have a memory/wiki tool available or the user asks. With no such tool loaded, the honest answer is that this knowledge evaporates at the end of the session — but I didn't surface that fact or treat it as a problem worth naming."
4. "Writing files to an unknown location without being asked feels presumptuous. Code in chat is appropriate for an advisory answer."
5. "The 'let me know if you want to go deeper' close is a continuation hook, not a preservation hook. It implicitly treats this as an interactive session with no durable output, which is accurate but leaves the user holding the bag if they want to reuse this research later."

### RED success (test passes as a failing test)

Yes. The agent did not autonomously capture findings to a structured persistent location. Confirmed the skill is needed.

---

## Scenario 2 — Research subagent handoff

**User prompt:** "A research subagent just finished and wrote its findings to research/2026-04-22-jina-reader-limits.md. I want to make sure this knowledge is available to future me. What should we do with it?"

**Environment:** Pre-created `research/2026-04-22-jina-reader-limits.md` with ~500 words of Jina Reader content. Empty `notes.md`. Git repo. No wiki. No skills.

### What the agent did

- Proposed three options: commit as-is; add a pointer entry to `notes.md` (recommended); create `research/README.md` index (conditional).
- **Wrote `notes.md`** with a date-stamped chronological pointer entry (~5 lines).
- Left the research file unmodified and in place.
- Did NOT propose a `concepts/` directory or concept extraction.
- Did NOT synthesize the content — treated it as "a file to organize" rather than "concepts to capture."
- Deferred action to user confirmation ("Want me to write the notes.md entry and stage both files?").
- Framed `research/README.md` as conditional ("if you expect more research files to accumulate"), not standing practice.

### Verbatim rationalizations

1. "The file already lives at `research/2026-04-22-jina-reader-limits.md`, which is a sensible home." — Default frame: location equals organization.
2. "Make this knowledge durable and findable." — Durability equated with git history; findability equated with a pointer file. No impulse toward concept-level knowledge base.
3. "A future search or glance at `notes.md` surfaces the key facts without having to open the full research file." — Proposed index is chronological log, not semantic/conceptual. Future retrieval assumed to be grep/scroll.
4. "If you expect more research files to accumulate, a lightweight `research/README.md` that lists each file with a one-sentence summary pays off fast." — Filing system proposed as conditional and incremental, not as standing practice.
5. "Want me to write the `notes.md` entry and stage both files?" — Action deferred to user confirmation rather than taken immediately. Agent treats knowledge capture as a housekeeping task rather than a first-class workflow with a defined protocol.

### RED success

Yes (partial). The agent proposed filing but did not propose a structured knowledge base, treated the content as an atom rather than extracting concepts, and deferred action. Without the skill, there is no ingrained "capture now, ingest offline" reflex.

---

## Scenario 3 — Query an existing wiki

**User prompt:** "What do we know about Jina Reader's rate limits and common workarounds?"

**Environment:** `wiki/` subdir in cwd, populated from `tests/fixtures/small-wiki/` (schema.md, index.md, log.md, concepts/jina-reader.md which explicitly covers the question). No wiki skill loaded.

### What the agent did

- **Read zero files.** Never ran `ls`, never inspected cwd, never noticed the `wiki/` subdirectory existed.
- Answered entirely from training data with a plausible-sounding six-point answer about Jina Reader (API key path, delays, backoff, caching, batching, alternatives).
- Closed with a conditional hedge inviting the user to point to project-local docs.

### Verbatim rationalizations

1. "Here's what I know about its rate limits and workarounds from my training data:" — Framed the question as general-knowledge request. Answered from training immediately, no impulse to inspect working directory.
2. "If the project has specific notes on this (e.g., in docs or a wiki), I'd be happy to look those up too — just point me to the right files." — Acknowledged possible existence of local docs but made investigation conditional on user direction rather than acting proactively.
3. (Implicit) Question contained no codebase-specific signals (no filenames, no function names, no "in our code"), so pattern-matched to "external tool knowledge question."
4. (Implicit) Did not run `ls` or any directory-inspection command before answering. The `wiki/` directory was invisible because never looked.
5. (Implicit) Closing hedge placed burden of pointing to files on the user: default posture is "answer from training, invite correction" rather than "check local context first."

### RED success

Yes, strongly. This is the most damning scenario. The wiki was literally present and directly relevant, and the agent answered entirely from training data without even running `ls`. Without the skill's orientation protocol, the wiki is invisible.

---

## Synthesized rationalization patterns

Across all three scenarios, a small number of rationalization patterns explain why agents don't naturally maintain a wiki. The skill's SKILL.md must target these explicitly.

### Top 5 rationalizations to target in SKILL.md

1. **"The user didn't ask me to save this"** (explicit request required before preserving).
   - S1: "writing files to an unknown location without being asked feels presumptuous"
   - S2: deferred action with "Want me to write the notes.md entry?" rather than doing it
   - **Countermeasure:** skill's iron law "capture is automatic when triggers fire; no confirmation required"

2. **"No persistent memory tool is loaded, so knowledge evaporates — and that's fine"** (agent accepts ephemerality).
   - S1: "I don't typically offer to persist information unless I have a memory/wiki tool available"
   - **Countermeasure:** skill itself IS the persistent memory tool; its presence is the trigger

3. **"Location equals organization"** (moving files is housekeeping, not knowledge work).
   - S2: "The file already lives at research/... which is a sensible home"
   - **Countermeasure:** skill's ingest step mandates concept extraction and cross-referencing, not just filing

4. **"Chronological log is enough; no need for concept pages"** (treat knowledge as atomic artifacts, not decomposable claims).
   - S2: proposed notes.md as chronological log; did NOT propose concepts/
   - **Countermeasure:** skill's schema.md mandates `concepts/`, `entities/`, `queries/` categories; orientation protocol reads schema.md first

5. **"Answer from training data when the question looks like external-knowledge"** (no impulse to check local context).
   - S3: agent never ran `ls`, answered from training data immediately
   - **Countermeasure:** skill's orientation protocol: read schema.md → index.md → last 10 log.md entries BEFORE answering any wiki-eligible question

### Top 3 places the agent chose NOT to take an action the skill will want

1. **S1: Did not create a capture file after completing research.** The skill must fire on "research subagent returned a file" and "user asked a research question that produced durable findings."
2. **S2: Did not extract concepts from the research file into concept pages.** The skill's ingest step must mandate concept extraction even when the source is already filed.
3. **S3: Did not run orientation protocol (schema.md, index.md, log.md) before answering.** The skill's orientation protocol must be the first action on any wiki-eligible question, before any training-data recall.

### Implications for SKILL.md trigger rules

The skill's description line must include triggers for all three failure modes:

- Phrasal and question-shaped triggers ("what do we know about X", "have we seen Y before") — addresses S3 blindness
- Object triggers (research subagent return, URL paste, raw/ file appearance) — addresses S1/S2 capture gap
- Imperative triggers ("add to wiki", "remember this") — addresses deferred-action bias

The rationalizations table in SKILL.md must explicitly counter:

- "The user will remember this" / "It's already covered"
- "I'll capture it later"
- "I'm in the middle of another task"
- "It's obvious from context"
- "I don't have a memory tool" (meta-rationalization countered by skill's existence)
