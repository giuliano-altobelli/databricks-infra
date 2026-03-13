# Governed Catalog Creation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a config-driven Terraform path that creates multiple workspace-isolated Unity Catalog catalogs with per-catalog AWS bootstrap, while preserving the existing isolated legacy path and its state behavior.

**Architecture:** Keep `modules/databricks_workspace/unity_catalog_catalog_creation` as the single-catalog AWS-plus-Databricks unit, but refactor it to accept generic catalog inputs and workspace bindings. Add a new root `catalogs_config.tf` caller that derives governed `prod_*` catalogs plus implicit `personal` when the governed domain map is non-empty, and keep the legacy isolated caller in `main.tf` wired to the refactored interface without changing its existing names or admin behavior.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider `~> 1.84`, AWS provider `>= 5.76, <7.0`, workspace-scoped Databricks alias `databricks.created_workspace`, `direnv` with `DATABRICKS_AUTH_TYPE=oauth-m2m`

---

**Spec:** `docs/superpowers/specs/2026-03-12-governed-catalog-creation-design.md`

## File Structure

Modify these design and operator docs:

- `ARCHITECTURE.md`
- `docs/design-docs/unity-catalog.md`
- `infra/aws/dbx/databricks/us-west-1/README.md`

Modify or create these root Terraform files:

- `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- `infra/aws/dbx/databricks/us-west-1/main.tf`
- `infra/aws/dbx/databricks/us-west-1/outputs.tf`

Modify or create these module files:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/outputs.tf`

Responsibilities:

- `ARCHITECTURE.md` and `docs/design-docs/unity-catalog.md`: align the repo-wide naming rule so empty `business_area` means `prod_<source>` for this rollout instead of forcing a sentinel
- root `README.md`: make `catalogs_config.tf` the preferred operator entrypoint for governed catalogs and document coexistence with the legacy isolated path
- module `SPEC.md`: convert the approved design into the local module contract used during implementation verification
- module `README.md`: document generic single-catalog usage, root wiring, legacy caller notes, and output semantics
- module `variables.tf`: define the new generic interface (`catalog_name`, `catalog_admin_principal`, `workspace_ids`, `set_default_namespace`) and validations
- module `main.tf`: preserve the one-pass AWS/bootstrap flow, add explicit workspace bindings, make default namespace optional, and keep legacy names/state stable when the old caller maps into the new interface
- module `outputs.tf`: expose the deterministic scalar outputs required by the spec
- `catalogs_config.tf`: define governed-domain locals, derived catalog locals, root-level `check` blocks, module `for_each`, and baseline dependencies
- root `main.tf`: adapt the legacy isolated caller to the refactored module interface without changing its names or admin-principal behavior
- root `outputs.tf`: preserve the existing singular `catalog_name` output and add the new `catalogs` map output

## Chunk 1: Contracts And Docs

### Task 1: Write The Local Module Contract

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/README.md`

- [ ] **Step 1: Write the module `SPEC.md` from the approved design**

Create `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md` with the repo-standard sections:

```md
# Module Spec

## Summary
## Scope
## Current Stack Usage
## Interfaces
## Provider Context
## Behavior / Data Flow
## Constraints and Failure Modes
## Validation
```

The spec must state these exact boundaries:

```md
- single-catalog module only
- owns AWS bootstrap plus Databricks storage credential, external location, catalog, bindings, and admin grant
- workspace-level Databricks provider only
- optional extra isolated `workspace_ids`
- no open/shared mode in this change
- legacy isolated caller must preserve names and state shape
```

Do not stop at the boundary bullets. The module `SPEC.md` must also explicitly encode these approved design sections:

- required inputs and optional inputs
- deterministic scalar outputs and `enabled = false` output behavior
- one-pass bootstrap sequence
- authoritative catalog grant behavior
- explicit isolated workspace-binding behavior
- module validation rules and failure modes

- [ ] **Step 2: Update the module README to match the new generic interface**

Rewrite `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/README.md` so it no longer describes only the legacy isolated naming surface. Include:

- a generic example using `catalog_name = "prod_salesforce_revenue"`
- explicit workspace-scoped provider wiring using `databricks.created_workspace`
- a note that AWS names derive from `replace(catalog_name, "_", "-")`
- the `set_default_namespace = false` default
- the explicit isolated `workspace_ids` behavior
- the scalar outputs consumed by root `catalogs`
- the `enabled = false` behavior where module scalar outputs resolve to `null`
- a short note that the legacy isolated caller is still supported by mapping its old naming formula into the new interface

- [ ] **Step 3: Validate the module docs before code refactor**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation validate
```

Expected: init succeeds and validate still passes before functional edits begin.

- [ ] **Step 4: Commit the module contract**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/README.md
git commit -m "docs: define governed catalog module contract"
```

Expected: one commit containing only the module contract and README alignment.

### Task 2: Align Repo-Level Docs With The Approved Naming Rule

**Files:**
- Modify: `ARCHITECTURE.md`
- Modify: `docs/design-docs/unity-catalog.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

- [ ] **Step 1: Update the repo architecture naming rule**

Edit `ARCHITECTURE.md` so the governed namespace contract reads:

```md
- Governed domain catalogs:
  - `prod_<source>_<business_area>` when `business_area` is present
  - `prod_<source>` when `business_area` is empty
```

Do not introduce schema work in this edit.

- [ ] **Step 2: Sync the detailed Unity Catalog design doc**

Update `docs/design-docs/unity-catalog.md` so every place that currently assumes `prod_<source>_<business_area>` or a sentinel for missing business area is brought into line with:

```md
- empty `business_area` renders `prod_<source>`
```

Keep the rest of the future schema and access-model design intact.

- [ ] **Step 3: Add operator docs for the new root entrypoint**

Update `infra/aws/dbx/databricks/us-west-1/README.md` with a short governed-catalog section that explains:

- `catalogs_config.tf` is the preferred entrypoint for new governed catalog work
- the file defaults off via `local.governed_catalog_domains = {}`
- `personal` appears only when the governed map is non-empty
- the existing isolated path still exists for backward compatibility
- the legacy isolated path is planned for future archival

- [ ] **Step 4: Commit the doc alignment**

Before committing, run:

```bash
rg -n "unassigned|prod_<source>_<business_area>" ARCHITECTURE.md docs/design-docs/unity-catalog.md infra/aws/dbx/databricks/us-west-1/README.md
git diff -- ARCHITECTURE.md docs/design-docs/unity-catalog.md infra/aws/dbx/databricks/us-west-1/README.md
```

Expected:

- no remaining sentinel-based guidance for missing `business_area`
- only the intended naming-rule and operator-entrypoint edits appear in the diff

Then commit:

Run:

```bash
git add ARCHITECTURE.md
git add docs/design-docs/unity-catalog.md
git add infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs: align governed catalog naming rules"
```

Expected: one doc-only commit that resolves the naming conflict before Terraform behavior changes.

## Chunk 2: Module Refactor And Legacy Compatibility

### Task 3: Refactor The Module Interface Without Breaking The Legacy Path

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/variables.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/outputs.tf`

- [ ] **Step 1: Replace the legacy input names with the generic interface**

Update `variables.tf` so the public inputs include:

```hcl
variable "enabled" {
  type    = bool
  default = true
}

variable "catalog_name" {
  type = string
}

variable "catalog_admin_principal" {
  type = string
}

variable "workspace_ids" {
  type    = list(string)
  default = []
}

variable "set_default_namespace" {
  type    = bool
  default = false
}

```

Keep the existing AWS/account inputs, but remove `uc_catalog_name` and `user_workspace_catalog_admin`.

- [ ] **Step 2: Add validation for the new public interface**

Add validation blocks that reject:

- blank `catalog_name`
- blank `catalog_admin_principal`
- blank or non-numeric `workspace_id`
- blank or non-numeric entries in `workspace_ids`

Use the same style as `unity_catalog_storage_locations/variables.tf`.

- [ ] **Step 3: Expand scalar outputs to the spec surface**

Replace `outputs.tf` with deterministic scalar outputs for:

```hcl
output "catalog_name" {}
output "catalog_bucket_name" {}
output "storage_credential_name" {}
output "storage_credential_external_id" {}
output "storage_credential_unity_catalog_iam_arn" {}
output "external_location_name" {}
output "iam_role_arn" {}
output "kms_key_arn" {}
```

When `enabled = false`, each output should evaluate to `null`.

- [ ] **Step 4: Do not validate or commit this task in isolation**

`variables.tf` and `outputs.tf` become valid only after `main.tf` is updated in Task 4. Keep this task uncommitted and move the first module validation/commit boundary to the end of Task 4.

### Task 4: Rewrite The Module Resource Logic

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/main.tf`

- [ ] **Step 1: Introduce naming locals that preserve the legacy path**

Start `main.tf` with locals like:

```hcl
locals {
  enabled_catalog = var.enabled
  aws_safe_catalog_suffix = replace(var.catalog_name, "_", "-")
  catalog_workspace_ids   = distinct(concat([var.workspace_id], var.workspace_ids))
  legacy_name_compat      = var.catalog_name == replace("${var.resource_prefix}-catalog-${var.workspace_id}", "-", "_")
  resource_name_base      = local.legacy_name_compat ? local.aws_safe_catalog_suffix : "${var.resource_prefix}-${local.aws_safe_catalog_suffix}-${var.workspace_id}"
  uc_iam_role             = local.resource_name_base
}
```

Important:

- the legacy caller in root `main.tf` must pass `catalog_name = replace("${var.resource_prefix}-catalog-${local.workspace_id}", "-", "_")`
- with that input, `local.legacy_name_compat` becomes true and `local.resource_name_base` becomes `${var.resource_prefix}-catalog-${local.workspace_id}`, which preserves the current legacy bucket, IAM role, policy, storage credential, and external location names

- [ ] **Step 2: Preserve the existing one-pass bootstrap sequence**

Keep the existing sequencing pattern:

- Databricks storage credential first
- Databricks-generated trust values feed the AWS assume-role policy
- IAM role/policy attachment
- bucket encryption and public-access settings
- external location after IAM readiness plus the existing wait guard

Do not introduce a caller-facing staged apply or `skip_validation` toggle.

- [ ] **Step 3: Keep the existing stateful resource addresses while making them generic**

Do not rename the existing stateful resource blocks. Preserve addresses like:

- `databricks_catalog.workspace_catalog`
- `databricks_storage_credential.workspace_catalog_storage_credential`
- `databricks_external_location.workspace_catalog_external_location`
- `databricks_grant.workspace_catalog` if that resource must remain for legacy compatibility

Only change their arguments and conditional creation logic so they read from `var.catalog_name`, `var.catalog_admin_principal`, and `var.enabled`.

Important: the plan must preserve legacy Terraform addresses and avoid state moves for the isolated path.

Also make every AWS and Databricks resource in the module conditional on `var.enabled`; `enabled = false` must create no resources at all.

- [ ] **Step 4: Add explicit workspace bindings and preserve legacy grant state**

Implement:

- `databricks_workspace_binding` for the storage credential
- `databricks_workspace_binding` for the external location
- `databricks_workspace_binding` for the catalog

Use one binding per `distinct(concat([var.workspace_id], var.workspace_ids))` entry and add duplicate binding preconditions.

For the catalog admin grant:

- preserve the existing legacy admin-grant state shape on the isolated path
- use `local.legacy_name_compat` as the discriminator between legacy isolated behavior and the governed path
- if switching the legacy path from `databricks_grant` to `databricks_grants` would require state moves or forced replacement, keep the legacy grant resource for the `local.legacy_name_compat` path and scope `databricks_grants` only to the governed path
- do not plan state moves or forced grant replacement for the legacy isolated path

- [ ] **Step 5: Make default namespace management opt-in**

Wrap `databricks_default_namespace_setting` in `count = var.enabled && var.set_default_namespace ? 1 : 0`.

The new governed path always passes `false`. The legacy isolated caller must pass `true` so its current behavior remains explicit and deterministic.

- [ ] **Step 6: Add early-fail name and collision protections**

Use lifecycle preconditions or root-driven checks so the module fails clearly when:

- computed S3 bucket names violate S3 naming rules
- generated identifiers exceed provider-specific limits
- duplicate workspace binding tuples are materialized

Do not hash or truncate names silently.

- [ ] **Step 7: Validate the fully refactored module**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation validate
```

Expected: validate succeeds only after `variables.tf`, `outputs.tf`, and `main.tf` are all updated together.

- [ ] **Step 8: Commit the full module refactor**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/variables.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/outputs.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/main.tf
git commit -m "feat: generalize governed catalog creation module"
```

Expected: one commit containing the complete module interface and behavior change together.

### Task 5: Rewire The Legacy Root Caller Without Forcing Replacement

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/main.tf`

- [ ] **Step 1: Update the legacy isolated module call to the refactored interface**

Change the existing block at `infra/aws/dbx/databricks/us-west-1/main.tf` so it passes:

```hcl
catalog_name            = replace("${var.resource_prefix}-catalog-${local.workspace_id}", "-", "_")
catalog_admin_principal = var.admin_user
workspace_ids           = []
set_default_namespace   = true
```

Use the existing AWS/account inputs unchanged.

- [ ] **Step 2: Preserve state and names explicitly**

Before committing, compare the derived values against the current module behavior and confirm these stay unchanged for the legacy path:

- catalog name
- bucket name
- storage credential name
- external location name
- IAM role/policy names

If any derived name changes, stop and fix the module inputs or locals instead of accepting replacement.

- [ ] **Step 3: Prove the legacy isolated path still plans without forced replacement**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars -var='uc_catalog_mode=isolated'
```

Expected:

- validate succeeds
- the legacy isolated caller still uses the same derived names as before
- the plan does not show forced replacement or state-move requirements caused only by the interface refactor

- [ ] **Step 4: Commit the legacy caller adaptation**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/main.tf
git commit -m "refactor: adapt legacy isolated catalog caller"
```

Expected: one commit that changes only the root legacy call surface.

## Chunk 3: New Root Caller, Outputs, And Verification

### Task 6: Add The Governed Catalog Root Entry Point

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/outputs.tf`

- [ ] **Step 1: Define the governed-domain and derived catalog locals**

Create `catalogs_config.tf` with locals shaped like:

```hcl
locals {
  governed_catalog_domains = {}

  governed_catalogs_enabled = length(local.governed_catalog_domains) > 0

  derived_governed_catalogs = local.governed_catalogs_enabled ? {
    for catalog_key, domain in local.governed_catalog_domains :
    catalog_key => {
      catalog_kind            = "governed"
      catalog_name            = trimspace(domain.business_area) == "" ? "prod_${domain.source}" : "prod_${domain.source}_${domain.business_area}"
      aws_safe_catalog_suffix = replace(trimspace(domain.business_area) == "" ? "prod_${domain.source}" : "prod_${domain.source}_${domain.business_area}", "_", "-")
      workspace_ids           = try(domain.workspace_ids, [])
    }
  } : {}

  catalogs = local.governed_catalogs_enabled ? merge(
    local.derived_governed_catalogs,
    {
      personal = {
        catalog_kind            = "personal"
        catalog_name            = "personal"
        aws_safe_catalog_suffix = "personal"
        workspace_ids           = []
      }
    }
  ) : {}
}
```

Keep the checked-in default empty and the future-sharing example commented out.

- [ ] **Step 2: Add root-level `check` blocks for the approved collision rules**

Implement explicit `check` blocks in `catalogs_config.tf` for:

- reserved caller key `personal`
- duplicate derived catalog names
- duplicate AWS-safe suffixes
- overlap with `var.uc_existing_catalog_name`
- overlap with the legacy isolated-catalog name in existing-workspace flows

For create-workspace flows, document in the `check` or adjacent comment that the legacy overlap guard may remain apply-time because `workspace_id` is unknown until the workspace exists.

- [ ] **Step 3: Add the governed `for_each` module call**

Create:

```hcl
module "governed_catalogs" {
  for_each = local.catalogs
  source   = "./modules/databricks_workspace/unity_catalog_catalog_creation"

  providers = {
    databricks = databricks.created_workspace
  }

  aws_account_id               = var.aws_account_id
  aws_iam_partition            = local.computed_aws_partition
  aws_assume_partition         = local.assume_role_partition
  unity_catalog_iam_arn        = local.unity_catalog_iam_arn
  cmk_admin_arn                = var.cmk_admin_arn == null ? "arn:${local.computed_aws_partition}:iam::${var.aws_account_id}:root" : var.cmk_admin_arn
  resource_prefix              = var.resource_prefix
  workspace_id                 = local.workspace_id
  catalog_name                 = each.value.catalog_name
  catalog_admin_principal      = local.identity_groups.platform_admins.display_name
  workspace_ids                = each.value.workspace_ids
  set_default_namespace        = false

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
  ]
}
```

- [ ] **Step 4: Add the root `catalogs` output and preserve the legacy singular output**

Update `outputs.tf` so:

- existing `catalog_name` stays unchanged
- new `catalogs` output returns `{}` when `local.catalogs` is empty
- each value includes:

```hcl
{
  catalog_kind                      = local.catalogs[catalog_key].catalog_kind
  catalog_name                      = module.governed_catalogs[catalog_key].catalog_name
  catalog_bucket_name               = module.governed_catalogs[catalog_key].catalog_bucket_name
  storage_credential_name           = module.governed_catalogs[catalog_key].storage_credential_name
  storage_credential_external_id    = module.governed_catalogs[catalog_key].storage_credential_external_id
  storage_credential_unity_catalog_iam_arn = module.governed_catalogs[catalog_key].storage_credential_unity_catalog_iam_arn
  external_location_name            = module.governed_catalogs[catalog_key].external_location_name
  iam_role_arn                      = module.governed_catalogs[catalog_key].iam_role_arn
  kms_key_arn                       = module.governed_catalogs[catalog_key].kms_key_arn
}
```

- [ ] **Step 5: Commit the new root caller and outputs**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/catalogs_config.tf
git add infra/aws/dbx/databricks/us-west-1/outputs.tf
git commit -m "feat: add governed catalog root configuration"
```

Expected: one commit containing only the new governed root path and outputs.

### Task 7: Format, Verify, And Capture Both Enabled And Disabled Paths

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf` temporarily during verification only if needed

- [ ] **Step 1: Format the full Terraform tree**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
```

Expected: all touched Terraform files are formatted with no remaining diff from `terraform fmt`.

- [ ] **Step 2: Verify the disabled/new-path baseline**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- validate succeeds
- the empty `local.governed_catalog_domains` path is a no-op
- the legacy existing-catalog flow still plans cleanly

- [ ] **Step 3: Exercise the governed path in an existing-workspace scenario**

Temporarily edit `catalogs_config.tf` to use a minimal non-empty example such as:

```hcl
governed_catalog_domains = {
  salesforce_revenue = {
    source        = "salesforce"
    business_area = "revenue"
  }
}
```

Then run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: plan shows new governed resources for `salesforce_revenue` and implicit `personal`, with no collision against `uc_existing_catalog_name = "workspace"`.

- [ ] **Step 4: Exercise the create-workspace path and unknown `workspace_id` behavior**

With the same temporary non-empty governed-domain example still in place, run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.premium-create-managed.tfvars
```

Expected:

- plan succeeds in the premium create-workspace path
- any legacy isolated overlap rule that depends on `workspace_id` is deferred safely until apply-time
- no enterprise-only resources are required

- [ ] **Step 5: Restore the checked-in empty governed-domain map**

Revert `catalogs_config.tf` to:

```hcl
governed_catalog_domains = {}
```

and confirm `git diff` shows only the intentional implementation changes, not the temporary verification example.

- [ ] **Step 6: Commit the finalized implementation**

Run:

```bash
git add ARCHITECTURE.md
git add docs/design-docs/unity-catalog.md
git add infra/aws/dbx/databricks/us-west-1/README.md
git add infra/aws/dbx/databricks/us-west-1/catalogs_config.tf
git add infra/aws/dbx/databricks/us-west-1/main.tf
git add infra/aws/dbx/databricks/us-west-1/outputs.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/README.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/variables.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/main.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/outputs.tf
git commit -m "feat: add governed catalog creation flow"
```

Expected: one final commit containing the working governed-catalog path, the preserved legacy isolated path, and synchronized docs.
