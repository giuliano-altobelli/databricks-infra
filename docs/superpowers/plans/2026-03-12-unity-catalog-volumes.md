# Unity Catalog Volumes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a workspace-scoped Terraform module for Databricks Unity Catalog volumes that supports `MANAGED` and `EXTERNAL` volume types from one `volumes` input map, with authoritative volume grants and root-module integration.

**Architecture:** Add a focused module at `modules/databricks_workspace/unity_catalog_volumes` that creates `databricks_volume` and optional authoritative `databricks_grants` resources only. Keep catalogs, schemas, storage credentials, external locations, and workspace bindings outside this module; root callers must pass names and external URIs from upstream resources or modules and add explicit `depends_on` when Terraform cannot infer prerequisite ordering.

**Tech Stack:** Terraform `~> 1.3`, Databricks Terraform provider `~> 1.84`, workspace-scoped provider alias `databricks.created_workspace`, `direnv` with `DATABRICKS_AUTH_TYPE=oauth-m2m`

---

**Spec:** `docs/superpowers/specs/2026-03-12-unity-catalog-volumes-design.md`

## File Structure

Create these module files:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/versions.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/outputs.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/FACTS.md` only if documentation lookups are needed during implementation

Modify or create these root files:

- `infra/aws/dbx/databricks/us-west-1/volume_config.tf`
- `infra/aws/dbx/databricks/us-west-1/README.md`

Responsibilities:

- `SPEC.md`: implementation contract derived from the approved design doc
- `README.md`: usage example, ordering contract, external-volume expectations, destroy guidance
- `variables.tf`: public module interface and validation
- `main.tf`: locals, duplicate detection, `databricks_volume`, `databricks_grants`, lifecycle preconditions
- `outputs.tf`: caller-facing volume output map
- `volume_config.tf`: root locals, example configuration, module invocation, provider wiring, dependency guidance

## Chunk 1: Module Contract And Scaffolding

### Task 1: Scaffold The Module Directory

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/*`

- [ ] **Step 1: Scaffold the new module from the repo template**

Run:

```bash
scripts/new_module.sh databricks_workspace/unity_catalog_volumes
```

Expected: the new module directory exists with the template file set.

- [ ] **Step 2: Replace the template `SPEC.md` with the approved contract**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/SPEC.md` from `docs/superpowers/specs/2026-03-12-unity-catalog-volumes-design.md`.

The file must use the same section structure as the repo module template:

```md
# Module Spec

## Summary
## Scope
## Interfaces
## Provider Context
## Constraints
## Validation
```

Populate those sections with the approved contract, including these exact implementation constraints:

```md
- Provider scope: workspace-level only
- `volume_type` must be `MANAGED` or `EXTERNAL`
- `EXTERNAL` volumes require `storage_location`
- `MANAGED` volumes forbid `storage_location`
- grants are authoritative when declared
- duplicate grant tuples and duplicate fully qualified volume identities must fail clearly
```

In `## Interfaces`, explicitly list:

- `enabled`
- `volumes`
- the `volumes` output map with `storage_location = null` for `MANAGED` volumes

- [ ] **Step 3: Align `versions.tf` with workspace-module conventions**

Ensure `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/versions.tf` matches the other workspace modules:

```hcl
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.84"
    }
  }

  required_version = "~> 1.3"
}
```

- [ ] **Step 4: Write the module README before implementation**

Seed `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/README.md` with:

- a minimal example showing one `MANAGED` volume and one `EXTERNAL` volume
- the root ordering contract for same-stack catalog/schema or external-location creation
- the same-stack external-location grant and authorization-readiness contract
- the destroy-safety contract that the provider does not expose force-delete behavior for volumes
- the statement that `storage_location` output is `null` for `MANAGED` volumes
- guidance to prefer upstream outputs for same-stack catalog/schema names when available

Use an example like:

```hcl
module "unity_catalog_volumes" {
  source = "./modules/databricks_workspace/unity_catalog_volumes"

  providers = {
    databricks = databricks.created_workspace
  }

  volumes = {
    model_artifacts = {
      name         = "model_artifacts"
      catalog_name = "prod_ml_platform"
      schema_name  = "final"
      volume_type  = "MANAGED"
    }
    inbound_files = {
      name             = "inbound_files"
      catalog_name     = "prod_salesforce_revenue"
      schema_name      = "raw"
      volume_type      = "EXTERNAL"
      storage_location = "${module.unity_catalog_storage_locations.external_locations.revenue_raw.url}/volumes/inbound_files"
    }
  }
}
```

- [ ] **Step 5: Validate the scaffold before the first commit**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate
```

Expected: the scaffolded module parses and validates before deeper implementation starts.

- [ ] **Step 6: Commit the scaffold and docs**

Run:

```bash
rm -f infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/FACTS.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/SPEC.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/README.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/versions.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/variables.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/outputs.tf
git commit -m "docs: scaffold unity catalog volumes module"
```

Expected: one commit containing only the finalized scaffold files. Keep `FACTS.md` out unless documentation lookups later make it necessary.

## Chunk 2: Module Interface, Validation, And Resources

### Task 2: Implement The Public Variable Contract

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/variables.tf`

- [ ] **Step 1: Define `enabled` and the `volumes` map input**

Start from this shape:

```hcl
variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "volumes" {
  description = "Unity Catalog volumes keyed by stable caller-defined identifiers."
  type = map(object({
    name             = string
    catalog_name     = string
    schema_name      = string
    volume_type      = string
    comment          = optional(string)
    owner            = optional(string)
    storage_location = optional(string)
    grants = optional(list(object({
      principal  = string
      privileges = list(string)
    })), [])
  }))
}
```

- [ ] **Step 2: Add non-empty field validation**

Add one validation block that rejects blank `name`, `catalog_name`, and `schema_name` values:

```hcl
validation {
  condition = !var.enabled || alltrue([
    for volume in values(var.volumes) :
    trimspace(volume.name) != "" &&
    trimspace(volume.catalog_name) != "" &&
    trimspace(volume.schema_name) != ""
  ])
  error_message = "Each volume must declare non-empty name, catalog_name, and schema_name values."
}
```

- [ ] **Step 3: Add `volume_type` and `storage_location` validation**

Add separate validation blocks for:

- allowed `volume_type` values
- required `storage_location` for `EXTERNAL`
- forbidden `storage_location` for `MANAGED`

Use near-final expressions like:

```hcl
validation {
  condition = !var.enabled || alltrue([
    for volume in values(var.volumes) :
    contains(["MANAGED", "EXTERNAL"], volume.volume_type)
  ])
  error_message = "Each volume volume_type must be MANAGED or EXTERNAL."
}

validation {
  condition = !var.enabled || alltrue([
    for volume in values(var.volumes) :
    volume.volume_type != "EXTERNAL" || trimspace(coalesce(try(volume.storage_location, null), "")) != ""
  ])
  error_message = "EXTERNAL volumes must declare a non-empty storage_location."
}

validation {
  condition = !var.enabled || alltrue([
    for volume in values(var.volumes) :
    volume.volume_type != "MANAGED" || trimspace(coalesce(try(volume.storage_location, null), "")) == ""
  ])
  error_message = "MANAGED volumes must not declare storage_location."
}
```

- [ ] **Step 4: Add grant principal and privilege validation**

Add separate validation blocks for:

- non-empty `principal`
- non-empty privilege lists
- allowed privileges only

Use near-final expressions like:

```hcl
validation {
  condition = !var.enabled || alltrue(flatten([
    for volume in values(var.volumes) : [
      for grant in volume.grants : trimspace(grant.principal) != ""
    ]
  ]))
  error_message = "Each volume grant principal must be non-empty."
}

validation {
  condition = !var.enabled || alltrue(flatten([
    for volume in values(var.volumes) : [
      for grant in volume.grants : length(grant.privileges) > 0
    ]
  ]))
  error_message = "Each volume grant must declare at least one privilege."
}

validation {
  condition = !var.enabled || alltrue(flatten([
    for volume in values(var.volumes) : [
      for grant in volume.grants : [
        for privilege in grant.privileges :
        contains(["ALL_PRIVILEGES", "APPLY_TAG", "MANAGE", "READ_VOLUME", "WRITE_VOLUME"], privilege)
      ]
    ]
  ]))
  error_message = "Volume grant privileges must be one of: ALL_PRIVILEGES, APPLY_TAG, MANAGE, READ_VOLUME, WRITE_VOLUME."
}
```

- [ ] **Step 5: Initialize the module and verify syntax before resource work**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate
```

Expected: init succeeds and validate reports the configuration is valid.

- [ ] **Step 6: Commit the interface**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/variables.tf
git commit -m "feat: define unity catalog volumes module inputs"
```

Expected: one commit containing the stable input contract and validations.

### Task 3: Add Normalization Locals And Duplicate Detection

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf`

- [ ] **Step 1: Replace the placeholder `main.tf` with one complete `locals {}` block**

Use one valid Terraform `locals` block, not free-standing `local.*` assignments:

```hcl
locals {
  enabled_volumes = var.enabled ? var.volumes : {}

  volume_identity_keys = [
    for volume_key, volume in local.enabled_volumes :
    format(
      "%s.%s.%s",
      lower(trimspace(volume.catalog_name)),
      lower(trimspace(volume.schema_name)),
      lower(trimspace(volume.name))
    )
  ]

  duplicate_volume_identity_keys = toset([
    for key in local.volume_identity_keys : key
    if length([
      for seen in local.volume_identity_keys : seen if seen == key
    ]) > 1
  ])

  volume_grant_tuples = flatten([
    for volume_key, volume in local.enabled_volumes : [
      for grant in volume.grants : [
        for privilege in grant.privileges : {
          volume_key = volume_key
          principal  = grant.principal
          privilege  = privilege
        }
      ]
    ]
  ])

  volume_grant_tuple_keys = [
    for tuple in local.volume_grant_tuples :
    "${tuple.volume_key}:${tuple.principal}:${tuple.privilege}"
  ]

  duplicate_volume_grant_tuple_keys = toset([
    for key in local.volume_grant_tuple_keys : key
    if length([
      for seen in local.volume_grant_tuple_keys : seen if seen == key
    ]) > 1
  ])

  volume_grants_by_principal = {
    for volume_key, volume in local.enabled_volumes : volume_key => {
      for principal in sort(distinct([
        for grant in volume.grants : grant.principal
      ])) : principal => sort(distinct(flatten([
        for grant in volume.grants : grant.principal == principal ? grant.privileges : []
      ])))
    }
  }
}
```

- [ ] **Step 2: Check the locals block against the storage-locations module pattern**

Compare the new block with `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations/main.tf` and confirm the volume module mirrors the same tuple-flattening, duplicate-detection, and regrouping style.

- [ ] **Step 3: Re-run validation after adding locals**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate
```

Expected: validate succeeds with no duplicate-local or expression errors.

- [ ] **Step 4: Commit the normalization logic**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf
git commit -m "feat: normalize unity catalog volumes inputs"
```

Expected: one commit containing locals only.

### Task 4: Implement Volumes And Authoritative Grants

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf`

- [ ] **Step 1: Implement `databricks_volume`**

Create one resource per enabled volume:

```hcl
resource "databricks_volume" "this" {
  for_each = local.enabled_volumes

  name          = each.value.name
  catalog_name  = each.value.catalog_name
  schema_name   = each.value.schema_name
  volume_type   = each.value.volume_type
  comment       = try(each.value.comment, null)
  owner         = try(each.value.owner, null)
  storage_location = each.value.volume_type == "EXTERNAL" ? each.value.storage_location : null
}
```

- [ ] **Step 2: Add the duplicate-identity precondition to `databricks_volume`**

Use a lifecycle block like:

```hcl
lifecycle {
  precondition {
    condition     = length(local.duplicate_volume_identity_keys) == 0
    error_message = "Duplicate volume identities are not allowed: ${join(", ", sort(tolist(local.duplicate_volume_identity_keys)))}"
  }
}
```

- [ ] **Step 3: Implement authoritative `databricks_grants` for volumes**

Create one `databricks_grants` resource for each volume with non-empty grants:

```hcl
resource "databricks_grants" "volume" {
  for_each = {
    for volume_key, volume in local.enabled_volumes :
    volume_key => volume
    if length(volume.grants) > 0
  }

  volume = databricks_volume.this[each.key].id

  dynamic "grant" {
    for_each = local.volume_grants_by_principal[each.key]

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}
```

- [ ] **Step 4: Add the duplicate-grant precondition to `databricks_grants`**

Use:

```hcl
lifecycle {
  precondition {
    condition     = length(local.duplicate_volume_grant_tuple_keys) == 0
    error_message = "Duplicate volume grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_volume_grant_tuple_keys)))}"
  }
}
```

- [ ] **Step 5: Verify the module still validates**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate
```

Expected: validate succeeds. The full negative-path execution matrix for these validations and preconditions is run later in Chunk 3, Task 8, once the temporary provider-backed harness is available.

- [ ] **Step 6: Commit the resource implementation**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf
git commit -m "feat: add unity catalog volumes resources"
```

Expected: one commit containing resource logic and lifecycle protections.

### Task 5: Implement Outputs

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/outputs.tf`

- [ ] **Step 1: Expose a stable output map for created volumes**

Add an output shaped like:

```hcl
output "volumes" {
  description = "Managed Unity Catalog volumes keyed by stable caller-defined identifiers."
  value = {
    for volume_key, volume in databricks_volume.this :
    volume_key => {
      name             = volume.name
      catalog_name     = volume.catalog_name
      schema_name      = volume.schema_name
      full_name        = volume.id
      volume_type      = volume.volume_type
      storage_location = local.enabled_volumes[volume_key].volume_type == "EXTERNAL" ? volume.storage_location : null
    }
  }
}
```

- [ ] **Step 2: Validate output expressions**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate
```

Expected: validate succeeds. Confirm `storage_location = null` for managed volumes during the later root-plan verification in Chunk 3.

- [ ] **Step 3: Commit the outputs**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/outputs.tf
git commit -m "feat: add unity catalog volumes outputs"
```

Expected: one commit containing the final caller-facing output contract.

## Chunk 3: Root Integration, Documentation, And Verification

### Task 6: Add Root Caller Configuration

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/volume_config.tf`

- [ ] **Step 1: Add root locals for module input**

Create a new root config file with an empty default map and commented examples:

```hcl
locals {
  uc_volumes = {}

  /*
  uc_volumes = {
    model_artifacts = {
      name         = "model_artifacts"
      catalog_name = "prod_ml_platform"
      schema_name  = "final"
      volume_type  = "MANAGED"
    }
    inbound_files = {
      name             = "inbound_files"
      catalog_name     = "prod_salesforce_revenue"
      schema_name      = "uat"
      volume_type      = "EXTERNAL"
      storage_location = format("%s/volumes/inbound_files/", trimsuffix(module.unity_catalog_storage_locations.external_locations["revenue_raw"].url, "/"))
      grants = [
        {
          principal  = "00000000-0000-0000-0000-000000000000" # UAT promotion service principal application ID
          privileges = ["READ_VOLUME", "WRITE_VOLUME"]
        }
      ]
    }
  }
  */
}
```

- [ ] **Step 2: Add the module block with provider wiring**

Use:

```hcl
module "unity_catalog_volumes" {
  source = "./modules/databricks_workspace/unity_catalog_volumes"

  providers = {
    databricks = databricks.created_workspace
  }

  volumes = local.uc_volumes

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
  ]
}
```

- [ ] **Step 3: Encode same-stack ordering guidance in comments**

Document directly above the module block:

- keep the baseline `depends_on = [module.unity_catalog_metastore_assignment, module.users_groups]`
- pass catalog/schema names from resource or module outputs when available
- if external-location readiness is only semantic, extend `depends_on`
- for `EXTERNAL` volumes, `storage_location` must live under a pre-existing external location
- if grants reference additional Terraform-managed groups or service principals, extend `depends_on`
- if Unity Catalog readiness has extra prerequisites in the current root, extend `depends_on` rather than replacing the baseline entries

Add a commented pattern like:

```hcl
# depends_on = [
#   module.unity_catalog_metastore_assignment,
#   module.users_groups,
#   module.upstream_catalogs,
#   module.upstream_storage_locations,
# ]
```

- [ ] **Step 4: Commit the root caller**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/volume_config.tf
git commit -m "feat: add unity catalog volumes root config"
```

Expected: one commit containing a root entrypoint that is safe by default because `local.uc_volumes = {}`.

### Task 7: Update Operator Documentation

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/README.md`

- [ ] **Step 1: Add a root README section for Unity Catalog volumes**

Document:

- module purpose and scope
- `MANAGED` vs `EXTERNAL` input differences
- root ordering contract for same-stack prerequisites
- grant authority behavior
- volume deletion remains conservative because the provider does not expose a force-delete argument

- [ ] **Step 2: Tighten the module README with operator warnings**

Add explicit notes that:

- renaming stable map keys changes Terraform addresses
- non-empty deletion is conservative and cannot be overridden through this module
- `storage_location` output is `null` for managed volumes
- `EXTERNAL` volumes require an external location to exist first
- if the managing identity relies on `MANAGE`, keep that identity present in the authoritative grant set

- [ ] **Step 3: Commit the docs update**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/README.md
git commit -m "docs: add unity catalog volumes usage guidance"
```

Expected: one commit containing both root and module operator guidance.

### Task 8: Run Verification And Negative Checks

**Files:**
- Modify: none

- [ ] **Step 1: Format the Terraform tree**

Run:

```bash
terraform fmt infra/aws/dbx/databricks/us-west-1/volume_config.tf
terraform fmt -recursive infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes
```

Expected: only the new module `.tf` files and `volume_config.tf` are reformatted.

- [ ] **Step 2: Verify the new module in isolation**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes validate
```

Expected: init succeeds and validate reports success.

- [ ] **Step 3: Verify the root configuration**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: validate succeeds and plan succeeds with the default empty `local.uc_volumes`.

- [ ] **Step 4: Run the full negative-path matrix**

Use two paths:

- module-directory `terraform plan` for pure variable-validation failures
- a temporary provider-backed root harness for precondition failures that require resource evaluation

For variable-validation failures, run these from the module directory and confirm the expected error fragment appears before provider-side apply work:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="",catalog_name="c",schema_name="s",volume_type="MANAGED"}}'
```

Expected: FAIL with blank `name` validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="",schema_name="s",volume_type="MANAGED"}}'
```

Expected: FAIL with blank `catalog_name` validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="",volume_type="MANAGED"}}'
```

Expected: FAIL with blank `schema_name` validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="s",volume_type="INVALID"}}'
```

Expected: FAIL with invalid `volume_type` validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="s",volume_type="EXTERNAL"}}'
```

Expected: FAIL with `EXTERNAL` storage-location validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="s",volume_type="MANAGED",storage_location="s3://bucket/path"}}'
```

Expected: FAIL with `MANAGED` storage-location validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="s",volume_type="MANAGED",grants=[{principal="",privileges=["READ_VOLUME"]}]}}'
```

Expected: FAIL with blank `principal` validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="s",volume_type="MANAGED",grants=[{principal="Data Engineers",privileges=[]}]}}'
```

Expected: FAIL with empty privilege-list validation.

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes plan -input=false -lock=false -refresh=false \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="s",volume_type="MANAGED",grants=[{principal="Data Engineers",privileges=["CREATE_EXTERNAL_TABLE"]}]}}'
```

Expected: FAIL with invalid privilege-name validation.

Create a temporary harness for precondition-based failures.

Use `apply_patch` to create `/tmp/unity-catalog-volumes-negative/main.tf` with this content:

```patch
*** Begin Patch
*** Add File: /tmp/unity-catalog-volumes-negative/main.tf
+terraform {
+  required_providers {
+    databricks = {
+      source  = "databricks/databricks"
+      version = "~> 1.84"
+    }
+  }
+}
+
+provider "databricks" {
+  host = var.workspace_host
+}
+
+module "under_test" {
+  source = "__REPO_ROOT__/infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes"
+
+  volumes = var.volumes
+}
+
+variable "workspace_host" {
+  type = string
+}
+
+variable "volumes" {
+  type = map(any)
+}
*** End Patch
```

Then run:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
perl -0pi -e 's|__REPO_ROOT__|'"${REPO_ROOT}"'|g' /tmp/unity-catalog-volumes-negative/main.tf
WORKSPACE_HOST="$(awk -F'=' '/^existing_workspace_host/ {gsub(/[ \"]/,"",$2); print $2}' infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars)"
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=/tmp/unity-catalog-volumes-negative init -backend=false
```

Expected: `WORKSPACE_HOST` is populated from the scenario file and init succeeds.

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=/tmp/unity-catalog-volumes-negative plan -input=false -lock=false -refresh=false \
  -var="workspace_host=${WORKSPACE_HOST}" \
  -var='volumes={a={name="x",catalog_name="c",schema_name="s",volume_type="MANAGED"},b={name="x",catalog_name="c",schema_name="s",volume_type="MANAGED"}}'
```

Expected: FAIL with duplicate fully qualified volume identity precondition.

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=/tmp/unity-catalog-volumes-negative plan -input=false -lock=false -refresh=false \
  -var="workspace_host=${WORKSPACE_HOST}" \
  -var='volumes={bad={name="x",catalog_name="c",schema_name="s",volume_type="MANAGED",grants=[{principal="Data Engineers",privileges=["READ_VOLUME","READ_VOLUME"]}]}}'
```

Expected: FAIL with duplicate grant tuple precondition.

Clean up the harness after the checks:

```bash
rm -rf /tmp/unity-catalog-volumes-negative
```

Expected: the repo remains clean.

- [ ] **Step 5: Commit formatting adjustments, if any**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/volume_config.tf
git add infra/aws/dbx/databricks/us-west-1/README.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/SPEC.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/README.md
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/versions.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/variables.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/outputs.tf
git commit -m "chore: verify unity catalog volumes module"
```

Expected: commit only if `fmt` changed the known implementation files. If nothing changed, skip the commit.
