# Codex Learning Coach Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create an adaptive Codex curriculum skill that teaches the best Codex workflows against `databricks-infra`, installs the official OpenAI Docs skill, and rewrites its curriculum after every session based on learner mastery and current official docs.

**Architecture:** Build a new skill in `~/.codex/skills/codex-learning-coach` with a concise `SKILL.md`, reference files, and state scaffolding. Pair it with the official OpenAI Docs skill from `openai/skills`, then validate the new skill with the skill-creator validation script.

**Tech Stack:** Markdown, YAML, JSON, local Codex skills, OpenAI official docs

---

### Task 1: Install the official OpenAI Docs skill

**Files:**
- Create: `~/.codex/skills/openai-docs/`

**Step 1: Discover the canonical skill path**

Run the curated skill listing helper and identify the official OpenAI Docs skill name and source path.

**Step 2: Install the skill**

Run the installer helper against `openai/skills` and install the OpenAI Docs skill into `~/.codex/skills`.

**Step 3: Verify installation**

Run a file listing against the installed directory and confirm `SKILL.md` exists.

### Task 2: Initialize the new curriculum skill

**Files:**
- Create: `~/.codex/skills/codex-learning-coach/`
- Create: `~/.codex/skills/codex-learning-coach/SKILL.md`
- Create: `~/.codex/skills/codex-learning-coach/agents/openai.yaml`
- Create: `~/.codex/skills/codex-learning-coach/references/`
- Create: `~/.codex/skills/codex-learning-coach/state/`

**Step 1: Scaffold the skill**

Use `init_skill.py` to create the new skill with `references` and `assets` support plus generated `agents/openai.yaml`.

**Step 2: Remove unused placeholders**

Delete any example or placeholder artifacts that are not needed for this skill.

**Step 3: Add initial state scaffolding**

Create the learner profile, knowledge map, current curriculum, and session history folder inside the skill.

### Task 3: Write the skill instructions

**Files:**
- Modify: `~/.codex/skills/codex-learning-coach/SKILL.md`

**Step 1: Write trigger metadata**

Describe the skill so it triggers for Codex onboarding, training, curriculum generation, progressive practice, and adaptive coaching requests.

**Step 2: Write the teaching workflow**

Document:
- session startup
- OpenAI docs refresh behavior
- guided exercise selection in `databricks-infra`
- assessment and evidence collection
- curriculum rewrite rules

**Step 3: Encode guardrails**

State the constraints:
- no cloud delegation
- no paid API topics
- no security-sensitive repositories
- no GitHub automations

### Task 4: Add compact references and state templates

**Files:**
- Create: `~/.codex/skills/codex-learning-coach/references/feature-map.md`
- Create: `~/.codex/skills/codex-learning-coach/references/databricks-infra-exercises.md`
- Create: `~/.codex/skills/codex-learning-coach/references/session-template.md`
- Create: `~/.codex/skills/codex-learning-coach/state/profile.json`
- Create: `~/.codex/skills/codex-learning-coach/state/knowledge-map.json`
- Create: `~/.codex/skills/codex-learning-coach/state/current-curriculum.md`

**Step 1: Write the feature map**

Summarize the current official Codex learning surface for CLI, API and SDK concepts, and Docs MCP usage. Keep the file concise and note that it must be refreshed from official docs before each session.

**Step 2: Write repo-specific exercises**

Create guided exercises rooted in `databricks-infra`, such as:
- tracing provider alias usage
- debugging Terraform module wiring
- repo documentation improvements
- small safe refactors

**Step 3: Write the session template and initial state**

Create a repeatable session template and initial learner state based on the user’s answers from this conversation.

### Task 5: Validate and inspect the skill

**Files:**
- Modify: `~/.codex/skills/codex-learning-coach/` as needed

**Step 1: Run skill validation**

Run `quick_validate.py` against the new skill.

**Step 2: Review generated metadata**

Open `agents/openai.yaml` and verify:
- the interface fields are present
- the default prompt explicitly mentions `$codex-learning-coach`
- the description is concise and aligned with the skill

**Step 3: Review installed skill contents**

List the final skill tree and confirm the expected references and state files exist.

### Task 6: Verify the repo artifacts for this planning work

**Files:**
- Create: `docs/plans/2026-03-08-codex-learning-coach-design.md`
- Create: `docs/plans/2026-03-08-codex-learning-coach-implementation.md`

**Step 1: Review the planning docs**

Run: `sed -n '1,240p' docs/plans/2026-03-08-codex-learning-coach-design.md`

Expected: the design doc records the approved goals, adaptive update model, session format, and OpenAI Docs dependency.

**Step 2: Review the implementation plan**

Run: `sed -n '1,320p' docs/plans/2026-03-08-codex-learning-coach-implementation.md`

Expected: the plan provides concrete files, steps, and validation actions for the skill build.
