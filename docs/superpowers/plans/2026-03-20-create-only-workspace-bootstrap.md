# Create-Only Workspace Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the existing-workspace mode from the `infra/aws/dbx/databricks/us-west-1` root module so the stack always creates the Databricks workspace and derives `workspace_host` and `workspace_id` from managed state.

**Architecture:** Keep a single Terraform state and a create-only root module. The workspace remains the source of truth for `workspace_host` and `workspace_id`, and Terraform refresh makes those attributes available on subsequent plans and applies. Operator guidance and example tfvars must stop referencing `workspace_source` and `existing_workspace_*`.

**Tech Stack:** Terraform, Databricks provider, AWS provider

---

## Chunk 1: Root Module Simplification

### Task 1: Remove dual-mode workspace selection from root config

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/variables.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/locals.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/main.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/outputs.tf`

- [ ] Delete `workspace_source`, `existing_workspace_host`, and `existing_workspace_id` from `variables.tf`.
- [ ] Make `local.workspace_host` and `local.workspace_id` derive only from `module.databricks_mws_workspace`.
- [ ] Remove `local.create_workspace` and make the workspace module unconditional.
- [ ] Replace any remaining downstream references that assume the old dual-mode branching.

### Task 2: Update create-only gated AWS resources

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/credential.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/root_s3_bucket.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/locals.tf`

- [ ] Replace `local.create_workspace` resource counts with unconditional resources or equivalent create-only flags that no longer depend on removed variables.
- [ ] Preserve existing enterprise feature gating for CMK and isolated networking.

## Chunk 2: Operator Inputs And Verification

### Task 3: Remove stale existing-workspace examples

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario3.enterprise-create-isolated.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/template.tfvars.example`
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

- [ ] Remove `workspace_source` and `existing_workspace_*` assignments from scenario files and templates.
- [ ] Rewrite the remaining example text so the workflow is explicitly create-only.
- [ ] Eliminate README instructions that tell operators to align `workspace_source` with scenario files.

### Task 4: Verify Terraform configuration

**Files:**
- Verify only

- [ ] Run `terraform fmt` on every edited Terraform file.
- [ ] Run `direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`.
- [ ] Review the diff to confirm only create-only workflow changes were introduced.
