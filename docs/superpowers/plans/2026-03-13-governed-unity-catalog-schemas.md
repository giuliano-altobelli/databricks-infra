# Governed Unity Catalog Schemas Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add governed Unity Catalog schema creation and governed managed-volume orchestration through a new root `schema_config.tf` entrypoint and a focused workspace-scoped `unity_catalog_schemas` module, while removing the checked-in governed `volume_config.tf` root caller.

**Architecture:** Keep `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf` as the single source of truth for governed catalog identities and continue sourcing catalog creation from `module.governed_catalogs`. Add `infra/aws/dbx/databricks/us-west-1/schema_config.tf` to derive the fixed governed schema layers (`raw`, `base`, `staging`, `final`, `uat`), manage authoritative schema grants via a new workspace-only module, and flatten optional managed-volume declarations into the existing `unity_catalog_volumes` module with explicit dependency ordering.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider `~> 1.84`, workspace-scoped alias `databricks.created_workspace`, `direnv`, `DATABRICKS_AUTH_TYPE=oauth-m2m`

---

**Spec:** `docs/superpowers/specs/2026-03-13-governed-unity-catalog-schemas-design.md`

**Execution Notes:**
- Use `@subagent-driven-development` to execute the tasks.
- Use `@test-driven-development` before each behavioral Terraform change, even when the “test” is a failing `terraform plan` or validation check.
- Use `@verification-before-completion` before claiming success.
- Use `@requesting-code-review` after the final verification pass.
- Do not use `@using-git-worktrees`; the user explicitly asked to stay on `main`.
- Do not execute any `git commit` step until the user has approved this plan for implementation.

## File Structure

Create these root files:

- `infra/aws/dbx/databricks/us-west-1/schema_config.tf`

Create these module files:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/versions.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/outputs.tf`

Delete this template-only module file unless documentation lookups make it necessary later:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/FACTS.md`

Modify these existing operator docs:

- `infra/aws/dbx/databricks/us-west-1/README.md:73-83`

Delete this checked-in root caller:

- `infra/aws/dbx/databricks/us-west-1/volume_config.tf:1-77`

Reference these existing files while implementing, but do not change them unless a later review uncovers a real defect:

- `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf:5-210`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/outputs.tf`

Responsibilities:

- `schema_config.tf`: single checked-in governed schema policy surface, root validations, schema expansion, managed-volume flattening, and module orchestration.
- `unity_catalog_schemas/SPEC.md`: local implementation contract for schema creation and authoritative schema grants.
- `unity_catalog_schemas/README.md`: usage example, provider wiring, stable-key guidance, and grant ownership.
- `unity_catalog_schemas/variables.tf`: public input schema and validation for names, principals, privileges, and enablement.
- `unity_catalog_schemas/main.tf`: duplicate detection, `databricks_schema`, and authoritative `databricks_grants`.
- `unity_catalog_schemas/outputs.tf`: stable output map keyed by caller-defined schema keys.
- root `README.md`: operator guidance for `schema_config.tf`, governed managed volumes, and `volume_config.tf` removal.

## Chunk 1: Schema Module Contract And Interface

### Task 1: Scaffold The `unity_catalog_schemas` Module

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/SPEC.md`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/README.md`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/versions.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/variables.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/main.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/outputs.tf`
- Delete: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/FACTS.md`

- [ ] **Step 1: Populate the existing empty module directory from the repo template**

Run:

```bash
test -d infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas
test -z "$(ls -A infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas)"
cp -R infra/aws/dbx/databricks/us-west-1/modules/_module_template/. infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/
```

Expected: the pre-created empty directory is populated with the template file set without overwriting any existing implementation files.

- [ ] **Step 2: Replace the generated `SPEC.md` with the approved contract**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/SPEC.md` with these exact sections:

```md
# Module Spec

## Summary
## Scope
## Interfaces
## Provider Context
## Behavior / Data Flow
## Constraints and Failure Modes
## Validation
```

The spec must encode these boundaries verbatim:

```md
- one `databricks_schema` resource per schema entry
- one authoritative `databricks_grants` resource per schema entry when grants are declared
- workspace-level Databricks provider only
- no catalog creation
- no volume creation
- no storage credentials or external locations
- no account-level resources or `databricks.mws`
```

In `## Interfaces`, list:

- required input `schemas`
- optional input `enabled`
- `schemas[*].catalog_name`
- `schemas[*].schema_name`
- `schemas[*].comment`
- `schemas[*].grants[*].principal`
- `schemas[*].grants[*].privileges`
- the `schemas` output map with `catalog_name`, `schema_name`, and `full_name`
- the `enabled = false` behavior returning an empty output map

Document the output map here as the approved contract, but call out that the concrete `outputs.tf` implementation lands in Chunk 2 after `databricks_schema.this` exists.

In `## Validation`, list the required failure cases from the governing spec:

- blank `catalog_name`
- blank `schema_name`
- blank grant principals
- empty privilege lists
- invalid privilege names
- duplicate fully qualified schema identities across stable keys
- duplicate schema grant tuples

- [ ] **Step 3: Rewrite the module README before implementation**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/README.md` with a concrete usage example like this:

```hcl
module "unity_catalog_schemas" {
  source = "./modules/databricks_workspace/unity_catalog_schemas"

  providers = {
    databricks = databricks.created_workspace
  }

  schemas = {
    "salesforce_revenue:raw" = {
      catalog_name = "prod_salesforce_revenue"
      schema_name  = "raw"
      grants = [
        {
          principal  = "Platform Admins"
          privileges = ["ALL_PRIVILEGES"]
        }
        {
          principal  = "Revenue Readers"
          privileges = ["USE_SCHEMA"]
        }
      ]
    }
  }
}
```

The README must also explain:

- stable map keys are Terraform addresses
- grants are authoritative when declared
- the module is workspace-only and must be wired to `databricks.created_workspace`
- `enabled = false` returns an empty `schemas` map
- catalogs and volumes stay outside this module

Call out in the README that the output behavior is part of the module contract even though the concrete Terraform output is implemented in Chunk 2 with the resource graph.

- [ ] **Step 4: Align `versions.tf` and remove the unused template facts file**

Set `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/versions.tf` to:

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

Then delete the generated template facts file so the new module surface matches the governing spec:

```bash
rm infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/FACTS.md
```

- [ ] **Step 5: Validate the scaffold before deeper implementation**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas fmt
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas validate
```

Expected: both commands succeed with no placeholder-template syntax left behind.

- [ ] **Step 6: Commit the scaffold after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas
git commit -m "feat: scaffold unity catalog schemas module"
```

Expected: one commit containing only the new module scaffold and docs.

### Task 2: Define The Public Variable Contract

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/variables.tf`

- [ ] **Step 1: Replace `variables.tf` with the approved input shape**

Start from this exact structure:

```hcl
variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "schemas" {
  description = "Unity Catalog schemas keyed by stable caller-defined identifiers."
  type = map(object({
    catalog_name = string
    schema_name  = string
    comment      = optional(string)
    grants = optional(list(object({
      principal  = string
      privileges = list(string)
    })), [])
  }))
}
```

- [ ] **Step 2: Add variable validation for names, principals, and privilege shapes**

Add validation blocks that reject:

- blank `catalog_name`
- blank `schema_name`
- blank grant principals
- empty privilege lists
- privileges outside `ALL_PRIVILEGES` and `USE_SCHEMA`

State explicitly in comments or task notes that duplicate fully qualified schema identities and duplicate schema grant tuples are enforced in Chunk 2 because they depend on `main.tf` locals rather than variable validation alone.

Use near-final expressions like:

```hcl
validation {
  condition = !var.enabled || alltrue([
    for schema in values(var.schemas) :
    trimspace(schema.catalog_name) != "" &&
    trimspace(schema.schema_name) != ""
  ])
  error_message = "Each schema must declare non-empty catalog_name and schema_name values."
}

validation {
  condition = !var.enabled || alltrue(flatten([
    for schema in values(var.schemas) : [
      for grant in schema.grants : trimspace(grant.principal) != ""
    ]
  ]))
  error_message = "Each schema grant principal must be non-empty."
}

validation {
  condition = !var.enabled || alltrue(flatten([
    for schema in values(var.schemas) : [
      for grant in schema.grants : length(grant.privileges) > 0
    ]
  ]))
  error_message = "Each schema grant must declare at least one privilege."
}

validation {
  condition = !var.enabled || alltrue(flatten([
    for schema in values(var.schemas) : [
      for grant in schema.grants : [
        for privilege in grant.privileges :
        contains(["ALL_PRIVILEGES", "USE_SCHEMA"], privilege)
      ]
    ]
  ]))
  error_message = "Schema grant privileges must be one of: ALL_PRIVILEGES, USE_SCHEMA."
}
```

- [ ] **Step 3: Validate the input contract before resource implementation**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas validate
```

Expected: validate succeeds with the new variable contract in place, even before the schema resources exist.

- [ ] **Step 4: Prove one negative path for the variable contract in a disposable scratch root**

Run:

```bash
repo_root="$(git rev-parse --show-toplevel)"
scratch_dir="$(mktemp -d /tmp/uc-schema-variable-contract.XXXXXX)"
cat > "${scratch_dir}/main.tf" <<EOF
module "under_test" {
  source = "${repo_root}/infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas"

  schemas = {
    invalid = {
      catalog_name = "prod_salesforce_revenue"
      schema_name  = "raw"
      grants = [
        {
          principal  = "Platform Admins"
          privileges = ["READ_VOLUME"]
        }
      ]
    }
  }
}
EOF
terraform -chdir="${scratch_dir}" init -backend=false
terraform -chdir="${scratch_dir}" validate
```

Expected: validation fails with `Schema grant privileges must be one of: ALL_PRIVILEGES, USE_SCHEMA.`

- [ ] **Step 5: Commit the variable contract after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/variables.tf
git commit -m "feat: define unity catalog schema module input contract"
```

Expected: one commit containing only the variable contract changes.

## Chunk 2: Schema Module Resources And Validation

### Task 3: Implement Schema Resources And Authoritative Grants

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/main.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/outputs.tf`

- [ ] **Step 1: Add the locals needed for duplicate detection and grant regrouping**

Model `main.tf` after the existing grant-normalization pattern in `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf`, but adapt it for schemas:

```hcl
locals {
  enabled_schemas = var.enabled ? var.schemas : {}

  schema_identity_keys = [
    for schema_key, schema in local.enabled_schemas :
    format(
      "%s.%s",
      lower(trimspace(schema.catalog_name)),
      lower(trimspace(schema.schema_name))
    )
  ]

  duplicate_schema_identity_keys = toset([
    for key in local.schema_identity_keys : key
    if length([
      for seen in local.schema_identity_keys : seen if seen == key
    ]) > 1
  ])

  schema_grant_tuples = flatten([
    for schema_key, schema in local.enabled_schemas : [
      for grant in schema.grants : [
        for privilege in grant.privileges : {
          schema_key = schema_key
          principal  = grant.principal
          privilege  = privilege
        }
      ]
    ]
  ])

  schema_grant_tuple_keys = [
    for tuple in local.schema_grant_tuples :
    "${tuple.schema_key}:${tuple.principal}:${tuple.privilege}"
  ]

  duplicate_schema_grant_tuple_keys = toset([
    for key in local.schema_grant_tuple_keys : key
    if length([
      for seen in local.schema_grant_tuple_keys : seen if seen == key
    ]) > 1
  ])

  schema_grants_by_principal = {
    for schema_key, schema in local.enabled_schemas : schema_key => {
      for principal in sort(distinct([
        for grant in schema.grants : grant.principal
      ])) : principal => sort(distinct(flatten([
        for grant in schema.grants : grant.principal == principal ? grant.privileges : []
      ])))
    }
  }
}
```

- [ ] **Step 2: Create one `databricks_schema` resource per stable schema key**

Add the resource:

```hcl
resource "databricks_schema" "this" {
  for_each = local.enabled_schemas

  catalog_name = each.value.catalog_name
  name         = each.value.schema_name
  comment      = try(each.value.comment, null)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_schema_identity_keys) == 0
      error_message = "Duplicate schema identities are not allowed: ${join(", ", sort(tolist(local.duplicate_schema_identity_keys)))}"
    }
  }
}
```

Do not add owner, volume, or catalog logic to this module.

- [ ] **Step 3: Create authoritative `databricks_grants` resources for schemas with grants**

Add a second resource following the same regroup-by-principal pattern used by the storage-location and volume modules:

```hcl
resource "databricks_grants" "schema" {
  for_each = {
    for schema_key, schema in local.enabled_schemas :
    schema_key => schema
    if length(schema.grants) > 0
  }

  schema = databricks_schema.this[each.key].id

  dynamic "grant" {
    for_each = local.schema_grants_by_principal[each.key]

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_schema_grant_tuple_keys) == 0
      error_message = "Duplicate schema grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_schema_grant_tuple_keys)))}"
    }
  }
}
```

The module must remain authoritative only for schema grants, not table or volume privileges.

- [ ] **Step 4: Add the stable `schemas` output once the resources exist**

Write `outputs.tf` so the module returns:

```hcl
output "schemas" {
  description = "Managed Unity Catalog schemas keyed by stable caller-defined identifiers."
  value = {
    for schema_key, schema in databricks_schema.this :
    schema_key => {
      catalog_name = local.enabled_schemas[schema_key].catalog_name
      schema_name  = local.enabled_schemas[schema_key].schema_name
      full_name    = schema.id
    }
  }
}
```

When `enabled = false`, this output must naturally collapse to `{}`.

- [ ] **Step 5: Run module init and validation after the resource graph lands**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas validate
```

Expected: init succeeds and validate succeeds with no unsupported arguments remaining on either resource.

- [ ] **Step 6: Commit the resource implementation after user approval to execute**

Only run this commit after Task 6, Step 4 has exercised the module negative-path checks for duplicate schema identities, duplicate schema grant tuples, and invalid schema privileges with the expected failure messages.

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/main.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/outputs.tf
git commit -m "feat: implement unity catalog schema resources"
```

Expected: one commit containing the schema resources and duplicate-detection locals.

## Chunk 3: Root Orchestration And Volume Re-home

### Task 4: Add `schema_config.tf` As The Governed Schema Entrypoint

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf:5-210`

- [ ] **Step 1: Create the governed schema config surface and keep it governed-only**

Start `schema_config.tf` with a root local shaped exactly like the design spec:

```hcl
locals {
  governed_schema_config = {
    # salesforce_revenue = {
    #   managed_volumes = {
    #     final = {
    #       model_artifacts = {
    #         name = "model_artifacts"
    #       }
    #     }
    #     uat = {
    #       candidate_assets = {
    #         name = "candidate_assets"
    #       }
    #     }
    #   }
    #
    #   # Placeholder only for future schema-writer rollout:
    #   # uat_writer_principals     = ["00000000-0000-0000-0000-000000000000"]
    #   # release_writer_principals = ["11111111-1111-1111-1111-111111111111"]
    # }
  }

  standard_governed_schema_names = ["raw", "base", "staging", "final", "uat"]

  governed_catalogs_for_schemas = {
    for catalog_key, catalog in local.catalogs :
    catalog_key => catalog
    if catalog.catalog_kind == "governed"
  }
}
```

Do not implement `personal.<user_key>` schema creation in this file.

- [ ] **Step 2: Normalize the config and add root `check` blocks**

Add normalization locals and `check` blocks that reject:

- unknown keys in `local.governed_schema_config`
- keys that exist in `local.catalogs` but are not governed catalogs
- managed-volume declarations under unsupported schema names
- explicit `grants = []` on managed-volume overrides
- blank principals inside managed-volume override grants
- empty privilege lists inside managed-volume override grants
- invalid managed-volume override privilege names

Use a normalization local shaped like:

```hcl
locals {
  normalized_governed_schema_config = {
    for catalog_key, catalog in local.governed_catalogs_for_schemas :
    catalog_key => {
      managed_volumes = {
        for schema_name, volumes in try(local.governed_schema_config[catalog_key].managed_volumes, {}) :
        schema_name => {
          for volume_key, volume in volumes :
          volume_key => {
            name    = trimspace(try(volume.name, volume_key))
            comment = try(volume.comment, null)
            owner   = try(volume.owner, null)
            grants  = try(volume.grants, null)
          }
        }
      }
    }
  }
}
```

Use checks shaped like:

```hcl
check "governed_schema_config_known_catalog_keys" {
  assert {
    condition = length(setsubtract(
      keys(local.governed_schema_config),
      keys(local.catalogs)
    )) == 0
    error_message = "governed_schema_config keys must already exist in local.catalogs."
  }
}

check "governed_schema_config_governed_catalog_only" {
  assert {
    condition = length(setsubtract(
      keys(local.governed_schema_config),
      keys(local.governed_catalogs_for_schemas)
    )) == 0
    error_message = "governed_schema_config may reference governed catalogs only."
  }
}
```

For managed-volume override privileges, use the existing `unity_catalog_volumes` privilege contract:

```hcl
["ALL_PRIVILEGES", "APPLY_TAG", "MANAGE", "READ_VOLUME", "WRITE_VOLUME"]
```

Add explicit root checks for override grant shape so invalid overrides fail before the reused volume module runs:

```hcl
check "governed_managed_volume_override_principals" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for volumes in values(catalog.managed_volumes) : [
          for volume in values(volumes) : [
            for grant in try(volume.grants, []) : trimspace(grant.principal) != ""
          ]
        ]
      ]
    ]))
    error_message = "Managed-volume override grant principals must be non-empty."
  }
}

check "governed_managed_volume_override_privilege_lists" {
  assert {
    condition = alltrue(flatten([
      for catalog in values(local.normalized_governed_schema_config) : [
        for volumes in values(catalog.managed_volumes) : [
          for volume in values(volumes) : [
            for grant in try(volume.grants, []) : length(grant.privileges) > 0
          ]
        ]
      ]
    ]))
    error_message = "Managed-volume override grants must declare at least one privilege."
  }
}
```

- [ ] **Step 3: Expand every governed catalog into five schema records with default grants**

Derive a map keyed by `<catalog_key>:<schema_name>`:

```hcl
locals {
  governed_schemas = {
    for record in flatten([
      for catalog_key, catalog in local.governed_catalogs_for_schemas : [
        for schema_name in local.standard_governed_schema_names : {
          key = "${catalog_key}:${schema_name}"
          value = {
            catalog_name = module.governed_catalogs[catalog_key].catalog_name
            schema_name  = schema_name
            grants = concat(
              [
                {
                  principal  = catalog.catalog_admin_principal
                  privileges = ["ALL_PRIVILEGES"]
                }
              ],
              [
                for principal in catalog.catalog_reader_principals : {
                  principal  = principal
                  privileges = ["USE_SCHEMA"]
                }
              ]
            )
          }
        }
      ]
    ]) : record.key => record.value
  }
}
```

Do not add writer-principal logic in this rollout.

- [ ] **Step 4: Wire the new schema module with the required dependency contract**

Add:

```hcl
module "unity_catalog_schemas" {
  source = "./modules/databricks_workspace/unity_catalog_schemas"

  providers = {
    databricks = databricks.created_workspace
  }

  schemas = local.governed_schemas

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.governed_catalogs,
  ]
}
```

Keep `module.governed_catalogs` in `depends_on` even though the catalog names are also referenced.

- [ ] **Step 5: Validate the new root entrypoint before volume integration**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt schema_config.tf
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: formatting succeeds and root validate passes with the new module call present.

- [ ] **Step 6: Commit the root schema entrypoint after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/schema_config.tf
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas
git commit -m "feat: add governed unity catalog schema entrypoint"
```

Expected: one commit containing the new root entrypoint and any schema-module refinements needed to support it.

### Task 5: Reuse `unity_catalog_volumes` For Governed Managed Volumes And Remove `volume_config.tf`

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- Delete: `infra/aws/dbx/databricks/us-west-1/volume_config.tf:1-77`

- [ ] **Step 1: Flatten optional managed volumes out of `governed_schema_config`**

In `schema_config.tf`, derive a `local.governed_managed_volumes` map keyed by `<catalog_key>:<schema_name>:<volume_key>`:

```hcl
locals {
  governed_managed_volumes = {
    for record in flatten([
      for catalog_key, catalog in local.governed_catalogs_for_schemas : [
        for schema_name, volumes in local.normalized_governed_schema_config[catalog_key].managed_volumes : [
          for volume_key, volume in volumes : {
            key = "${catalog_key}:${schema_name}:${volume_key}"
            value = {
              name         = trimspace(try(volume.name, volume_key))
              catalog_name = module.governed_catalogs[catalog_key].catalog_name
              schema_name  = schema_name
              volume_type  = "MANAGED"
              comment      = try(volume.comment, null)
              owner        = try(volume.owner, null)
              grants = try(volume.grants, null) != null ? volume.grants : concat(
                [
                  {
                    principal  = catalog.catalog_admin_principal
                    privileges = ["ALL_PRIVILEGES"]
                  }
                ],
                [
                  for principal in catalog.catalog_reader_principals : {
                    principal  = principal
                    privileges = ["READ_VOLUME"]
                  }
                ]
              )
            }
          }
        ]
      ]
    ]) : record.key => record.value
  }
}
```

Use `local.normalized_governed_schema_config[catalog_key].managed_volumes` for the `volumes` expression in that loop. Treat any explicit non-empty `grants` list as a full replacement, not a merge.

- [ ] **Step 2: Add duplicate managed-volume identity validation**

Before the module call, compute fully qualified volume identities and reject duplicates after flattening:

```hcl
locals {
  managed_volume_identity_keys = [
    for volume in values(local.governed_managed_volumes) :
    format(
      "%s.%s.%s",
      lower(trimspace(volume.catalog_name)),
      lower(trimspace(volume.schema_name)),
      lower(trimspace(volume.name))
    )
  ]

  duplicate_managed_volume_identity_keys = toset([
    for key in local.managed_volume_identity_keys : key
    if length([
      for seen in local.managed_volume_identity_keys : seen if seen == key
    ]) > 1
  ])
}

check "governed_managed_volume_identities" {
  assert {
    condition     = length(local.duplicate_managed_volume_identity_keys) == 0
    error_message = "Duplicate governed managed-volume identities are not allowed."
  }
}
```

- [ ] **Step 3: Move the governed volume caller into `schema_config.tf` and delete `volume_config.tf` in one edit**

In the same file-editing step:

- add a `module "unity_catalog_volumes"` block in `schema_config.tf`
- delete `infra/aws/dbx/databricks/us-west-1/volume_config.tf`

Use this module block in `schema_config.tf`:

```hcl
module "unity_catalog_volumes" {
  source = "./modules/databricks_workspace/unity_catalog_volumes"

  providers = {
    databricks = databricks.created_workspace
  }

  volumes = local.governed_managed_volumes

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.governed_catalogs,
    module.unity_catalog_schemas,
  ]
}
```

This must become the only checked-in governed root caller for managed volumes before any `terraform validate` or `terraform plan` command is run.

- [ ] **Step 4: Verify that only the new governed volume caller remains**

Run:

```bash
rg -n "volume_config\\.tf|schema_config\\.tf" infra/aws/dbx/databricks/us-west-1/README.md
rg -n "module \"unity_catalog_volumes\"" infra/aws/dbx/databricks/us-west-1
```

Expected:

- root docs still mention `volume_config.tf` until the README task updates them
- only one checked-in `module "unity_catalog_volumes"` block remains, now in `schema_config.tf`

- [ ] **Step 5: Commit the managed-volume re-home after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/schema_config.tf
git add infra/aws/dbx/databricks/us-west-1/volume_config.tf
git commit -m "feat: govern managed volumes from schema config"
```

Expected: one commit that moves governed managed-volume orchestration under `schema_config.tf` and removes `volume_config.tf`.

## Chunk 4: Verification And Operator Docs

### Task 6: Update Operator Docs And Run Full Verification

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md:73-83`
- Test: `/tmp/uc-schema-root.XXXXXX/`

- [ ] **Step 1: Update the root README to point governed schema and managed-volume guidance at `schema_config.tf`**

Replace the current `## Unity Catalog Volumes` section with a new section that explains:

- governed schemas are configured in `schema_config.tf`
- the standard schema set is `raw`, `base`, `staging`, `final`, and `uat`
- this rollout creates governed schemas only and does not create `personal.<user_key>` schemas
- governed catalog keys omitted from `governed_schema_config` still get the standard schemas and default schema grants
- optional managed volumes are declared under `managed_volumes` inside `governed_schema_config`
- omitted managed-volume `grants` inherit admin `ALL_PRIVILEGES` and reader `READ_VOLUME`
- explicit managed-volume `grants` replace the derived defaults
- commented `uat_writer_principals` and `release_writer_principals` examples are placeholders only in this rollout
- the checked-in governed `volume_config.tf` entrypoint was intentionally removed

- [ ] **Step 2: Run formatting and the required module and root verification commands**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas validate
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- module init and validate succeed
- formatting produces no remaining diffs
- root validate succeeds
- the default checked-in `scenario1.premium-existing.tfvars` plan stays on the `personal`-only baseline and does not fail because `schema_config.tf` exists

- [ ] **Step 3: Exercise the real success path in a disposable scratch copy**

Run:

```bash
scratch_dir="$(mktemp -d /tmp/uc-schema-root.XXXXXX)"
rsync -a infra/aws/dbx/databricks/us-west-1/ "${scratch_dir}/"
terraform -chdir="${scratch_dir}" init -backend=false
```

Then edit `${scratch_dir}/catalogs_config.tf` and uncomment exactly these governed catalog examples:

```hcl
salesforce_revenue = {
  enabled             = true
  display_name        = "Salesforce Revenue"
  source              = "salesforce"
  business_area       = "revenue"
  catalog_admin_group = "platform_admins"
  reader_group        = []
}

hubspot_shared = {
  enabled             = true
  display_name        = "HubSpot Shared"
  source              = "hubspot"
  business_area       = ""
  catalog_admin_group = "platform_admins"
  reader_group        = []
}
```

Edit `${scratch_dir}/schema_config.tf` and add exactly this managed-volume example, leaving `hubspot_shared` absent from `governed_schema_config`:

```hcl
salesforce_revenue = {
  managed_volumes = {
    final = {
      model_artifacts = {
        name = "model_artifacts"
      }
    }
  }
}
```

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- the plan includes all five schema resources for `salesforce_revenue`: `raw`, `base`, `staging`, `final`, and `uat`
- the plan includes all five schema resources for `hubspot_shared` even though that catalog is omitted from `governed_schema_config`
- the plan includes `module.unity_catalog_volumes.databricks_volume.this["salesforce_revenue:final:model_artifacts"]`
- the plan does not include any managed-volume resources keyed under `hubspot_shared`

- [ ] **Step 4: Exercise module-level negative checks in the same scratch root**

Create `${scratch_dir}/schema_module_negative.tf` and test these cases one at a time, keeping only one invalid case in the file per run:

Duplicate schema identity:

```hcl
module "schema_negative_test" {
  source = "./modules/databricks_workspace/unity_catalog_schemas"

  providers = {
    databricks = databricks.created_workspace
  }

  schemas = {
    first = {
      catalog_name = "prod_salesforce_revenue"
      schema_name  = "raw"
    }
    second = {
      catalog_name = "prod_salesforce_revenue"
      schema_name  = "raw"
    }
  }
}
```

Duplicate schema grant tuple:

```hcl
module "schema_negative_test" {
  source = "./modules/databricks_workspace/unity_catalog_schemas"

  providers = {
    databricks = databricks.created_workspace
  }

  schemas = {
    first = {
      catalog_name = "prod_salesforce_revenue"
      schema_name  = "raw"
      grants = [
        {
          principal  = "Platform Admins"
          privileges = ["USE_SCHEMA", "USE_SCHEMA"]
        }
      ]
    }
  }
}
```

Invalid schema privilege:

```hcl
module "schema_negative_test" {
  source = "./modules/databricks_workspace/unity_catalog_schemas"

  providers = {
    databricks = databricks.created_workspace
  }

  schemas = {
    first = {
      catalog_name = "prod_salesforce_revenue"
      schema_name  = "raw"
      grants = [
        {
          principal  = "Platform Admins"
          privileges = ["READ_VOLUME"]
        }
      ]
    }
  }
}
```

Run after each edit:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- duplicate identity fails with `Duplicate schema identities are not allowed`
- duplicate tuple fails with `Duplicate schema grant tuples are not allowed`
- invalid privilege fails with `Schema grant privileges must be one of: ALL_PRIVILEGES, USE_SCHEMA`

Delete `${scratch_dir}/schema_module_negative.tf` when finished.

- [ ] **Step 5: Exercise root-level negative checks for managed volumes**

In the scratch `schema_config.tf`, test these cases one at a time and rerun the same `terraform plan` command after each edit:

- unknown `governed_schema_config` key:

```hcl
unknown_catalog = {
  managed_volumes = {}
}
```

- non-governed catalog key:

```hcl
personal = {
  managed_volumes = {
    final = {
      bad_volume = {
        name = "bad_volume"
      }
    }
  }
}
```

- unsupported schema name:

```hcl
salesforce_revenue = {
  managed_volumes = {
    sandbox = {
      bad_volume = {
        name = "bad_volume"
      }
    }
  }
}
```

- duplicate fully qualified managed-volume identity:

```hcl
salesforce_revenue = {
  managed_volumes = {
    final = {
      one = {
        name = "model_artifacts"
      }
      two = {
        name = "model_artifacts"
      }
    }
  }
}
```

- explicit empty override list:

```hcl
salesforce_revenue = {
  managed_volumes = {
    final = {
      model_artifacts = {
        name   = "model_artifacts"
        grants = []
      }
    }
  }
}
```

- blank override principal:

```hcl
salesforce_revenue = {
  managed_volumes = {
    final = {
      model_artifacts = {
        name = "model_artifacts"
        grants = [
          {
            principal  = ""
            privileges = ["READ_VOLUME"]
          }
        ]
      }
    }
  }
}
```

- empty override privilege list:

```hcl
salesforce_revenue = {
  managed_volumes = {
    final = {
      model_artifacts = {
        name = "model_artifacts"
        grants = [
          {
            principal  = "Platform Admins"
            privileges = []
          }
        ]
      }
    }
  }
}
```

- invalid volume override privilege:

```hcl
salesforce_revenue = {
  managed_volumes = {
    final = {
      model_artifacts = {
        name = "model_artifacts"
        grants = [
          {
            principal  = "Platform Admins"
            privileges = ["USE_SCHEMA"]
          }
        ]
      }
    }
  }
}
```

Expected:

- unknown catalog key fails before apply
- non-governed catalog key fails before apply
- unsupported schema name fails before apply
- duplicate volume identity fails before apply
- `grants = []` fails before apply
- blank override principal fails before apply
- empty override privilege list fails before apply
- invalid override privilege fails before apply with the root validation message, not a provider error

- [ ] **Step 6: Commit docs and verification-facing cleanup after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs: document governed unity catalog schemas"
```

Expected: one doc-only commit with the final operator guidance.

- [ ] **Step 7: Request code review after all verification passes**

Run `@requesting-code-review` with:

- the final diff summary
- the `scenario1.premium-existing.tfvars` plan result
- the scratch success-path plan result
- the negative-path checks that were exercised

Expected: review feedback is captured before merge or apply.
