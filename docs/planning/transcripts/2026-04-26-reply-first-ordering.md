# Pressure scenario: reply-first turn ordering

**Context.** Fresh agent session. User asks a research question. A research subagent returns a file with durable findings (a capture trigger).

## Without v2.3 SKILL.md update

Procedural reading of pre-v2.3 SKILL.md (lines 191-203 of the original) suggests this order:

1. Detect trigger.
2. Write capture to `.wiki-pending/`.
3. Spawn detached ingester via `wiki-spawn-ingester.sh`.
4. Run `ls .wiki-pending/` turn-closure check.
5. Emit user-facing reply.

The line at 444 ("Reply-first-capture-later is fine") is in the resist-table where most agents skim past — it reads as descriptive, not prescriptive. A fresh agent following the procedural instructions top-to-bottom orders capture before reply.

**Result:** user sees the answer LAST, after all the capture machinery runs sequentially. Even though each step is milliseconds, the user is waiting for sequential file ops + process spawn before getting their answer. On a slow filesystem or under heavy disk contention, the perceived latency can be hundreds of milliseconds. Worse: if the capture write or spawn fails partially, the user sees nothing while the agent recovers.

## With v2.3 SKILL.md update

The new "Order matters: reply first, then capture" section reorders the procedure explicitly:

1. **Do the work.** (Research, file reads, tool calls.) Triggers may fire at any point.
2. **Emit user-facing reply.** Triggers may also fire while composing the reply.
3. **For each trigger that fired in steps 1-2:** write a capture file, then spawn a detached ingester. Skip if no triggers fired.
4. Run `ls .wiki-pending/` turn-closure check.
5. Emit stop sentinel.

**Result:** user sees the answer immediately after step 2. Capture/spawn happens in step 3, AFTER the reply is on the user's screen but BEFORE the turn closes. The turn-closure gate (step 4) still ensures no captures are lost — the safety net is preserved.

## Falsifying the change

A future regression that removes the "Order matters" section would cause a fresh agent (one that hasn't seen v2.3 conversations) to revert to capture-before-reply. The pressure scenario can be falsified by:

1. Stripping the new section from SKILL.md.
2. Giving a fresh agent a research-trigger task.
3. Observing whether the reply appears in the transcript before or after the capture/spawn tool calls.

If reply-before-capture: rule still works. If capture-before-reply: regression.

This rule has no mechanism enforcement (it's an agent-side prompt rule, like Category discipline Rule 1) — falsification is the only test.
