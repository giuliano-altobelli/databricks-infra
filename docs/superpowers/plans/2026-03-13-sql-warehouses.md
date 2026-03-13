# SQL Warehouses Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a workspace-scoped Databricks SQL warehouses module plus a root `sql_warehouses.tf` caller that can create new SQL warehouses, manage their authoritative ACLs, and expose stable connection outputs without adopting existing warehouses or creating identities.

**Architecture:** Create a new `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses` module that accepts one stable-keyed `sql_warehouses` map, creates one `databricks_sql_endpoint` and one authoritative `databricks_permissions` resource per key, and publishes stable output maps keyed by those same caller-owned keys. Keep the checked-in root surface in `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`, wire only the workspace-scoped `databricks.created_workspace` provider, keep the checked-in configuration disabled by default on `main`, and leave identity creation, account-level resources, and Unity Catalog grants outside this module boundary.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider `~> 1.84`, workspace-scoped `databricks.created_workspace`, `direnv`, `DATABRICKS_AUTH_TYPE=oauth-m2m`, Markdown docs

---

**Spec:** `docs/superpowers/specs/2026-03-13-sql-warehouses-design.md`

**Execution Notes:**
- Use `@subagent-driven-development` to execute the tasks.
- Use `@test-driven-development` before each behavioral Terraform change, even when the “test” is a failing `terraform validate` or `terraform plan`.
- Use `@verification-before-completion` before claiming success.
- Use `@requesting-code-review` after the final verification pass.
- Do not use `@using-git-worktrees`; the user explicitly asked to stay on `main`.
- Do not invoke `@brainstorming`; the design and scope are already fixed by the approved spec.
- Keep the scope workspace-level only. Do not add account-level resources, identity creation, workspace assignments, entitlements, Unity Catalog grants, cluster policies, jobs, dashboards, queries, or multi-workspace fan-out.
- Keep the checked-in root caller disabled by default on `main`.
- Use the repo-standard root verification command shape only: `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 <plan|apply> -var-file=scenario1.premium-existing.tfvars`
- Do not execute any `git commit` step until the user has approved this plan for implementation.

## File Structure

Create these module files:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/versions.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/outputs.tf`

Delete this template-only file after scaffolding:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/FACTS.md`

Create this root caller:

- `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`

Modify this operator doc:

- `infra/aws/dbx/databricks/us-west-1/README.md`

Reference these existing files while implementing, but do not change them unless a later review uncovers a real defect:

- `ARCHITECTURE.md`
- `docs/superpowers/specs/2026-03-13-sql-warehouses-design.md`
- `infra/aws/dbx/databricks/us-west-1/provider.tf`
- `infra/aws/dbx/databricks/us-west-1/identify.tf`
- `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- `infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/_module_template/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy/versions.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy/outputs.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/outputs.tf`

Responsibilities:

- `sql_warehouses/SPEC.md`: local implementation contract for SQL warehouse creation, authoritative ACL ownership, validation, and outputs.
- `sql_warehouses/README.md`: workspace-scoped usage example, provider wiring, principal-name semantics, stable-key rules, and authoritative ACL behavior.
- `sql_warehouses/versions.tf`: Databricks provider version for a workspace-scoped module.
- `sql_warehouses/variables.tf`: public input contract and all input-time validation rules required by the spec.
- `sql_warehouses/main.tf`: resource graph, permission normalization, duplicate detection, block expansion for `channel` and `tags`, and authoritative ACL translation.
- `sql_warehouses/outputs.tf`: stable maps for IDs, names, JDBC URLs, and ODBC parameters.
- `sql_warehouses.tf`: root SQL warehouse catalog, safe-by-default enable flag, explicit provider wiring, and explicit dependencies on identities already resolved outside the module.
- root `README.md`: operator guidance for enabling and populating the new SQL warehouse catalog without expecting it to create identities or manage Unity Catalog access.

## Chunk 1: Module Contract, Inputs, And Resource Graph

### Task 1: Scaffold The Workspace SQL Warehouses Module

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/SPEC.md`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/README.md`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/versions.tf`
- Delete: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/FACTS.md`

- [ ] **Step 1: Scaffold the new module from the repo template**

Run:

```bash
test ! -e infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses
scripts/new_module.sh databricks_workspace/sql_warehouses
```

Expected: the new module directory exists with the template file set and no existing implementation is overwritten.

- [ ] **Step 2: Replace `SPEC.md` with the approved SQL warehouses contract**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/SPEC.md` with these exact top-level sections:

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

The spec must encode these boundaries explicitly:

```md
- workspace-level only
- one `databricks_sql_endpoint` per caller-defined warehouse key
- one authoritative `databricks_permissions` resource per managed warehouse using `sql_endpoint_id`
- `sql_warehouses` is the single required caller-owned map input
- `enabled = false` collapses all resources and outputs to empty maps
- groups, users, and service principals are referenced by Databricks-native identifiers only
- the module does not discover or create identities
- the module does not adopt existing warehouses
- the module does not manage account-level resources, entitlements, workspace assignments, or Unity Catalog grants
- the module exposes stable maps for warehouse IDs, names, JDBC URLs, and ODBC parameters
```

In `## Interfaces`, list:

- required input `sql_warehouses`
- optional input `enabled`
- `sql_warehouses[*].name`
- `sql_warehouses[*].cluster_size`
- `sql_warehouses[*].max_num_clusters`
- `sql_warehouses[*].enable_serverless_compute`
- `sql_warehouses[*].permissions[*].principal_type`
- `sql_warehouses[*].permissions[*].principal_name`
- `sql_warehouses[*].permissions[*].permission_level`
- optional settings `min_num_clusters`, `auto_stop_mins`, `spot_instance_policy`, `enable_photon`, `warehouse_type`, `no_wait`, `channel`, and `tags`
- output maps `warehouse_ids`, `warehouse_names`, `jdbc_urls`, and `odbc_params`

In `## Validation`, list the required failure cases from the governing design:

- unsupported `principal_type`
- unsupported warehouse permission level
- empty `permissions`
- duplicate permission tuples
- duplicate managed warehouse names
- invalid `cluster_size`
- invalid `spot_instance_policy`
- invalid `warehouse_type`
- invalid `channel.name`
- invalid `min_num_clusters`
- invalid `max_num_clusters`
- `max_num_clusters < min_num_clusters`
- `enable_serverless_compute = true` with `warehouse_type = "CLASSIC"`

Also call out these runtime failure modes in `## Constraints and Failure Modes`:

- insufficient workspace-level privileges to create SQL warehouses
- insufficient workspace-level privileges to manage warehouse ACLs
- principal identifiers that do not exist in the target workspace
- workspace capability mismatches for serverless or other compute settings

- [ ] **Step 3: Rewrite `README.md` with a concrete workspace-scoped usage example**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/README.md` with a working-shaped example like this:

```hcl
module "sql_warehouses" {
  source = "./modules/databricks_workspace/sql_warehouses"

  providers = {
    databricks = databricks.created_workspace
  }

  sql_warehouses = {
    analytics_ci = {
      name                      = "Analytics CI Warehouse"
      cluster_size              = "2X-Small"
      max_num_clusters          = 1
      auto_stop_mins            = 10
      enable_serverless_compute = false
      warehouse_type            = "PRO"
      enable_photon             = true
      channel = {
        name = "CHANNEL_NAME_CURRENT"
      }
      tags = {
        Environment = "shared"
        Owner       = "data-platform"
      }
      permissions = [
        {
          principal_type   = "group"
          principal_name   = "Platform Admins"
          permission_level = "CAN_MANAGE"
        },
        {
          principal_type   = "service_principal"
          principal_name   = "00000000-0000-0000-0000-000000000000"
          permission_level = "CAN_USE"
        }
      ]
    }
  }
}
```

The README must also explain:

- stable map keys are Terraform addresses and downstream lookup keys
- this module requires only the workspace-scoped Databricks provider
- `principal_name` for groups is the workspace display name
- `principal_name` for users is the Databricks `user_name`, typically an email
- `principal_name` for service principals is the Databricks application ID
- warehouse ACLs are authoritative because the module owns one `databricks_permissions` resource per warehouse
- `enabled = false` returns empty output maps
- identity creation, entitlements, workspace assignments, and Unity Catalog grants remain outside this module

- [ ] **Step 4: Set the provider version in `versions.tf` and remove the unused facts file**

Replace `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/versions.tf` with:

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

Then remove the template-only facts file:

```bash
rm infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/FACTS.md
```

- [ ] **Step 5: Format and re-read the scaffold before deeper implementation**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses fmt
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/SPEC.md
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/README.md
sed -n '1,120p' infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/versions.tf
```

Expected: the scaffold is formatted, the module docs match the approved design, and the module is clearly workspace-scoped only.

- [ ] **Step 6: Commit the scaffold after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses
git commit -m "feat(sql): scaffold sql warehouses module"
```

Expected: one commit containing only the new SQL warehouses module scaffold and docs.

### Task 2: Define The Public Variable Contract And Validation Rules

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/variables.tf`

- [ ] **Step 1: Replace `variables.tf` with the approved SQL warehouse input contract**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/variables.tf` as:

```hcl
variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "sql_warehouses" {
  description = "SQL warehouses keyed by stable caller-defined identifiers."
  type = map(object({
    name                      = string
    cluster_size              = string
    max_num_clusters          = number
    enable_serverless_compute = bool
    permissions = list(object({
      principal_type   = string
      principal_name   = string
      permission_level = optional(string, "CAN_USE")
    }))
    min_num_clusters    = optional(number)
    auto_stop_mins      = optional(number)
    spot_instance_policy = optional(string)
    enable_photon       = optional(bool)
    warehouse_type      = optional(string)
    no_wait             = optional(bool)
    channel = optional(object({
      name = optional(string, "CHANNEL_NAME_CURRENT")
    }))
    tags = optional(map(string))
  }))

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      length(warehouse.permissions) > 0
    ])
    error_message = "Each SQL warehouse must declare at least one permission entry."
  }

  validation {
    condition = !var.enabled || length([
      for warehouse in values(var.sql_warehouses) : warehouse.name
    ]) == length(toset([
      for warehouse in values(var.sql_warehouses) : warehouse.name
    ]))
    error_message = "Managed SQL warehouse names must be unique across sql_warehouses."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for warehouse in values(var.sql_warehouses) : [
        for grant in warehouse.permissions :
        contains(["group", "user", "service_principal"], grant.principal_type)
      ]
    ]))
    error_message = "Each permission principal_type must be one of: group, user, service_principal."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for warehouse in values(var.sql_warehouses) : [
        for grant in warehouse.permissions :
        contains(["CAN_USE", "CAN_MONITOR", "CAN_MANAGE", "CAN_VIEW", "IS_OWNER"], coalesce(try(grant.permission_level, null), "CAN_USE"))
      ]
    ]))
    error_message = "Each permission permission_level must be one of: CAN_USE, CAN_MONITOR, CAN_MANAGE, CAN_VIEW, IS_OWNER."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      contains(["2X-Small", "X-Small", "Small", "Medium", "Large", "X-Large", "2X-Large", "3X-Large", "4X-Large"], warehouse.cluster_size)
    ])
    error_message = "Each SQL warehouse cluster_size must match the Databricks SQL warehouse supported sizes."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.spot_instance_policy, null) == null || contains(["COST_OPTIMIZED", "RELIABILITY_OPTIMIZED"], warehouse.spot_instance_policy)
    ])
    error_message = "Each SQL warehouse spot_instance_policy must be COST_OPTIMIZED or RELIABILITY_OPTIMIZED when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.warehouse_type, null) == null || contains(["PRO", "CLASSIC"], warehouse.warehouse_type)
    ])
    error_message = "Each SQL warehouse warehouse_type must be PRO or CLASSIC when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.channel.name, null) == null || contains(["CHANNEL_NAME_CURRENT", "CHANNEL_NAME_PREVIEW"], warehouse.channel.name)
    ])
    error_message = "Each SQL warehouse channel.name must be CHANNEL_NAME_CURRENT or CHANNEL_NAME_PREVIEW when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      warehouse.max_num_clusters > 0 && floor(warehouse.max_num_clusters) == warehouse.max_num_clusters
    ])
    error_message = "Each SQL warehouse max_num_clusters must be a positive integer."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.min_num_clusters, null) == null || (warehouse.min_num_clusters > 0 && floor(warehouse.min_num_clusters) == warehouse.min_num_clusters)
    ])
    error_message = "Each SQL warehouse min_num_clusters must be a positive integer when set."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      try(warehouse.min_num_clusters, null) == null || warehouse.max_num_clusters >= warehouse.min_num_clusters
    ])
    error_message = "Each SQL warehouse max_num_clusters must be greater than or equal to min_num_clusters."
  }

  validation {
    condition = !var.enabled || alltrue([
      for warehouse in values(var.sql_warehouses) :
      !warehouse.enable_serverless_compute || coalesce(try(warehouse.warehouse_type, null), "PRO") != "CLASSIC"
    ])
    error_message = "SQL warehouses with enable_serverless_compute = true must not set warehouse_type = CLASSIC."
  }
}
```

Implementation notes for this step:

- keep `enable_serverless_compute` required at the module boundary
- keep `tags` as `map(string)` at the public interface
- do not add identity lookup data sources or extra input fields beyond the approved design
- keep duplicate warehouse-name detection in variable validation so invalid names fail before provider planning

- [ ] **Step 2: Format and module-validate the input contract**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses fmt
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses validate
```

Expected: the module validates successfully with the required input contract in place. The full negative-path matrix for duplicate permission tuples and invalid root-caller edits runs later in Chunk 2, Task 6, once the disposable caller-backed harness exists.

- [ ] **Step 3: Prove one variable-contract failure in a disposable scratch root**

Run:

```bash
scratch_dir="$(mktemp -d /tmp/sql-warehouse-variable-contract.XXXXXX)"
cat > "${scratch_dir}/main.tf" <<'EOF'
terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.84"
    }
  }
}

module "under_test" {
  source = "/Users/giulianoaltobelli/workbench/git-projects/databricks-infra/infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses"

  enabled = true

  sql_warehouses = {
    invalid = {
      name                      = "Broken Warehouse"
      cluster_size              = "Tiny"
      max_num_clusters          = 1
      enable_serverless_compute = false
      permissions = [
        {
          principal_type = "group"
          principal_name = "Platform Admins"
        }
      ]
    }
  }
}
EOF
terraform -chdir="${scratch_dir}" init -backend=false
terraform -chdir="${scratch_dir}" validate
rm -rf "${scratch_dir}"
```

Expected: FAIL with the `cluster_size` validation message. This proves the module rejects unsupported warehouse sizes before any provider-backed plan runs.

- [ ] **Step 4: Commit the variable contract after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/variables.tf infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/.terraform.lock.hcl
git commit -m "feat(sql): add sql warehouse module contract"
```

Expected: one commit containing only the public input contract and module initialization metadata if Terraform created a lockfile.

### Task 3: Implement The Warehouse Resources, ACL Translation, And Stable Outputs

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/main.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/outputs.tf`

- [ ] **Step 1: Replace `main.tf` with the SQL warehouse resource graph**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/main.tf` as:

```hcl
locals {
  enabled_sql_warehouses = var.enabled ? var.sql_warehouses : {}

  normalized_permissions = {
    for warehouse_key, warehouse in local.enabled_sql_warehouses : warehouse_key => [
      for grant in warehouse.permissions : {
        principal_type   = grant.principal_type
        principal_name   = grant.principal_name
        permission_level = coalesce(try(grant.permission_level, null), "CAN_USE")
      }
    ]
  }

  flattened_permissions = flatten([
    for warehouse_key, permissions in local.normalized_permissions : [
      for grant in permissions : merge(grant, {
        warehouse_key = warehouse_key
      })
    ]
  ])

  permission_key_list = [
    for grant in local.flattened_permissions :
    "${grant.warehouse_key}:${grant.principal_type}:${grant.principal_name}:${grant.permission_level}"
  ]

  duplicate_permission_keys = toset([
    for key in local.permission_key_list : key
    if length([
      for seen in local.permission_key_list : seen if seen == key
    ]) > 1
  ])
}

resource "databricks_sql_endpoint" "this" {
  for_each = local.enabled_sql_warehouses

  name                      = each.value.name
  cluster_size              = each.value.cluster_size
  min_num_clusters          = try(each.value.min_num_clusters, null)
  max_num_clusters          = each.value.max_num_clusters
  auto_stop_mins            = try(each.value.auto_stop_mins, null)
  spot_instance_policy      = try(each.value.spot_instance_policy, null)
  enable_photon             = try(each.value.enable_photon, null)
  warehouse_type            = try(each.value.warehouse_type, null)
  enable_serverless_compute = each.value.enable_serverless_compute
  no_wait                   = try(each.value.no_wait, null)

  dynamic "channel" {
    for_each = try(each.value.channel, null) == null ? [] : [each.value.channel]

    content {
      name = coalesce(try(channel.value.name, null), "CHANNEL_NAME_CURRENT")
    }
  }

  dynamic "tags" {
    for_each = length(try(each.value.tags, {})) == 0 ? [] : [each.value.tags]

    content {
      dynamic "custom_tags" {
        for_each = tags.value

        content {
          key   = custom_tags.key
          value = custom_tags.value
        }
      }
    }
  }
}

resource "databricks_permissions" "sql_endpoint" {
  for_each = local.enabled_sql_warehouses

  sql_endpoint_id = databricks_sql_endpoint.this[each.key].id

  dynamic "access_control" {
    for_each = local.normalized_permissions[each.key]

    content {
      permission_level       = access_control.value.permission_level
      group_name             = access_control.value.principal_type == "group" ? access_control.value.principal_name : null
      user_name              = access_control.value.principal_type == "user" ? access_control.value.principal_name : null
      service_principal_name = access_control.value.principal_type == "service_principal" ? access_control.value.principal_name : null
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_permission_keys) == 0
      error_message = "Duplicate SQL warehouse permission tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_permission_keys)))}"
    }
  }
}
```

Implementation notes for this step:

- do not add data sources to look up principals, warehouses, or release channels
- keep the principal-type translation isolated to the `databricks_permissions` resource
- keep duplicate permission-tuple detection authoritative and fail clearly instead of silently deduplicating
- keep `tags` expansion as one outer `tags` block containing one `custom_tags` block per caller-supplied map entry

- [ ] **Step 2: Replace `outputs.tf` with stable maps keyed by the caller-defined warehouse keys**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/outputs.tf` as:

```hcl
output "warehouse_ids" {
  description = "Map of warehouse keys to Databricks SQL warehouse IDs."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.id }
}

output "warehouse_names" {
  description = "Map of warehouse keys to Databricks SQL warehouse display names."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.name }
}

output "jdbc_urls" {
  description = "Map of warehouse keys to Databricks SQL warehouse JDBC URLs."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.jdbc_url }
}

output "odbc_params" {
  description = "Map of warehouse keys to Databricks SQL warehouse ODBC connection parameters."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.odbc_params }
}
```

- [ ] **Step 3: Run module formatting and module validation again**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses fmt
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses validate
```

Expected: the module validates successfully with the new resource graph and stable outputs. Duplicate permission tuple failures are exercised later in Chunk 2, Task 6, where the caller-backed plan path is available.

- [ ] **Step 4: Commit the implementation after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/main.tf infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/outputs.tf
git commit -m "feat(sql): add workspace sql warehouse resources"
```

Expected: one commit containing only the module implementation and stable outputs.

## Chunk 2: Root Caller, Operator Docs, And Verification

### Task 4: Add The Checked-In Root Caller And Safe-By-Default Warehouse Catalog

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`

- [ ] **Step 1: Create the checked-in root SQL warehouse catalog**

Write `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf` as:

```hcl
# =============================================================================
# Databricks Workspace SQL Warehouses
# =============================================================================

locals {
  sql_warehouses_enabled = false

  sql_warehouses = {
    analytics_ci = {
      name                      = "Analytics CI Warehouse"
      cluster_size              = "2X-Small"
      max_num_clusters          = 1
      auto_stop_mins            = 10
      enable_serverless_compute = false
      warehouse_type            = "PRO"
      enable_photon             = true
      channel = {
        name = "CHANNEL_NAME_CURRENT"
      }
      tags = {
        Environment = "shared"
        Owner       = "data-platform"
      }
      permissions = concat(
        [
          {
            principal_type   = "group"
            principal_name   = local.identity_groups.platform_admins.display_name
            permission_level = "CAN_MANAGE"
          }
        ],
        local.service_principals_enabled ? [
          {
            principal_type   = "service_principal"
            principal_name   = module.service_principals.application_ids["uat_promotion"]
            permission_level = "CAN_USE"
          }
        ] : []
      )
    }
  }
}

module "sql_warehouses" {
  source = "./modules/databricks_workspace/sql_warehouses"

  providers = {
    databricks = databricks.created_workspace
  }

  enabled        = local.sql_warehouses_enabled
  sql_warehouses = local.sql_warehouses

  depends_on = [
    module.users_groups,
    module.service_principals,
  ]
}
```

Implementation notes for this step:

- keep the checked-in caller disabled by default on `main`
- keep the service-principal ACL entry guarded by `local.service_principals_enabled` so `terraform validate` and the disabled root plan do not fail when service principals remain disabled
- do not add account-level provider aliases or any root outputs in this task
- keep the root warehouse map keyed by stable Terraform identifiers, not display names

- [ ] **Step 2: Format and re-read the new root caller**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt sql_warehouses.tf
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf
```

Expected: the checked-in root caller is readable, disabled by default, and safe even while `service_principals.tf` stays disabled on `main`.

- [ ] **Step 3: Commit the root caller after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf
git commit -m "feat(sql): add root sql warehouse catalog"
```

Expected: one commit containing only the checked-in root caller.

### Task 5: Update The Operator README For The New SQL Warehouse Entry Point

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

- [ ] **Step 1: Add a dedicated SQL warehouses section near the other checked-in root catalogs**

Add a new section to `infra/aws/dbx/databricks/us-west-1/README.md` immediately after the existing `## Service Principal Identity Catalog` section with this content:

```md
## SQL Warehouses

`sql_warehouses.tf` is the root catalog for Terraform-managed Databricks SQL warehouses.

- The checked-in example demonstrates one workspace-scoped warehouse keyed as `analytics_ci`.
- The file is intentionally disabled by default on `main` with `local.sql_warehouses_enabled = false`.
- Stable map keys are Terraform addresses and downstream lookup keys for `module.sql_warehouses` outputs.
- Warehouse ACLs are authoritative because the module manages one `databricks_permissions` resource per warehouse.
- Groups, users, and service principals referenced in `permissions` must resolve in the target workspace by the time Terraform reaches the SQL warehouse resources, whether they already existed or were created earlier in the same graph through explicit dependencies.
- The checked-in service-principal ACL example activates only when `local.service_principals_enabled = true`; replace the example warehouse definition before enabling live compute.
- This layer manages only SQL warehouse creation plus warehouse ACLs.
- Identity creation, entitlements, workspace assignments, Unity Catalog grants, jobs, dashboards, and queries remain outside this file.
```

- [ ] **Step 2: Re-read the surrounding README sections for flow and duplication**

Run:

```bash
sed -n '1,140p' infra/aws/dbx/databricks/us-west-1/README.md
```

Expected: the new SQL warehouse section sits next to the other checked-in root catalogs and does not duplicate the service-principal guidance or claim to manage Unity Catalog access.

- [ ] **Step 3: Commit the README update after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs(sql): document sql warehouse root caller"
```

Expected: one commit containing only the operator-doc change.

### Task 6: Run Root Success-Path And Negative-Path Verification

**Files:**
- Reference: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/variables.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/main.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

- [ ] **Step 1: Run repo formatting and root validation**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 init
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: formatting is clean and the root module validates with the new SQL warehouse entry point wired in.

- [ ] **Step 2: Run the checked-in scenario 1 plan with the root caller still disabled**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- the caller-backed plan succeeds
- the new SQL warehouse module does not propose live compute because `local.sql_warehouses_enabled = false`
- any unrelated drift in other parts of the repo is called out separately and not mistaken for SQL warehouse work

- [ ] **Step 3: Exercise the enabled success path in a disposable scratch copy**

Run:

```bash
scratch_dir="$(mktemp -d /tmp/sql-warehouse-root.XXXXXX)"
rsync -a infra/aws/dbx/databricks/us-west-1/ "${scratch_dir}/"
perl -0pi -e 's/sql_warehouses_enabled = false/sql_warehouses_enabled = true/' "${scratch_dir}/sql_warehouses.tf"
terraform -chdir="${scratch_dir}" init -backend=false
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- the scratch-root plan succeeds against the real caller context
- the plan shows one `databricks_sql_endpoint` for `analytics_ci`
- the plan shows one `databricks_permissions` resource for that warehouse
- the default checked-in group grant remains present
- the service-principal grant remains absent while `local.service_principals_enabled = false`

- [ ] **Step 4: Run the full negative-path matrix in the same scratch copy**

In `${scratch_dir}/sql_warehouses.tf`, test these cases one at a time. Revert the previous invalid edit before testing the next one, and rerun the same scenario 1 `terraform plan` command after each edit:

- Change the first permission entry to `principal_type = "robot"`.
  Expected: FAIL with `principal_type` validation.
- Change the first permission entry to `permission_level = "ADMIN"`.
  Expected: FAIL with `permission_level` validation.
- Replace the warehouse `permissions` list with `permissions = []`.
  Expected: FAIL with the non-empty permissions validation.
- Duplicate the `analytics_ci` object under a new key but keep `name = "Analytics CI Warehouse"` unchanged.
  Expected: FAIL with the duplicate managed warehouse names validation.
- Change `cluster_size = "2X-Small"` to `cluster_size = "Tiny"`.
  Expected: FAIL with the supported `cluster_size` validation.
- Add `spot_instance_policy = "SPOT"` to the warehouse object.
  Expected: FAIL with the supported `spot_instance_policy` validation.
- Change `warehouse_type = "PRO"` to `warehouse_type = "SERVERLESS"`.
  Expected: FAIL with the supported `warehouse_type` validation.
- Change `channel = { name = "CHANNEL_NAME_CURRENT" }` to `channel = { name = "CHANNEL_NAME_BETA" }`.
  Expected: FAIL with the supported `channel.name` validation.
- Change `max_num_clusters = 1` to `max_num_clusters = 1.5`.
  Expected: FAIL with the positive-integer `max_num_clusters` validation.
- Add `min_num_clusters = 1.5`.
  Expected: FAIL with the positive-integer `min_num_clusters` validation.
- Add `min_num_clusters = 2` while keeping `max_num_clusters = 1`.
  Expected: FAIL with the `max_num_clusters >= min_num_clusters` validation.
- Change `enable_serverless_compute = false` to `enable_serverless_compute = true` and `warehouse_type = "CLASSIC"` in the same invalid run.
  Expected: FAIL with the serverless-plus-CLASSIC validation.
- Duplicate the first permission object so the warehouse has the same `principal_type`, `principal_name`, and `permission_level` twice.
  Expected: FAIL with `Duplicate SQL warehouse permission tuples are not allowed`.

- [ ] **Step 5: Clean up the scratch workspace after verification**

Run:

```bash
rm -rf "${scratch_dir}"
```

Expected: the temporary caller-backed verification copy is removed after both the success path and negative-path matrix have been exercised.

- [ ] **Step 6: Capture the verification evidence in the execution log**

Record these facts in the implementation handoff or execution notes:

- `terraform validate` succeeded in the real root
- the checked-in disabled root plan succeeded
- the scratch enabled root plan showed the expected warehouse and ACL resources
- the negative-path cases that were exercised and their failure messages

Expected: the final handoff gives the reviewer enough evidence to confirm the implementation matches the spec without re-deriving what was tested.
