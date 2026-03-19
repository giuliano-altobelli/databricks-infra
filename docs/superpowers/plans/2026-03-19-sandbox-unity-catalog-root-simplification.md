# Sandbox Unity Catalog Root Simplification Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove legacy Unity Catalog mode switching from the `sandbox` branch root and enforce sandbox-owned governed catalogs with a native Databricks metastore collision guard in a staged bootstrap-then-rollout workflow.

**Architecture:** Delete the root `uc_catalog_mode` / `uc_existing_catalog_name` interface and the legacy single-catalog caller, leaving `catalogs_config.tf` as the only catalog-definition path. Add a root-level collision guard that uses native Databricks data sources after a bootstrap apply has created the workspace and metastore assignment, then keep `output "catalogs"` authoritative while retaining `catalog_name` only as a compatibility alias to the sandbox personal catalog.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider `~> 1.84`, AWS provider `>= 5.76, <7.0`, workspace-scoped Databricks alias `databricks.created_workspace`, `direnv` with `DATABRICKS_AUTH_TYPE=oauth-m2m`

---

**Spec:** `docs/superpowers/specs/2026-03-19-sandbox-unity-catalog-root-simplification-design.md`

**User preference:** Do not commit during this session. Use `git diff` checkpoints instead of commit steps.

## File Structure

Modify these root Terraform files:

- `infra/aws/dbx/databricks/us-west-1/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/locals.tf`
- `infra/aws/dbx/databricks/us-west-1/main.tf`
- `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- `infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf`
- `infra/aws/dbx/databricks/us-west-1/outputs.tf`

Create this root Terraform file:

- `infra/aws/dbx/databricks/us-west-1/catalog_collision_check.tf`

Modify these operator-facing config and doc files:

- `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars`
- `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- `infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars`
- `infra/aws/dbx/databricks/us-west-1/scenario3.enterprise-create-isolated.tfvars`
- `infra/aws/dbx/databricks/us-west-1/template.tfvars.example`
- `infra/aws/dbx/databricks/us-west-1/README.md`

Responsibilities:

- `variables.tf`: remove the old Unity Catalog mode inputs entirely
- `locals.tf`: stop deriving catalog behavior from mode flags and keep only the temporary compatibility alias for the personal catalog
- `main.tf`: remove the legacy single-catalog module path
- `catalogs_config.tf`: keep governed-catalog derivation as the only catalog source and remove obsolete overlap checks
- `catalog_collision_check.tf`: query the assigned metastore catalogs through native Databricks data sources and fail on name collisions before governed catalog creation
- `sandbox_validations.tf`: enforce sandbox run shape without any `uc_catalog_mode` dependency
- `outputs.tf`: keep `catalogs` authoritative and narrow `catalog_name` to a compatibility alias only
- `scenario*.tfvars` and `template.tfvars.example`: stop setting removed inputs so checked-in examples remain syntactically valid
- `README.md`: document the sandbox-only contract, bootstrap-first workflow, and collision behavior precisely

## Chunk 1: Remove The Legacy Unity Catalog Root Interface

### Task 1: Delete The Old Inputs And Legacy Single-Catalog Path

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/variables.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/locals.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/main.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/outputs.tf`

- [ ] **Step 1: Remove the sandbox tfvars entries for the deleted inputs**

Edit `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars` so this block:

```hcl
uc_catalog_mode          = "isolated"
uc_existing_catalog_name = "sandbox_do_not_use"
metastore_exists         = true
```

becomes:

```hcl
metastore_exists = true
```

- [ ] **Step 2: Remove the obsolete Unity Catalog input variables from the root module**

Delete these variable blocks from `infra/aws/dbx/databricks/us-west-1/variables.tf`:

```hcl
variable "uc_catalog_mode" {
  description = "Unity Catalog mode. Null means mode is inferred from pricing tier and workspace source."
  type        = string
  default     = null
  nullable    = true
}

variable "uc_existing_catalog_name" {
  description = "Existing Unity Catalog name to use when uc_catalog_mode is existing."
  type        = string
  default     = "main"
}
```

Do not leave dead validation text behind.

- [ ] **Step 3: Simplify the root locals to governed-catalog-only behavior**

Replace the old mode-derived locals in `infra/aws/dbx/databricks/us-west-1/locals.tf`:

```hcl
  effective_uc_catalog_mode = var.uc_catalog_mode != null ? var.uc_catalog_mode : (local.enable_enterprise_infra ? "isolated" : "existing")
  catalog_name              = local.effective_uc_catalog_mode == "isolated" ? try(module.unity_catalog_catalog_creation[0].catalog_name, null) : var.uc_existing_catalog_name
```

with a compatibility alias only:

```hcl
  # Temporary compatibility alias for disabled single-catalog consumers.
  catalog_name = try(module.governed_catalogs["personal"].catalog_name, null)
```

- [ ] **Step 4: Remove the legacy root single-catalog module call**

Delete the entire `module "unity_catalog_catalog_creation"` block from `infra/aws/dbx/databricks/us-west-1/main.tf`.

Delete this shape completely:

```hcl
module "unity_catalog_catalog_creation" {
  count  = local.effective_uc_catalog_mode == "isolated" ? 1 : 0
  ...
}
```

The sandbox branch must no longer have a second catalog-creation path in root.

- [ ] **Step 5: Keep the root `catalog_name` output only as a temporary compatibility alias**

Update `infra/aws/dbx/databricks/us-west-1/outputs.tf` so:

```hcl
output "catalog_name" {
  description = "Name of the catalog created for the workspace"
  value       = local.catalog_name
}
```

becomes:

```hcl
output "catalog_name" {
  description = "Compatibility alias for the sandbox personal catalog. Use output.catalogs for the authoritative catalog set."
  value       = local.catalog_name
}
```

Do not change the shape of `output "catalogs"` in this task.

- [ ] **Step 6: Format and inspect the root-interface diff**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
git diff -- infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars \
  infra/aws/dbx/databricks/us-west-1/variables.tf \
  infra/aws/dbx/databricks/us-west-1/locals.tf \
  infra/aws/dbx/databricks/us-west-1/main.tf \
  infra/aws/dbx/databricks/us-west-1/outputs.tf
```

Expected:

- no remaining references to `uc_catalog_mode`
- no remaining references to `uc_existing_catalog_name`
- the only remaining singular catalog concept is the `catalog_name` compatibility alias

### Task 2: Keep Checked-In Examples Valid For The Sandbox-Only Branch

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/scenario3.enterprise-create-isolated.tfvars`
- Modify: `infra/aws/dbx/databricks/us-west-1/template.tfvars.example`

- [ ] **Step 1: Remove deleted inputs from every checked-in tfvars/example file**

Delete `uc_catalog_mode` and `uc_existing_catalog_name` assignments from:

- `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- `infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars`
- `infra/aws/dbx/databricks/us-west-1/scenario3.enterprise-create-isolated.tfvars`
- `infra/aws/dbx/databricks/us-west-1/template.tfvars.example`

For the template example, remove both active assignments and commented examples such as:

```hcl
uc_catalog_mode          = "existing"
uc_existing_catalog_name = "main"
# uc_catalog_mode         = null
# uc_catalog_mode         = "isolated"
```

- [ ] **Step 2: Add an explicit sandbox-branch warning to the non-sandbox scenario files if they remain in-tree**

At the top of these files:

- `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`
- `infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars`
- `infra/aws/dbx/databricks/us-west-1/scenario3.enterprise-create-isolated.tfvars`

add a short comment such as:

```hcl
# Historical scenario reference only. The sandbox branch is validated only with scenario2.sandbox-create-managed.tfvars.
```

Do not add new variables. This is only to prevent operator confusion after the root interface changes.

- [ ] **Step 3: Diff-check the example cleanup**

Run:

```bash
rg -n "uc_catalog_mode|uc_existing_catalog_name" infra/aws/dbx/databricks/us-west-1/scenario*.tfvars infra/aws/dbx/databricks/us-west-1/template.tfvars.example
git diff -- infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars \
  infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars \
  infra/aws/dbx/databricks/us-west-1/scenario3.enterprise-create-isolated.tfvars \
  infra/aws/dbx/databricks/us-west-1/template.tfvars.example
```

Expected:

- `rg` prints nothing
- the only changes are deleted UC-mode assignments and the optional historical-warning comments

## Chunk 2: Add The Native Metastore Collision Guard

### Task 3: Replace Obsolete Overlap Checks With A Root-Level Catalog Guard

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/catalog_collision_check.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`

- [ ] **Step 1: Remove the old overlap checks from `catalogs_config.tf`**

Delete these check blocks from `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`:

```hcl
check "governed_catalog_existing_catalog_overlap" { ... }
check "governed_catalog_legacy_isolated_overlap" { ... }
```

They are artifacts of the deleted legacy mode-switching model.

- [ ] **Step 2: Create native Databricks data reads for the assigned workspace metastore**

Create `infra/aws/dbx/databricks/us-west-1/catalog_collision_check.tf` with this structure:

```hcl
data "databricks_current_metastore" "workspace" {
  provider = databricks.created_workspace

  provider_config {
    workspace_id = local.workspace_id
  }

  depends_on = [module.unity_catalog_metastore_assignment]
}

data "databricks_catalogs" "workspace" {
  provider = databricks.created_workspace

  provider_config {
    workspace_id = local.workspace_id
  }

  depends_on = [module.unity_catalog_metastore_assignment]
}

locals {
  metastore_catalog_names  = toset(data.databricks_catalogs.workspace.ids)
  configured_catalog_names = toset([for catalog in values(local.catalogs) : catalog.catalog_name])
  colliding_catalog_names  = sort(tolist(setintersection(local.metastore_catalog_names, local.configured_catalog_names)))
}
```

Notes:

- keep this logic in its own root file rather than burying it in `catalogs_config.tf`
- do not push collision logic down into `modules/databricks_workspace/unity_catalog_catalog_creation`
- the supported sandbox workflow is now staged, so these reads are expected to resolve during plan after the bootstrap apply has populated `local.workspace_id` in state

- [ ] **Step 3: Add the root check that fails on collisions**

In the same new file, add:

```hcl
check "sandbox_catalog_name_collisions" {
  assert {
    condition     = length(local.colliding_catalog_names) == 0
    error_message = "Configured sandbox catalogs already exist in metastore ${data.databricks_current_metastore.workspace.metastore_info[0].metastore_id}: ${join(", ", local.colliding_catalog_names)}. The sandbox branch creates new catalogs only; rename or remove the existing catalogs before re-running."
  }
}
```

Keep the message concrete. It must tell the operator that existing catalogs are not adopted into Terraform state in this branch.

- [ ] **Step 4: Make governed catalog creation wait on the collision guard inputs**

Extend the existing `depends_on` in the `module "governed_catalogs"` block in `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf` so it includes the new data reads:

```hcl
  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    data.databricks_current_metastore.workspace,
    data.databricks_catalogs.workspace,
  ]
```

This ensures the full rollout sequence is:

1. bootstrap apply creates workspace and metastore assignment
2. full rollout plan reads current metastore plus catalog names
3. plan fails on collision or proceeds to governed catalog creation

- [ ] **Step 5: Format and run root validation**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected:

- `validate` passes
- `plan` no longer references removed UC-mode inputs
- after bootstrap, `plan` resolves the new catalog-read data sources without deferring them for unknown `workspace_id`
- no syntax or provider-schema errors mention `provider_config` blocks for the new Databricks data sources

## Chunk 3: Align Sandbox Validation And Operator Docs

### Task 4: Update Sandbox Assertions And README Guidance

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

- [ ] **Step 1: Remove `uc_catalog_mode` from the sandbox run-shape check**

Update `infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf` so this assertion:

```hcl
      var.metastore_exists &&
      local.effective_uc_catalog_mode == "isolated" &&
      var.existing_workspace_host == null &&
```

becomes:

```hcl
      var.metastore_exists &&
      var.existing_workspace_host == null &&
```

Update the error message too. It should no longer mention `uc_catalog_mode=isolated`.

- [ ] **Step 2: Rewrite the README to describe only the sandbox Unity Catalog contract**

In `infra/aws/dbx/databricks/us-west-1/README.md`, update the sandbox workflow section so it says:

- the sandbox branch never adopts existing Unity Catalog catalogs
- the sandbox branch only creates new sandbox-prefixed catalogs declared in `catalogs_config.tf`
- the workflow is staged: bootstrap workspace first, then run the full sandbox plan/apply
- catalog-collision failures are checked against the assigned metastore during the post-bootstrap plan

Also remove or rewrite README bullets that still mention:

- `uc_catalog_mode = "existing"`
- `uc_catalog_mode = "isolated"`
- choosing a Unity Catalog mode in this branch

- [ ] **Step 3: Sweep the root tree for deleted-interface references**

Run:

```bash
rg -n "uc_catalog_mode|uc_existing_catalog_name|effective_uc_catalog_mode" \
  infra/aws/dbx/databricks/us-west-1/*.tf \
  infra/aws/dbx/databricks/us-west-1/*.tfvars \
  infra/aws/dbx/databricks/us-west-1/*.example \
  infra/aws/dbx/databricks/us-west-1/README.md
```

Expected:

- no matches in active root Terraform, checked-in tfvars, examples, or the README

- [ ] **Step 4: Run final verification for the supported sandbox workflow**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply -target=module.databricks_mws_workspace -target=module.unity_catalog_metastore_assignment -target=module.user_assignment -var-file=scenario2.sandbox-create-managed.tfvars
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
git diff --stat
```

Expected:

- formatting is clean
- validation passes
- the bootstrap apply populates the workspace and metastore assignment in state without attempting governed catalog creation
- the sandbox plan contains no references to removed UC-mode inputs
- the post-bootstrap plan evaluates the collision check during plan
- `git diff --stat` shows only the planned root/config/doc files for this change

- [ ] **Step 5: Perform the manual collision-path verification**

Use a temporary local edit in `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf` that points one sandbox catalog at a catalog name already present in the assigned metastore, after the bootstrap apply has already created the workspace.

Verification rule:

- expect the collision to fail during `plan`

Expected error text should include:

- the colliding catalog names
- the metastore identifier
- a clear statement that the sandbox branch creates new catalogs only

## Chunk 4: Document And Verify The Bootstrap Workflow

### Task 5: Lock The Workflow To Bootstrap Then Full Rollout

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

- [ ] **Step 1: Add the exact staged command sequence to the sandbox README**

Document these commands in the sandbox workflow section:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply \
  -target=module.databricks_mws_workspace \
  -target=module.unity_catalog_metastore_assignment \
  -target=module.user_assignment \
  -var-file=scenario2.sandbox-create-managed.tfvars

DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan \
  -var-file=scenario2.sandbox-create-managed.tfvars
```

Make the README explain why the workflow is staged:

- the workspace ID must come from Terraform state
- the collision check must run during plan
- hardcoding `workspace_id` is intentionally unsupported

- [ ] **Step 2: Verify the README no longer describes a single-pass sandbox rollout**

Run:

```bash
rg -n "first create-workspace run|fail during apply|hardcode the workspace_id|Unity Catalog mode" infra/aws/dbx/databricks/us-west-1/README.md
git diff -- infra/aws/dbx/databricks/us-west-1/README.md
```

Expected:

- no stale guidance remains about first-run collision failure during apply
- the README reflects the exact bootstrap-then-full-rollout workflow

Plan complete and saved to `docs/superpowers/plans/2026-03-19-sandbox-unity-catalog-root-simplification.md`. Ready to execute?
