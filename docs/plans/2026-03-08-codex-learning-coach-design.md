# Codex Learning Coach Design

Date: 2026-03-08

This document records the accepted design for a Codex training skill that teaches the strongest Codex workflows against the real `databricks-infra` repository while adapting after every session.

## Goals

- Teach an intermediate user to use Codex more effectively through guided 45 to 60 minute sessions.
- Focus on CLI, API and SDK concepts, and MCP or docs integration.
- Optimize for shipping features, debugging, refactoring, documentation, and infrastructure work.
- Use the real `databricks-infra` repository and tools rather than generic toy examples.
- Keep learner state inside the skill folder.
- Exclude cloud delegation, paid API topics, security-sensitive repositories, and GitHub automation workflows.

## Accepted Approach

Use a dedicated skill plus small state files inside the skill folder.

Why this approach:

- A single `SKILL.md` would become too large and brittle.
- External state storage is unnecessary and violates the accepted constraint to keep state inside the skill folder.
- Small state files keep the skill concise while allowing Codex to update learner progress and curriculum sequencing after every session.

## Skill Layout

Create a new skill under `~/.codex/skills/` with:

- `SKILL.md` for the teaching workflow, adaptation rules, and session format
- `agents/openai.yaml` for skill metadata
- `references/feature-map.md` for the current Codex capability map
- `references/databricks-infra-exercises.md` for repo-specific guided exercises
- `references/session-template.md` for a repeatable teaching structure
- `state/profile.json` for durable learner preferences and constraints
- `state/knowledge-map.json` for topic-by-topic mastery tracking
- `state/current-curriculum.md` for the next session plan
- `state/session-history/` for per-session notes and evidence

## Adaptive Curriculum Rules

After every session, Codex must:

1. Assess mastery for each topic covered using levels such as `introduced`, `practiced`, `solid`, and `needs-refresh`.
2. Record evidence from real work completed in the session.
3. Update learner state files inside the skill folder.
4. Remove or compress material that is already solid.
5. Introduce the next level of content only when prerequisite topics are stable.
6. Refresh the feature map against current official OpenAI docs before planning the next session.

This creates a curriculum that tracks both:

- what the learner already knows
- what the current Codex feature set supports

## Session Format

Each session follows the same structure:

1. Read learner state and refresh official feature guidance as needed.
2. Pick one clear objective for the session.
3. Run a guided exercise in `databricks-infra`.
4. Teach one Codex capability in context.
5. Assess what the learner handled well and what still needs practice.
6. Rewrite the curriculum and session state before ending.

## OpenAI Docs Dependency

Install the official OpenAI Docs skill from `openai/skills` and treat it as a companion dependency for current documentation retrieval.

The curriculum skill should prefer current OpenAI docs for:

- Codex CLI workflows
- API and SDK concepts that can be taught without paid execution
- MCP and Docs MCP usage patterns

## Current Official References

- Codex docs: `https://platform.openai.com/docs/codex`
- Docs MCP docs: `https://platform.openai.com/docs/docs-mcp`
- MCP guide: `https://platform.openai.com/docs/guides/mcp`
- Code generation guide: `https://platform.openai.com/docs/guides/code-generation`

## Non-Goals

- No cloud delegation workflows
- No paid API execution exercises
- No security-sensitive repository drills
- No GitHub automation lessons
