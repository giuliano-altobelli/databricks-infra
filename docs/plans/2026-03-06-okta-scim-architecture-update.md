# Okta SCIM Architecture Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update the Databricks architecture documentation so it reflects Okta SCIM user provisioning, automatic membership in `okta-databricks-users` at account and workspace scope, Terraform-managed follow-up group assignment only when requested, and a simple Mermaid diagram for that workflow.

**Architecture:** Keep the existing Unity Catalog and developer workflow intact, but remove any wording that implies users are created from `infra/aws/dbx/databricks/us-west-1/identify.tf`. Add a concise identity provisioning section that makes the Okta-to-Databricks lifecycle explicit, includes a simple Mermaid flow, and preserves the separation between baseline access and additional group assignment.

**Tech Stack:** Markdown documentation, Terraform configuration references

---

### Task 1: Update the architecture narrative

**Files:**
- Modify: `ARCHITECTURE.md`

**Step 1: Replace Terraform-managed user provisioning references**

Update the personal catalog wording so it no longer says users come from `local.identity_users` in Terraform. Keep the `personal.<user_key>` namespace model, but describe users as Okta-approved and SCIM-provisioned instead.

**Step 2: Add an identity provisioning section**

Document that:
- Okta SCIM provisions users into Databricks.
- Approved users are automatically added to `okta-databricks-users`.
- That membership exists at both account and workspace scope.
- `infra/aws/dbx/databricks/us-west-1/identify.tf` is only for assigning additional Databricks groups on request.
- Unity Catalog privileges remain managed separately.

**Step 3: Add a Mermaid identity workflow diagram**

Insert a small Mermaid flowchart under the identity provisioning section that shows:
- Okta approval
- SCIM provisioning into Databricks
- Automatic `okta-databricks-users` membership at account scope
- Automatic `okta-databricks-users` membership at workspace scope
- Optional additional group assignment through `infra/aws/dbx/databricks/us-west-1/identify.tf`

**Step 4: Clarify the developer flow prerequisites**

Add a short note near the developer experience flow stating that the developer must already be provisioned through Okta SCIM and present in `okta-databricks-users` before the documented workspace flow begins.

### Task 2: Verify the documentation change

**Files:**
- Modify: `ARCHITECTURE.md`

**Step 1: Review the diff**

Run: `git diff -- ARCHITECTURE.md docs/plans/2026-03-06-okta-scim-architecture-update.md`

Expected: the diff shows removal of Terraform-managed user creation wording and addition of the Okta SCIM plus `okta-databricks-users` explanation and Mermaid workflow.

**Step 2: Re-read the updated sections**

Run: `sed -n '1,220p' ARCHITECTURE.md`

Expected: the document reads cleanly, stays scoped to account and workspace identity behavior, and does not imply Unity Catalog access changes from the Okta group alone.
