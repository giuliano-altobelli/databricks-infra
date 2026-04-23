# SCIM Gate Group Validation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce optional workspace SCIM gate membership for every user declared in `users_groups` before applying memberships, roles, workspace assignments, or entitlements.

**Architecture:** Add one opt-in module input (`scim_gate_group_display_name`) and keep existing behavior unchanged when it is empty. When enabled, resolve the workspace gate group via `databricks.workspace`, normalize usernames, compute a deterministic missing-user list, and fail at plan with one batched precondition error. Reuse the module's existing output-precondition validation pattern.

**Tech Stack:** Terraform (HCL), Databricks Terraform provider (`data.databricks_group`, `data.databricks_user`), root-stack plan flow with `direnv` + OAuth M2M.

---

## File Structure

- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/variables.tf`  
  Responsibility: add the opt-in gate input variable and description.
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/main.tf`  
  Responsibility: add gate activation, workspace gate lookup, normalized membership diff locals.
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/outputs.tf`  
  Responsibility: add plan-time precondition with batched actionable error.
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/SPEC.md`  
  Responsibility: update module contract and failure modes for SCIM gate validation.
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/README.md`  
  Responsibility: document the new opt-in gate behavior and usage example.

Notes:
- `identify.tf` remains caller-controlled; no default gate value should be hardcoded in the module.
- Follow @superpowers:test-driven-development by reproducing failure/success via `terraform plan` before/after implementation.

## Chunk 1: Module Gate Logic

### Task 1: Add Gate Input Contract

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/variables.tf:111-140`
- Test: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/variables.tf`

- [ ] **Step 1: Add the new input variable**

```hcl
variable "scim_gate_group_display_name" {
  description = "Optional workspace-scoped SCIM gate group display name. When set, all users must be members of this group."
  type        = string
  default     = ""
}
```

- [ ] **Step 2: Run module validation syntax check**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit contract change**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/variables.tf
git commit -m "feat(users_groups): add optional SCIM gate group input"
```

### Task 2: Implement Gate Lookup + Missing-User Diff

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/main.tf:1-145`
- Test: live plan scenario from `infra/aws/dbx/databricks/us-west-1`

- [ ] **Step 1: Capture current (failing) behavior vs requirement**

Use a workspace scenario where one `users` entry is known to be outside `okta-databricks-users` (temporary local-only input change if needed).  
Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars
```
Expected before implementation: plan does **not** fail for gate membership (this demonstrates the gap).

- [ ] **Step 2: Add gate locals and workspace gate lookup**

Implement locals/data source pattern:

```hcl
locals {
  scim_gate_enabled = var.enabled && trimspace(var.scim_gate_group_display_name) != ""
}

data "databricks_group" "scim_gate" {
  provider = databricks.workspace
  for_each = local.scim_gate_enabled ? { gate = trimspace(var.scim_gate_group_display_name) } : {}

  display_name = each.value
}
```

- [ ] **Step 3: Add normalized membership comparison locals**

Implement deterministic missing-user computation:

```hcl
locals {
  requested_users_normalized = {
    for user_key, user in local.enabled_users :
    user_key => lower(trimspace(user.user_name))
  }

  scim_gate_member_usernames = local.scim_gate_enabled ? toset([
    for member in data.databricks_group.scim_gate["gate"].users :
    lower(trimspace(member.user_name))
  ]) : toset([])

  scim_gate_missing_users = local.scim_gate_enabled ? sort([
    for user_key, user in local.enabled_users :
    "${user_key} (${user.user_name})"
    if !contains(local.scim_gate_member_usernames, lower(trimspace(user.user_name)))
  ]) : []
}
```

- [ ] **Step 4: Re-run module validation**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit logic change**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/main.tf
git commit -m "feat(users_groups): compute SCIM gate membership violations"
```

### Task 3: Enforce Batched Plan-Time Failure

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/outputs.tf:1-30`
- Test: live plan scenario from `infra/aws/dbx/databricks/us-west-1`

- [ ] **Step 1: Add precondition to `output.user_ids`**

```hcl
precondition {
  condition = !local.scim_gate_enabled || length(local.scim_gate_missing_users) == 0
  error_message = "users must be members of workspace gate group \"${trimspace(var.scim_gate_group_display_name)}\" before identity assignments are applied. Missing (${length(local.scim_gate_missing_users)}): ${join(", ", local.scim_gate_missing_users)}."
}
```

- [ ] **Step 2: Run live negative scenario (should now fail)**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars
```
Expected: plan fails with one batched precondition error listing `user_key (user_name)` entries missing from gate group.

- [ ] **Step 3: Run live positive scenario (should pass)**

Use a scenario where all requested users are gate members.  
Run the same plan command and confirm no SCIM gate precondition failure.

- [ ] **Step 4: Commit enforcement change**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/outputs.tf
git commit -m "feat(users_groups): enforce SCIM gate membership precondition"
```

## Chunk 2: Spec, Docs, and Final Verification

### Task 4: Update Module Spec + README

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/SPEC.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/README.md`
- Test: markdown consistency + example accuracy

- [ ] **Step 1: Update `SPEC.md`**

Document:
- new input `scim_gate_group_display_name`,
- opt-in behavior,
- provider/data lookup for workspace gate group,
- new failure mode and precondition semantics.

- [ ] **Step 2: Update `README.md` usage**

Add usage snippet:

```hcl
module "users_groups" {
  # ...
  scim_gate_group_display_name = "okta-databricks-users"
}
```

Add note that the module does not manage gate group membership itself.

- [ ] **Step 3: Commit docs update**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/SPEC.md infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/README.md
git commit -m "docs(users_groups): document SCIM gate validation"
```

### Task 5: End-to-End Verification + Final Commit

**Files:**
- Verify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/{variables.tf,main.tf,outputs.tf,SPEC.md,README.md}`

- [ ] **Step 1: Format changed Terraform files**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups fmt
```
Expected: no diff after rerun.

- [ ] **Step 2: Validate module and root scenario**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate -var-file=terraform.tfvars
```
Expected: both validations succeed.

- [ ] **Step 3: Run final root plan**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars
```
Expected: gate behavior matches scenario (success when compliant; batched failure when non-compliant).

- [ ] **Step 4: Create final squashing commit if required by team workflow**

```bash
git status
git log --oneline -n 5
```

- [ ] **Step 5: Request code review with validation evidence**

Use @superpowers:requesting-code-review and include:
- exact plan command used,
- relevant precondition error output,
- compliant scenario output summary.
