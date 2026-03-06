# README Onboarding Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update `README.md` so new users understand the current Databricks onboarding and group-assignment process.

**Architecture:** Keep the README intentionally narrow. Document the account-level and workspace-level onboarding flow through Okta, then describe the Terraform PR step for additional Databricks group membership and briefly note that Unity Catalog permissions are granted to groups.

**Tech Stack:** Markdown documentation

---

### Task 1: Add onboarding guidance to the README

**Files:**
- Modify: `README.md`

**Step 1: Add the getting-started steps**

Document the current process in order:
- Request Databricks access through Okta.
- Admin approves the request.
- The approved Okta group provisions the user into Databricks and adds the user to `okta-databricks-users` at the account and workspace levels.
- The Okta group maps to the target workspace.
- The user opens a PR to be added to the appropriate Databricks group in `infra/aws/dbx/databricks/us-west-1/identify.tf`.

**Step 2: Add the access-model note**

State that Unity Catalog permissions are assigned to groups and that groups can then receive access to catalogs, schemas, and objects.

**Step 3: Add the current-scope note**

State that this is the current process and that the team will iterate from here.

### Task 2: Verify the README change

**Files:**
- Modify: `README.md`

**Step 1: Review the diff**

Run: `git diff -- README.md docs/plans/2026-03-06-readme-onboarding-update.md`

Expected: the diff shows the new onboarding flow, the access-model note, and the current-scope note.

**Step 2: Re-read the README**

Run: `sed -n '1,220p' README.md`

Expected: the README is concise, reflects the approved account-level and workspace-level onboarding flow, and stops short of a full Unity Catalog permissions workflow.

