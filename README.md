# Karpathy Wiki

Two Claude Code skills for building persistent, compounding knowledge bases — based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Instead of re-deriving answers from raw documents every time (RAG), the LLM incrementally builds and maintains a wiki — a structured, interlinked collection of markdown files. The wiki compounds with every source you add and every question you ask.

## Skills

### `karpathy-wiki` — General-Purpose Knowledge Base

For research, learning, and personal knowledge management. You drop sources (articles, papers, notes) into `raw/`, the LLM builds and maintains a wiki.

**Auto-triggers on:**
- Adding sources to `raw/`
- Asking synthesis questions ("compare A and B", "what do we know about X")
- Requesting health checks ("lint the wiki", "find gaps")

### `karpathy-project-wiki` — Project Documentation

For codebases. The LLM reads your source code, docs, and git history, then builds a living wiki that stays current as the code evolves. You write code, the LLM writes the docs.

**Auto-triggers on:**
- Code changes (new modules, refactors, API changes)
- Architecture questions ("how does auth work", "explain the data flow")
- Documentation health checks ("is the wiki up to date")

## Install

Copy the skill folder to your Claude Code skills directory:

```bash
# General-purpose wiki
cp -r karpathy-wiki ~/.claude/skills/wiki

# Project wiki
cp -r karpathy-project-wiki ~/.claude/skills/project-wiki
```

## Usage

Once installed, just tell Claude:

```
Initialize a wiki for my research on [topic]
```

or for projects:

```
Initialize a project wiki for this codebase
```

The skills auto-trigger from there — the wiki stays current without you asking.

## Architecture

Each skill is a plugin with:

- **SKILL.md** — Schema defining wiki conventions, operations, and auto-invocation triggers
- **hooks.json** — `Stop` hook (checks for updates after every task) + `SessionStart` hook (detects drift)
- **scripts/** — Lightweight bash scripts for drift detection
- **references/** — Detailed operation workflows

## How It Works

Three layers (from Karpathy's pattern):

1. **Raw sources** — Your curated documents (or codebase for project-wiki)
2. **The wiki** — LLM-generated markdown with summaries, entity pages, concept pages, cross-references
3. **The schema** — SKILL.md defining conventions and workflows

Three operations:

1. **Ingest** — Process new sources, update 10-15 wiki pages per source
2. **Query** — Search wiki, synthesize answers, file valuable results back
3. **Lint** — Health check for contradictions, stale claims, orphan pages

## Credits

Based on Andrej Karpathy's [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) concept and [original tweet](https://x.com/karpathy/status/2039805659525644595).

Built by [toolbox.md](https://toolbox.md) — we make things that make things.
