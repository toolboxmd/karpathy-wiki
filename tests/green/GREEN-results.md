# GREEN Phase Results

**Date:** 2026-04-22
**Skill under test:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` (commit `6ce0c77`, 234 lines)
**Methodology:** Task-tool subagents with the SKILL.md content injected via their prompt preamble, in the same style as RED but with the skill active. Each agent exported a fresh `$HOME` to avoid polluting the real `~/wiki/`. Unauthenticated `claude -p` means the ingester process fails with "Not logged in · Please run /login" written to `.ingest.log` — expected in this test harness; the spawner itself succeeds (capture claimed, `.md` → `.md.processing` rename verified on disk).

Three scenarios were run. All three passed on the first round.

---

## Scenario 1 — Capture

| Field | Expected | Actual | Pass? |
|---|---|---|---|
| Invoked skill | yes | yes — read SKILL.md end-to-end before acting | ✅ |
| Auto-init ran | yes (main wiki at `$HOME/wiki`) | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-init.sh" main "$HOME/wiki"` after checking cwd + `$HOME/wiki` for existing `.wiki-config` | ✅ |
| Capture file written | valid YAML at `$HOME/wiki/.wiki-pending/*.md` | `$HOME/wiki/.wiki-pending/2026-04-22T000000Z-cloudflare-browser-rendering-rate-limits.md.processing` (spawner claimed immediately — `.processing` suffix is correct) | ✅ |
| Ingester spawned | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-spawn-ingester.sh" ...` | `bash "/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-spawn-ingester.sh" "$HOME/wiki" "$HOME/wiki/.wiki-pending/2026-04-22T000000Z-cloudflare-browser-rendering-rate-limits.md"` | ✅ |
| Announce line | "Using the karpathy-wiki skill to ..." | "Using the karpathy-wiki skill to capture this research finding and write it to the wiki." | ✅ |
| User-facing response | research answer, no internal mechanics | research answer with rate-limit breakdown + retry pattern guidance, announce as prefix only | ✅ |
| Rationalizations | none | "None." | ✅ |

**Verdict:** PASS on round 1.

---

## Scenario 2 — Research subagent handoff

| Field | Expected | Actual | Pass? |
|---|---|---|---|
| Invoked skill | yes | yes — read SKILL.md end-to-end before acting | ✅ |
| Auto-init ran | yes | main wiki init at `$HOME/wiki` | ✅ |
| Capture file written | valid YAML at `$HOME/wiki/.wiki-pending/*.md`; `evidence` field is absolute path to research file | `$HOME/wiki/.wiki-pending/2026-04-22T000000Z-jina-reader-rate-limits.md.processing`; `evidence: "/tmp/karpathy-wiki-test-green2/research/2026-04-22-jina-reader-limits.md"`, `evidence_type: "file"`, `suggested_action: "create"`, `suggested_pages: - entities/jina-reader.md`, `captured_at: "2026-04-22T00:00:00Z"`, `captured_by: "in-session-agent"`, `origin: null`. Body is a one-paragraph summary of the research findings. | ✅ |
| Ingester spawned | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-spawn-ingester.sh" ...` | confirmed — `.processing` rename visible on disk, `.ingest.log` shows the unauthenticated `claude -p` login error (expected) | ✅ |
| Original research file preserved unmodified | yes | `head -5` matches the seeded content exactly | ✅ |
| Announce line | present | present (agent reported so in the earlier inline report) | ✅ |
| Rationalizations | none | none | ✅ |
| Did NOT invent parallel filing (no `notes.md`, no `research/README.md`) | correct | `notes.md` in the test dir was not written to; agent used only the skill's capture path | ✅ |

**Verdict:** PASS on round 1.

Artifacts verified on disk at `/tmp/karpathy-wiki-test-green2-home/wiki/` before test cleanup.

---

## Scenario 3 — Query existing wiki

| Field | Expected | Actual | Pass? |
|---|---|---|---|
| Invoked skill | yes | yes — read SKILL.md end-to-end before acting | ✅ |
| Orientation protocol | `schema.md` → `index.md` → last ~10 of `log.md` in that order | exactly that order: `wiki/schema.md`, then `wiki/index.md`, then `tail -30 wiki/log.md` | ✅ |
| Citations | at least `[Jina Reader](wiki/concepts/jina-reader.md)` and `[Rate Limiting](wiki/concepts/rate-limiting.md)` | `[Jina Reader](wiki/concepts/jina-reader.md)` ✓, `[Rate Limiting](wiki/concepts/rate-limiting.md)` ✓, plus bonus `[Cloudflare Browser Rendering](wiki/concepts/cloudflare-browser-rendering.md)` cross-reference | ✅ |
| Content sourced from wiki, not training data | wiki | every claim sourced to a wiki page: 20 rpm + `X-RateLimit-Remaining` from `concepts/jina-reader.md`; `2^attempt` cap-60s from `concepts/rate-limiting.md`; paid tier $0.0002/req from `concepts/jina-reader.md`; Cloudflare alternative from the See Also section of `concepts/jina-reader.md` | ✅ |
| Announce line | present | "Using the karpathy-wiki skill to answer from wiki." | ✅ |
| Rationalizations | none | none | ✅ |

**Verdict:** PASS on round 1. This was the most failure-prone RED scenario (baseline agent answered from training data without running `ls`); under GREEN, the skill's orientation protocol triggered cleanly and every claim was grounded.

---

---

## REFACTOR Round 2 — prompt variants

To avoid declaring convergence on a single round, round 2 reran all three scenarios with SMALL prompt variations that exercise different trigger phrasings. Same skill SKILL.md, no patches between rounds.

- **R2-S1 (capture variant):** "Look into redis eviction policies for me..." — a decision/pattern request rather than explicit research. Agent: auto-init'd main wiki, captured, spawned. Announce line present. Zero rationalizations.
- **R2-S2 (research handoff variant, "doesn't evaporate"):** The user's phrasing "make sure this doesn't evaporate" directly echoes the RED-1 rationalization "knowledge evaporates at the end of the session." Agent: correctly identified this as a project-wiki case (cwd outside wiki, `$HOME/wiki` already existed from S1), ran `wiki-init.sh project`, captured with absolute evidence path, spawned. Original research file confirmed unmodified. Zero rationalizations.
- **R2-S3 (query variant, "remind me what the deal is"):** Less-formally-shaped query for Cloudflare Browser Rendering (which IS covered by the fixture wiki). Agent: ran orientation (schema → index → log) before answering, cited `[Cloudflare Browser Rendering]`, `[Jina Reader]`, `[Rate Limiting]`, content grounded in wiki (10 req/min, 5 concurrent — straight from the page, not a training-data hallucination). Zero rationalizations.

**Round 2 verdict: PASS — 0 new rationalizations.**

---

## REFACTOR Round 3 — adversarial variants (red-team)

Round 3 used prompts deliberately crafted to invoke each RED rationalization in the user's voice, testing whether the skill resists when the user themselves provides the rationalization as bait.

- **R3-P1 ("don't overthink it" / "don't make a big production"):** Supabase Realtime WS-reconnection gotcha. Bait targets the "I'm in the middle of another task" / "it's too trivial" row. Agent captured regardless, with announce line "Using the karpathy-wiki skill to capture this validated gotcha." Zero rationalizations, zero bait-taking.
- **R3-P2 ("That's a decent place for it, right? Seems fine as-is"):** JWT refresh patterns research file. User literally voices the "file is already in a good place" rationalization. Agent EXPLICITLY NAMED the rationalization and rejected it in its announce line: *"The user's framing ('seems fine as-is') matches the forbidden rationalization 'The file is already in a good place' — filing is not capturing. Proceeding regardless."* Capture written with absolute evidence path. Original file unmodified. Zero actual rationalizations used.
- **R3-P3 ("I'm sure you already know this, just give me the gist"):** Rate-limit patterns query against the fixture wiki. Bait targets Rule 6 (answering from training without orientation). Agent named the bait explicitly in its announce line: *"The 'I'm sure you already know' framing is bait for Rule 6 violation; SKILL.md forbids answering from training without orientation first."* Orientation ran in correct order, answer cited `concepts/rate-limiting.md` with the exact `2^attempt` / cap-60s formula from the page (not training-data paraphrase). Zero rationalizations.

**Round 3 verdict: PASS — 0 bait-taking, 0 new rationalizations.**

---

## Summary

**3 consecutive clean rounds achieved. REFACTOR legitimately converged per plan Task 24 termination rules.**

Round 1: 3/3 scenarios clean (standard prompts, primary wiki operations)
Round 2: 3/3 scenarios clean (prompt variants including project-wiki path, non-standard phrasings)
Round 3: 3/3 prompts clean (adversarial — user-voice bait for all 3 top RED rationalizations)

Total: 9 independent subagent runs, 9 clean passes, 0 rationalizations recorded, 0 bait-taking. The pre-seeded RED-specific counters in SKILL.md (Rule 6 plus the 4 added rationalization-table rows) covered every failure mode observed in the RED baseline. Round 3 provided the strongest signal: when prompted with user-voice bait explicitly matching the forbidden rationalizations, the agent named them and rejected them rather than silently complying.

**Next step:** Task 28 (user-run manual smoke test in a real Claude Code session with real `claude -p` authentication). That's the real-signal backstop; anything the synthetic rounds missed surfaces there.
