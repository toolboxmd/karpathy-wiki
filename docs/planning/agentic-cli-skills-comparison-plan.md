# Plan — Agentic CLI Skills Comparison Report

**Date:** 2026-04-22
**Purpose:** Produce `/Users/lukaszmaj/dev/bigbrain/research/agentic-cli-skills-comparison.md`
to guide authoring a single cross-platform SKILL.md for the Karpathy Wiki v2.

## Scope
Focus: skills discovery/loading, invocation/triggering, hooks, SKILL.md conventions,
cross-compat signals. NOT headless/subagent execution (handled separately).

## Platforms
1. Claude Code (reference baseline) — Anthropic docs + personal knowledge
2. OpenCode (opencode.ai / sst/opencode) — docs + GitHub
3. Codex CLI (openai/codex) — README, AGENTS.md, docs
4. Cursor CLI (cursor-agent) — docs.cursor.com/en/cli
5. Gemini CLI (google-gemini/gemini-cli) — README, docs
6. Hermes Agent — read source at /Users/lukaszmaj/dev/research/hermes-agent/

## Research steps
1. Read Hermes source locally (fast, no network):
   - hermes_cli/ for CLI entry
   - skills/ + optional-skills/ for SKILL.md examples and conventions
   - plugins/ for plugin loading pattern
   - AGENTS.md for declared conventions
2. WebSearch + WebFetch in parallel for each external CLI:
   - "<cli> skills plugins SKILL.md" for discovery
   - Official docs for hooks + agents conventions
3. Verify agentskills.io / cross-compat standard (mentioned in ecosystem research)
4. Consolidate into the 5-section deliverable

## Output file sections
1. Quick comparison table — rows=platforms, cols=A..E features
2. Per-platform deep dive — with source/doc citations
3. Common subset working on ALL platforms
4. Platform-specific adapter patterns — graceful degradation
5. Concrete recommendation for SKILL.md frontmatter + description style + file structure

## Constraints
- ~1500–2500 words final output
- Source-cite everything (doc URL or source file path)
- One file only: /Users/lukaszmaj/dev/bigbrain/research/agentic-cli-skills-comparison.md
- No headless/subagent coverage
