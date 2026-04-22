# Superpowers skill-style guide — applying obra's patterns to the Karpathy Wiki v2 skill

**Subject studied:** `obra/superpowers` at commit `8a5edab282632443` (v5.0.7)
**Repo signal:** 164,129 stars, 14,353 forks, 315 open issues, last commit 2026-04-16
**Source material:** `/Users/lukaszmaj/dev/bigbrain/research/obra-superpowers-8a5edab282632443.txt` (~720 KB, 22,088 lines, full repo)
**Live repo:** https://github.com/obra/superpowers (recent commits, open/closed issues and PRs)
**Target to apply this to:** the v2 Karpathy Wiki skill described in `/Users/lukaszmaj/dev/bigbrain/plans/karpathy-wiki-v2-design.md`

---

## Section 1 — Why superpowers is good

Reading 15 SKILL.md files, the writing-skills meta-skill, the hook scripts, the PR template, and the last month of commits/issues, the principles that come into focus are not cosmetic. They are behavioral.

### 1.1 Every skill is TDD for process documentation

The defining insight, stated plainly in `skills/writing-skills/SKILL.md`:

> Writing skills IS Test-Driven Development applied to process documentation. You write test cases (pressure scenarios with subagents), watch them fail (baseline behavior), write the skill (documentation), watch tests pass (agents comply), and refactor (close loopholes). **Core principle:** If you didn't watch an agent fail without the skill, you don't know if the skill teaches the right thing.

This is not a slogan. The `systematic-debugging/` directory ships with `test-academic.md`, `test-pressure-1.md`, `test-pressure-2.md`, `test-pressure-3.md` — actual pressure scenarios the skill was hardened against. The `skills/writing-skills/testing-skills-with-subagents.md` reference is 400 lines of how to adversarially test a skill. Obra empirically designed these skills against real rationalizations he watched agents produce.

Corollary: every piece of load-bearing language in a superpowers SKILL.md is there because an agent violated the rule without it. That's why the style looks almost legalistic — it is. It's patched against concrete failure modes.

### 1.2 Descriptions are triggers, not summaries

From `writing-skills/SKILL.md`:

> Testing revealed that when a description summarizes the skill's workflow, Claude may follow the description instead of reading the full skill content. A description saying "code review between tasks" caused Claude to do ONE review, even though the skill's flowchart clearly showed TWO reviews (spec compliance then code quality). When the description was changed to just "Use when executing implementation plans with independent tasks" (no workflow summary), Claude correctly read the flowchart and followed the two-stage review process. **The trap:** Descriptions that summarize workflow create a shortcut Claude will take. The skill body becomes documentation Claude skips.

This is the most important single insight in the repo for anyone writing a skill description. Every superpowers description obeys this rule.

### 1.3 Token parsimony at the discoverable surface, detail one level down

Only frontmatter is pre-loaded at session start; once SKILL.md is read it competes with conversation history. Superpowers keeps SKILL.md bodies to 100-300 lines and pushes heavy material into sibling files linked directly, never nested two deep. From `anthropic-best-practices.md`: "Keep references one level deep from SKILL.md... Claude may partially read files when they're referenced from other referenced files" (using `head -100` previews instead of full reads).

### 1.4 Bulletproofing against rationalization, not naive correctness

A naive skill says "write tests first." A superpowers skill says: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST. Write code before the test? Delete it. Start over. **No exceptions:** Don't keep it as 'reference'. Don't 'adapt' it while writing tests. Don't look at it. Delete means delete." Then adds an 11-row `| Excuse | Reality |` rationalization table, a "Red Flags — STOP and Start Over" list, and the one-liner "**Violating the letter of the rules is violating the spirit of the rules.**" Every one of those is a response to an observed agent workaround.

The systematic-debugging `CREATION-LOG.md` documents this explicitly as "Bulletproofing": **Language choices** ("ALWAYS" / "NEVER", not "should" / "try to"; "even if faster"; "STOP and re-analyze"; "Don't skip past"); **Structural defenses** (Phase 1 required, can't skip to implementation; single hypothesis rule; explicit failure mode); **Redundancy** ("NEVER fix symptom" appears 4 times in different contexts).

### 1.5 One voice, one vocabulary

"Your human partner" appears 40+ times across the skills. Never "the user." Never "you and your user." It's a deliberate frame that positions the agent as a junior collaborator — and per `CLAUDE.md` it's a tested choice: "PRs that rewrite the project's voice... will be rejected." The repo rejects "compliance" rewrites that restructure for Anthropic's published style without eval evidence, because the wording is eval-tuned.

Other vocabulary signals that recur everywhere:
- "Iron Law" (block-quoted in code fences) for non-negotiable rules
- "Red Flags — STOP" as a literal section heading for failure-mode lists
- "Rationalization" tables with `| Excuse | Reality |` columns
- "Use when..." to open every description
- "Announce at start:" lines that force the agent to declare its skill use aloud

### 1.6 Cross-platform from the start (but not uniformly)

The hook system is the most technically interesting part of the repo. `hooks/session-start` is a single bash script that detects Cursor vs Claude Code vs Copilot CLI via env vars and emits different JSON shapes. `hooks/run-hook.cmd` is a cmd+bash polyglot for Windows via Git Bash. Per-platform plugin manifests (`.claude-plugin/`, `.cursor-plugin/`, `gemini-extension.json`) kept in sync by `scripts/bump-version.sh`. Tool-name maps in `using-superpowers/references/{codex,copilot,gemini}-tools.md`.

But obra does NOT force uniformity. `dispatching-parallel-agents` and `subagent-driven-development` degrade on Gemini CLI (no Task tool) and require an opt-in TOML flag on Codex. The philosophy: write for Claude Code, map tool names, state what degrades where.

### 1.7 Real-user-pain signal from issues and commits

Last month's signal:
- **Recent commits** are overwhelmingly cross-platform plumbing ("sync-to-codex-plugin", "README updates for Codex", "Windows path sanitization"). Skills themselves are stable.
- **Issue #1220** — one user measured 73 KB / ~17,800 tokens of duplicated `using-superpowers` bootstrap re-injected across 13 SessionStart firings (startup/clear/compact) over 57 hours. Real pain point with the SessionStart-injects-SKILL-content pattern. Relevant to our wiki hooks.
- **Issue #1237** — brainstorming's visual-companion server auto-exits after 30 min inactivity with no signal to the agent. Long-running subprocesses need a liveness probe readable by the agent.
- **Issue #1245** — "models add unrequested naive time estimates to design docs" — even tuned skills keep discovering new rationalizations.
- **Closed PRs** — 90%+ unmerged. The 94% rejection rate in `CLAUDE.md` is real.

---

## Section 2 — The superpowers SKILL.md template

Distilled from reading all 13 SKILL.md files in the repo:

Sections, in order (include only the ones that apply):

1. **Frontmatter** — `name` (kebab-case), `description` (single-line "Use when..."). Two fields only. Max 1024 chars total.
2. **Title** (`# Skill Name` in Title Case).
3. **Overview** — 1-3 sentences. Then `**Core principle:**` (one-line invariant, bolded). Then `**Violating the letter of the rules is violating the spirit of the rules.**` if discipline skill. Then `**Announce at start:** "I'm using the [name] skill to [purpose]."` if workflow skill.
4. **The Iron Law** (discipline skills only) — code-fenced `NO X WITHOUT Y FIRST`, followed by "Do A? Delete it. Start over." and a **No exceptions:** bullet list of closed loopholes.
5. **When to Use** — `**Use when:**` (concrete triggers), `**Don't use when:**` (anti-triggers), optional `**Use this ESPECIALLY when:**` for pressure scenarios.
6. **The Process / Phases / Steps** — numbered, 4-7 items, each 1-5 lines. Graphviz flowchart only if ordering is non-obvious.
7. **Red Flags — STOP** — bulleted list of thought patterns in quotes, ending with `**ALL of these mean: STOP. [action].**`
8. **Common Rationalizations** — `| Excuse | Reality |` table.
9. **Quick Reference** — scannable table for common operations.
10. **Common Mistakes / Anti-Patterns** — `**[Name]**` with `**Problem:**` / `**Fix:**` bullets.
11. **Integration** — `**Called by:**`, `**Pairs with:**`, `**Required sub-skill:**` lists of cross-skill names.
12. **Real-World Impact** (optional, last) — 2-4 measured bullets.

### Notes on the template

- **Frontmatter:** exactly two fields, `name` and `description`, max 1024 chars total. Quotes only when description contains a colon or angle bracket.
- **No emojis.** Zero across 13 SKILL.md files. ✅/❌ appear only inside `<Good>`/`<Bad>` code blocks.
- **No first person** — "you" is addressed TO the agent; descriptions are third-person (injected into system prompt).
- **Flowcharts:** graphviz `dot` blocks, only for non-obvious decision points. Rendered via obra's `render-graphs.js`.
- **Good/Bad examples** wrap in `<Good>`/`<Bad>` XML tags (TDD skill uses this repeatedly).
- **Length:** TDD 370, systematic-debugging 300, verification-before-completion 140, brainstorming 165, using-git-worktrees 220. Average ~200 lines. Writing-skills (660) is the outlier meta-skill.
- **Reference files:** siblings of SKILL.md, linked directly, never nested. Kebab-case `.md`. Example: `systematic-debugging/{condition-based-waiting,defense-in-depth,root-cause-tracing}.md`.
- **Scripts:** `scripts/` subdirectory, extensionless (the repo uses `session-start` not `session-start.sh` to avoid Claude Code's Windows auto-`bash` prepending — see comment in `hooks/run-hook.cmd`).

---

## Section 3 — Description-writing playbook

Trigger accuracy IS the skill. If the description is wrong, the skill never runs. If the description summarizes the workflow, the agent reads the description and skips the skill body.

### 3.1 The rule

> Description starts with "Use when..." and describes triggering conditions ONLY, not workflow.

### 3.2 Five annotated examples from superpowers

**1. `test-driven-development`:** *"Use when implementing any feature or bugfix, before writing implementation code"* — terse (13 words), explicit trigger + explicit temporal gate. Zero mention of red-green-refactor or "watch tests fail" — all body content.

**2. `systematic-debugging`:** *"Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes"* — three synonymous triggers maximize match rate. "Before proposing fixes" cuts off "I'll just try a quick fix." No "root cause" / "four phases" in the description.

**3. `verification-before-completion`:** *"Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always"* — 37 words because this fires on every "done" claim. Four parallel triggers, enumerated situations, slogan tail. Mild workflow leak ("requires running verification commands") probably earned through pressure testing.

**4. `brainstorming`:** *"You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation."* — breaks the "Use when" convention with authority framing. Four synonymous triggers. Second sentence mildly workflow-y but vague enough not to short-circuit reading the body.

**5. `using-superpowers`:** *"Use when starting any conversation - establishes how to find and use skills, requiring Skill tool invocation before ANY response including clarifying questions"* — maximally broad trigger because this is the always-on skill. The tail is an injected constraint (fire before answering) the agent needs at description level, not buried in the body.

### 3.3 Derived playbook for our wiki skill's description

Apply these rules:
1. **Open with "Use when..."** (or "TRIGGER when..." — obra doesn't use that phrasing, but our v1 does and it works fine).
2. **List 3-7 concrete triggers as parallel items**, each a situation or user phrase. Synonyms multiply the match surface.
3. **Mention both question-shaped and event-shaped triggers.** Question-shaped ("user asks what we know about X") triggers the query path. Event-shaped ("file added to raw/", "research subagent returns a file") triggers capture/ingest.
4. **Include a "DO NOT TRIGGER" clause.** Obra doesn't always do this, but superpowers relies on skill-level priority ordering the user never configures. Our wiki skill has a harder discrimination problem ("is this question actually about the wiki's domain?") so explicit anti-triggers earn their tokens.
5. **Do NOT summarize ingest/query/lint/doctor workflows.** Don't say "captures events, ingests in the background, and serves queries." That invites the shortcut.
6. **Keep under 500 chars if possible**, 1024 max. Our v1 description is already at the edge (~750 chars) — probably fine; do not grow it further.
7. **Terminology match.** If users say "research" and "notes" and "remember this," put those exact words in the description. This is `anthropic-best-practices.md`'s keyword-coverage advice.

---

## Section 4 — Hook patterns

### 4.1 Superpowers uses exactly one hook, and uses it carefully

`hooks/hooks.json`:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start", "async": false }
        ]
      }
    ]
  }
}
```

Three observations:
1. **Only `SessionStart`.** No Stop hook, no PreToolUse, no PostToolUse. The only "automation" point is when a new session/compaction/clear happens.
2. **`type: command`, not `type: prompt`.** The hook runs a shell script; it never asks the LLM to do anything. Shell-only hooks are deterministic, fast, and don't burn tokens. This directly validates the design-doc choice to replace our v1 Stop-hook `type: prompt` with `type: command`.
3. **The `matcher`** filters to startup|clear|compact, not `*`. This is a bug fix — previous versions matched everything, and issue #1220 measured the cost (~17.8k tokens over 57 hours across 13 firings, even with the matcher, because "clear" and "compact" both fire the hook).

### 4.2 What the SessionStart hook actually does

It injects context. It reads `skills/using-superpowers/SKILL.md`, escapes it for JSON, and emits one of three output shapes depending on the platform (Cursor's `additional_context`, Claude Code's `hookSpecificOutput.additionalContext`, or Copilot CLI's top-level `additionalContext`). The payload starts with `<EXTREMELY_IMPORTANT>You have superpowers.` Importantly: the hook does NOT invoke any LLM. It also doesn't start background processes (per issue #1237 those are fragile).

### 4.3 When to use hooks vs let the agent decide

Reading across superpowers, the implicit rule is:

> Use a hook only to **inject context** or **run deterministic shell work**. Never to trigger LLM-led actions. If you want the agent to do something conditionally, put that in the SKILL.md body, not in a hook `type: prompt`.

Our v1 uses `type: prompt` on Stop to tell the LLM to update the wiki. This is the pattern obra walked away from. The design doc already replaces it with `type: command` that writes marker files.

### 4.4 Superpowers-style hook pattern for our wiki skill

**SessionStart hook** (shell-only):
- Detect wiki presence in cwd.
- Diff `raw/` SHAs against `.manifest.json` — write new captures if drift.
- Check `.wiki-pending/` — if populated, spawn a headless drain ingester (via `nohup claude -p ... &` or platform equivalent).
- Reclaim stale `.processing` and `.lock` files by timestamp.
- Exit sub-second.

**Stop hook** (shell-only):
- Same drift check (cheap).
- If captures pending, spawn drain ingester.
- Optional: if `transcript_sweep: true` in `.wiki-config`, spawn cheap-model subprocess reading the transcript for missed captures. This DOES invoke an LLM, but headlessly in a separate process — it does not ask the foreground agent to do anything.
- Exit sub-second.

**Cost awareness (from issue #1220):** SessionStart fires on `startup|clear|compact`. If your hook injects context into the model, that cost multiplies across long sessions with multiple clears/compacts. Our wiki SessionStart hook should emit **zero model-visible context** — it's purely shell-side housekeeping. No `additionalContext` emission. The agent already has SKILL.md loaded on demand via the description match; it doesn't need bootstrap injection.

**Cross-platform note:** use the polyglot `run-hook.cmd` pattern from superpowers — a single file that's both a valid `.cmd` batch script and a valid bash script via a bash-comment trick. One file, two interpreters. This lets the same hook work on Windows via Git Bash without carrying a separate `.ps1` variant.

---

## Section 5 — Anti-patterns and explicit warnings from `writing-skills`

Pulled verbatim from `skills/writing-skills/SKILL.md` and the bundled `anthropic-best-practices.md`. If we do any of these, we're building a worse skill than obra would.

1. **Descriptions that summarize workflow** — covered in Section 3. The #1 anti-pattern. Writing-skills gives the example: BAD: "Use when executing plans - dispatches subagent per task with code review between tasks" ← Claude follows the description instead of reading the skill.

2. **Narrative examples** — "In session 2025-10-03, we found empty projectDir caused..." Too specific, not reusable. Our wiki skill must resist anecdotes like "last session the wiki missed the JWT insight." Keep examples generic and pattern-shaped.

3. **Multi-language dilution** — `example-js.js`, `example-py.py`, `example-go.go`. Mediocre quality, maintenance burden. One excellent example beats many mediocre ones. Low risk for us (markdown-native).

4. **Deeply nested references** — "Claude may partially read files when they're referenced from other referenced files... Keep references one level deep from SKILL.md." No `SKILL.md → A.md → details.md` chains.

5. **`@` prefix on references (force-loads context)** — "`@skills/testing/...` force-loads, burns context." Use `**REQUIRED SUB-SKILL:** Use superpowers:skill-name` instead.

6. **Flowcharts for reference material** — "Use flowcharts ONLY for non-obvious decision points, process loops, 'A vs B' decisions. Never for reference material, code examples, or linear instructions."

7. **Time-sensitive information** — BAD: "If you're doing this before August 2025, use the old API." For our skill: don't write "as of 2026, Claude supports X." Use an "Old patterns" details-collapsed section.

8. **Inconsistent terminology** — mixing "API endpoint" / "URL" / "route" confuses the model. Lock our vocabulary: **capture** (not "note"/"draft"/"event"), **ingest** (not "process"/"digest"), **wiki page** (not "doc"/"entry"), **raw source** (not "input"/"original"), **main wiki** / **project wiki**, **drift** (for raw-source hash change).

9. **Skipping bulletproofing** — discipline skills need: close every loophole explicitly, address spirit-vs-letter inline, rationalization table, Red Flags list, violation symptoms in the description. Our wiki skill has *one* discipline-like rule: don't skip ingestion because "this is trivial." Bulletproof only the wiki-worthy decision; everything else is discretionary.

10. **Creating skills without failing tests** — "NO SKILL WITHOUT A FAILING TEST FIRST." We won't run full subagent-pressure-testing on v2 (overhead too high), but at minimum eyeball-test the wiki-worthy decision against 5-10 scenarios before shipping.

---

## Section 6 — Applying superpowers style to Karpathy Wiki v2

The design doc lists a lot of machinery (captures, ingesters, locks, manifests, propagation, three-tier lint, two hook types). This section maps that onto superpowers-style skill structure and identifies where our stateful, cross-platform nature forces deviation.

### 6.1 Single skill or multi-skill package?

Superpowers ships 13 skills but only one plugin. Each skill is single-purpose and they cross-reference via `**REQUIRED SUB-SKILL:** superpowers:name` lines. For our case, the design doc says "one skill replaces the existing `wiki` + `project-wiki`." That's the right call — the two roles (main vs project) share 95% of the same operations and only differ in scope and propagation direction. Superpowers' tdd + debugging example shows that when skills diverge in workflow, they split; when they share workflow, they stay unified.

**Recommendation:** One skill, named `wiki` (not `karpathy-wiki` — the reference is known but the name shouldn't force a lineage). Role handling is internal.

### 6.2 Frontmatter

```yaml
---
name: wiki
description: Use when the user asks about something that might be in a persistent knowledge base (what we know about X, how we handled Y, what did we decide about Z), when research files or notes appear in a conversation, when the user says "remember this" / "add to wiki" / "capture that", when a wiki/ directory exists in the project, or when evidence emerges during a session that should be preserved across sessions. DO NOT trigger for: time-sensitive questions that need fresh data, simple file reads, questions clearly outside the wiki's domain, or when the user explicitly says to skip the wiki.
---
```

Draft. ~650 chars. Uses the "Use when" opening. Lists both question-shaped and event-shaped triggers. Lists phrases the user actually says. Includes the DO NOT clause. Does NOT describe the ingest workflow, auto-init, captures, locks, or any other internal machinery — that's all body material.

### 6.3 SKILL.md skeleton, in superpowers style

Structure the body as: Overview (with Core principle + Announce-at-start) → Two Roles (main vs project) → When to Use → Auto-Init → What Counts as Wiki-Worthy → The Capture → Ingest → Query Loop → User Commands (`wiki doctor`, `wiki status`) → Red Flags — STOP → Cross-Platform (pointer to reference) → Integration.

Sample opening:
```markdown
## Overview

A persistent, compounding knowledge base built from the work that happens in
every session. Research, decisions, patterns, and gotchas get captured as the
user works and merged into interlinked markdown pages. Nothing is lost between
sessions. Ask questions naturally — the wiki answers.

**Core principle:** Capture is cheap, ingest is patient, query is natural.

**Announce on first wiki action per session:** "Using the wiki skill to
[capture this / ingest pending captures / answer from wiki]."
```

Sample closing (mandatory sections):
```markdown
## Red Flags — STOP
If you catch yourself thinking:
- "This conversation is too trivial to capture" → capture anyway if it resolved confusion
- "I'll write the wiki page directly instead of a capture" → don't; captures are the only entry point
- "Let me ingest this in the foreground real quick" → no; ingest is background only

## Integration
**Pairs with:**
- **superpowers:brainstorming** — wiki auto-captures brainstorm design docs
- **superpowers:writing-plans** — wiki captures plans as reference material
```

### 6.4 Reference files (one level deep)

Siblings of SKILL.md:
- `references/capturing.md` — exact capture file format, YAML spec, what goes in the body, examples of good vs poor captures.
- `references/ingesting.md` — ingester's decision algorithm, lockfile protocol, manifest update, propagation criteria.
- `references/commands.md` — exact behavior of `wiki doctor` and `wiki status` including output formats.
- `references/platform-support.md` — cross-platform table (like `using-superpowers/references/*-tools.md`) for headless commands and fallback.
- `references/schema.md` — default `schema.md` bootstrap content and evolution rules.

Scripts live in `scripts/`:
- `scripts/session-start` (extensionless, polyglot pattern from superpowers)
- `scripts/stop-sweep`
- `scripts/ingest` (the background ingester, invoked in headless mode)
- `scripts/wiki-doctor`
- `scripts/wiki-status`
- `scripts/run-hook.cmd` (polyglot launcher on Windows)

### 6.5 Hooks

`hooks.json`:
```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|clear|compact",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/run-hook.cmd\" session-start", "async": false }] }
    ],
    "Stop": [
      { "matcher": ".*",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/run-hook.cmd\" stop-sweep", "async": false }] }
    ]
  }
}
```

Shell-only. No `type: prompt`. No context injection (we do not re-inject SKILL.md on every session; the description+body already load on demand and SessionStart firing many times per long session would burn tokens per issue #1220). The scripts should each exit in under a second of shell work; any LLM spawn is detached via the headless-command pattern and doesn't block the hook.

### 6.6 Places we must deviate from superpowers style

Superpowers skills are **stateless process documentation**. Our wiki is a **stateful artifact-manipulating skill**. That changes four things:

1. **Reference files serve as data-format specs, not supplemental prose.** `references/capturing.md` is the canonical capture-file format — source of truth the ingester reads at runtime. If someone reports an ingester bug, first question is "does this capture conform to it?" Superpowers has no equivalent. Add a TOC block at the top of each data-format reference per `anthropic-best-practices.md`.

2. **On-disk safety invariants.** Our skill owns files that survive sessions. We need rules superpowers doesn't: "never modify files in `raw/`", "never delete captures outside `.wiki-pending/` except after ingestion", "read before every page edit", "acquire locks before editing." These are the Iron Laws specific to us.

3. **Concurrency is operator-facing.** Multiple ingesters, locks, timeouts, stale reclaim. The protocol goes in `references/ingesting.md`; the symptoms (`wiki status` reports stale locks, `wiki doctor` reclaims them) go in SKILL.md.

4. **Auto-init is destructive** (`git init`, directory creation). Add a rule obra doesn't need: **"Never auto-init if a `.wiki-config` exists but doesn't match the expected role — ask the user."** This is the wiki analogue of the "verify `git check-ignore` before creating a worktree" safety rule in `using-git-worktrees`.

### 6.7 What we can lift directly from superpowers

`**Announce at start:**` preamble; Iron-Law block-quoted fence; `| Excuse | Reality |` table; Red Flags — STOP bullets; Pairs-with / Called-by / REQUIRED SUB-SKILL integration; polyglot `run-hook.cmd`; graphviz flowcharts for non-obvious decisions (probably just two places — capture-vs-don't, propagation-direction); sibling-scripts model for hook runners; kebab-case names; single-line third-person "Use when..." descriptions. The "your human partner" vocabulary is optional — it's a superpowers tradition, not a universal standard; "the user" is fine for our skill.

### 6.8 Length budget

Target SKILL.md length: **250-350 lines**, max 500. Superpowers median. Our design doc is 550 lines; most of that becomes reference files, not SKILL.md.

---

## Section 7 — Top 10 reusable phrases and patterns from superpowers

Copy these literally (with wiki-appropriate substitutions) into our SKILL.md and reference files.

1. **"Use when [trigger], before [point-of-no-return action]."** From TDD and systematic-debugging. Anchors description to trigger *and* temporal gate. For us: *"Use when the user asks about domain knowledge, before answering from memory."*

2. **The Iron Law block** — triple-fenced `NO X WITHOUT Y FIRST`, immediately after overview. For us: *`NO INGEST WITHOUT A CAPTURE FIRST`* and *`NO PAGE EDIT WITHOUT READING THE PAGE FIRST`*.

3. **"Violating the letter of the rules is violating the spirit of the rules."** One sentence after Core Principle. Cuts off "I'm following the spirit" rationalizations. Copy verbatim.

4. **"Don't X. Don't Y. Don't Z."** The "no exceptions" enumeration. From TDD: "Don't keep it as 'reference'. Don't 'adapt' it while writing tests. Don't look at it. Delete means delete." For us: *"Don't edit a page without reading it first. Don't skip the lock for small edits. Don't ingest in the foreground. Don't bypass the ingester to write a page directly."*

5. **"Use this ESPECIALLY when:"** — the pressure-invoking header. From systematic-debugging: "under time pressure, 'just one quick fix' seems obvious, you've already tried multiple fixes." For us: *"the conversation feels 'just about one quick thing,' you think the user will remember this themselves, you're about to close the session without checking `.wiki-pending/`."*

6. **`| Excuse | Reality |` rationalization table.** For us: *"This is obvious, no need to capture" → "What's obvious now is forgotten next month. Capture."* / *"The ingester will catch it later" → "The ingester only runs on captures. No capture = no ingest."* / *"I'll write the page myself" → "You'll write one page. The ingester updates ten. Write the capture."*

7. **"Announce at start: 'Using the [skill] skill to [purpose].'"** Forces declaration, reduces silent-skip. For us: *"Using the wiki skill to [capture / ingest / answer from wiki]."*

8. **`**REQUIRED SUB-SKILL:** Use superpowers:[name]`** — exact phrasing for cross-skill hard requirements.

9. **Red Flags — STOP pattern** — header, then `If you catch yourself thinking:` + bulleted quoted rationalizations, ending with `**ALL of these mean: STOP. [action].**` Catches internal monologue, not just behavior.

10. **Platform-mapping 2-column table** — from `using-superpowers/references/*-tools.md`. For us: `| Claude Code | Codex | OpenCode | Gemini CLI |` with rows like `claude -p "…"` / `codex exec "…"` / `opencode run "…"` / `gemini -p "…"` for the headless-invocation contract.

---

## Closing observations

**What superpowers gets most right:** skill-writing as an engineering discipline with its own testing methodology, enforced through a rejection process (94% rejection rate, hard-gate PR template, closed "compliance" PRs from Anthropic). Result: 13 skills with one recognizable voice that demonstrably shape agent behavior.

**Where we should be stricter than obra:** background-process liveness. Obra's visual-companion server silently expiring mid-session (issue #1237) is exactly the failure mode our ingesters could hit. Keep stale-file reclaim timeouts tight (5-10 minutes) and document them in SKILL.md, not buried in a reference file.

**Where we should be less strict than obra:** bulletproofing. Over-bulletproofing would bloat SKILL.md past 500 lines. Reserve the Iron-Law-and-rationalization-table treatment for the 2-3 rules that actually matter: capture-don't-skip, read-before-write, never-ingest-in-foreground. Everything else is descriptive workflow, not discipline enforcement.

The recent commit history is overwhelmingly cross-platform plumbing, not skill content — the skills stabilized months ago. Obra's style is close to a fixed point. Copying it is a good bet.
