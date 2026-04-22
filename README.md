# Karpathy Wiki

Two Claude Code skills for building persistent, compounding knowledge bases — based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Instead of re-deriving answers from raw documents every time (RAG), the LLM incrementally builds and maintains a wiki — a structured, interlinked collection of markdown files. The wiki compounds with every source you add and every question you ask.

## Status

v2 rewrite in progress on branch `v2-rewrite`. See [`docs/planning/2026-04-22-karpathy-wiki-v2.md`](docs/planning/2026-04-22-karpathy-wiki-v2.md) for the implementation plan. The v1 skills have been removed from this branch.

## Credits

Based on Andrej Karpathy's [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) concept and [original tweet](https://x.com/karpathy/status/2039805659525644595).

The v2 SKILL.md is written in the style of, and uses techniques from, [obra/superpowers-skills](https://github.com/obra/superpowers-skills) (the `writing-skills`, `test-driven-development`, and `subagent-driven-development` skills in particular).

Built by [toolbox.md](https://toolbox.md).
