Date: 2026-03-13

# SQL Warehouses Design

## Summary

Add a new workspace-scoped Databricks module at `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses` plus a root caller at `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`.

One module instance manages a caller-owned `map` of new Databricks SQL warehouses keyed by stable Terraform identifiers. Each entry owns both:

- creation of one Databricks SQL warehouse through `databricks_sql_endpoint`
- authoritative warehouse ACLs through one `databricks_permissions` resource targeting `sql_endpoint_id`

The module is workspace-level only. It creates only new SQL warehouses and does not adopt existing warehouses.

## Scope

In scope:

- New module: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses`
- New root caller: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`
- Managing multiple new SQL warehouses from one module invocation
- Managing warehouse ACLs for groups, users, and service principals on those warehouses
- Broad exposure of most supported `databricks_sql_endpoint` settings through the module interface
- Fast-fail validation for invalid warehouse settings, invalid ACL entries, empty ACLs, duplicate ACL tuples, and duplicate managed warehouse names
- Stable outputs for warehouse IDs, names, JDBC URLs, and ODBC parameters

Out of scope:

- Adopting or importing pre-existing SQL warehouses
- Account-level Databricks resources
- Creating groups, users, or service principals
- Workspace assignments or entitlements
- Unity Catalog grants
- Cluster policies, jobs, dashboards, or queries
- Multi-workspace fan-out from one module invocation

## Context

This repo already follows a stable pattern for Databricks modules:

- root callers define a catalog map keyed by stable Terraform identifiers
- child modules manage the actual Databricks resources from those caller-owned definitions
- workspace ACLs are managed authoritatively with `databricks_permissions`
- modules do not discover identities internally; callers resolve principal identifiers before the module boundary

The closest existing analog is `modules/databricks_workspace/cluster_policy`, which already:

- accepts a map of managed workspace resources
- takes generic ACL entries with `principal_type`, `principal_name`, and `permission_level`
- translates those entries into provider-specific `access_control` fields
- treats permissions as Terraform-owned and authoritative per managed resource

This SQL warehouse design follows the same contract shape to stay consistent with the repo.

The current architecture also already expects dedicated SQL-only service principals and dedicated SQL warehouses for automation workflows. This design creates the reusable module boundary for that pattern without coupling warehouse creation to identity or Unity Catalog modules.

## Recommended Architecture

Use one public workspace module that manages both SQL warehouse creation and warehouse ACLs.

This is the recommended approach because it keeps each warehouse definition and its ACL in one contract, matches the repo's existing `cluster_policy` pattern, and avoids split catalogs that callers would need to keep synchronized manually.

### Module placement

Create the module under:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses`

This placement is correct because SQL warehouses and warehouse permissions are workspace-scoped resources and should use only a workspace-scoped Databricks provider.

### Root caller

Create the checked-in root caller at:

- `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`

That file becomes the root catalog for Terraform-managed SQL warehouses in the same style as:

- `cluster_policy_config.tf` for workspace cluster policies
- `service_principals.tf` for Terraform-managed service principals

The checked-in root caller should be disabled by default on `main` using an explicit local enable flag so placeholder warehouse definitions do not create live compute before operators are ready.

### Provider model

The module should require only:

- `databricks`

The root caller wires that provider to:

- `databricks.created_workspace`

This module must not use account-level providers or aliases.

## Module Interface

### Inputs

Required inputs:

- `sql_warehouses` as `map(object(...))`

Optional inputs:

- `enabled` as `bool`, default `true`

Each warehouse object should expose a broad but validated interface over `databricks_sql_endpoint`:

- `name` (`string`, required)
- `cluster_size` (`string`, required)
- `max_num_clusters` (`number`, required)
- `enable_serverless_compute` (`bool`, required)
- `permissions` (`list(object)`, required)
- `min_num_clusters` (`optional(number)`)
- `auto_stop_mins` (`optional(number)`)
- `spot_instance_policy` (`optional(string)`)
- `enable_photon` (`optional(bool)`)
- `warehouse_type` (`optional(string)`)
- `no_wait` (`optional(bool)`)
- `channel` (`optional(object({ name = optional(string, "CHANNEL_NAME_CURRENT") }))`)
- `tags` (`optional(map(string))`)

Each `permissions` entry should be:

- `principal_type` (`string`): one of `group`, `user`, or `service_principal`
- `principal_name` (`string`): exact Databricks identifier for that principal type
- `permission_level` (`optional(string, "CAN_USE")`)

`principal_name` semantics are Databricks-native rather than Terraform-key based:

- group: workspace group display name
- user: Databricks `user_name`, typically an email
- service principal: Databricks application ID

The two ergonomic normalizations are intentional:

- `channel` is modeled as a small object instead of forcing callers to mirror a nested provider block
- `tags` is modeled as `map(string)` and expanded by the module into `tags { custom_tags { ... } }`

### Outputs

Expose stable maps keyed by the caller-defined warehouse key:

- `warehouse_ids`
- `warehouse_names`
- `jdbc_urls`
- `odbc_params`

When `enabled = false`, all outputs resolve to empty maps.

## Root Configuration Shape

The root caller should define a stable local map keyed by Terraform-owned warehouse identifiers and then pass that map into the module.

Recommended shape:

```hcl
locals {
  sql_warehouses_enabled = false

  sql_warehouses = {
    analytics_ci = {
      name                     = "Analytics CI Warehouse"
      cluster_size             = "2X-Small"
      max_num_clusters         = 1
      auto_stop_mins           = 10
      enable_serverless_compute = false
      warehouse_type           = "PRO"
      enable_photon            = true
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
          principal_name   = local.identity_groups.platform_admins.display_name
          permission_level = "CAN_MANAGE"
        },
        {
          principal_type   = "service_principal"
          principal_name   = module.service_principals.application_ids["uat_promotion"]
          permission_level = "CAN_USE"
        }
      ]
    }
  }
}
```

Stable identity rules:

- the map key is the Terraform identity for the managed warehouse
- renaming a key changes Terraform addresses even if the warehouse display name stays the same
- downstream consumers should read outputs using these same stable keys

## Behavior And Data Flow

When `enabled = false`:

- all internal collections collapse to empty maps
- no warehouses or ACLs are created
- all outputs are empty maps

When `enabled = true`:

1. Iterate over the caller-owned `sql_warehouses` map
2. Create one `databricks_sql_endpoint` resource per warehouse key
3. Normalize the permission tuples for duplicate detection
4. Create one authoritative `databricks_permissions` resource per warehouse using `sql_endpoint_id`
5. Translate generic principal types into provider-specific `access_control` fields:
   - `group` -> `group_name`
   - `user` -> `user_name`
   - `service_principal` -> `service_principal_name`
6. Expand `tags` into provider `custom_tags`
7. Publish stable output maps keyed by the original caller-defined warehouse keys

Warehouse ACL behavior is authoritative. If a principal should retain access to a managed warehouse, that principal must remain present in the warehouse's `permissions` list. Out-of-band grants on Terraform-managed warehouses are not preserved.

## Constraints And Failure Modes

Stable caller-defined map keys drive Terraform addresses and output keys.

Warehouse names must be unique across the managed map. Duplicate names should fail during validation rather than producing ambiguous provider behavior.

Every managed warehouse must declare at least one permission entry. Empty `permissions` lists are invalid.

Supported principal types are exactly:

- `group`
- `user`
- `service_principal`

Supported warehouse permission levels should be constrained to the SQL warehouse ACL set supported by `databricks_permissions` for `sql_endpoint_id`:

- `CAN_USE`
- `CAN_MONITOR`
- `CAN_MANAGE`
- `CAN_VIEW`
- `IS_OWNER`

Duplicate tuples of `warehouse_key`, `principal_type`, `principal_name`, and `permission_level` are invalid and must fail clearly rather than being silently deduplicated.

The module should validate the allowed enum values for:

- `cluster_size`
- `spot_instance_policy`
- `warehouse_type`
- `channel.name`

`min_num_clusters` and `max_num_clusters` must be positive integers when set, and `max_num_clusters` must be greater than or equal to `min_num_clusters`.

`enable_serverless_compute` must be required at the module boundary. The provider documentation notes that the default may vary by workspace history, so an implicit default would make the repo drift-prone.

`enable_serverless_compute = true` must not be combined with `warehouse_type = "CLASSIC"`.

Runtime failures may still occur when:

- the workspace principal running Terraform lacks permission to create SQL warehouses
- the workspace principal running Terraform lacks permission to manage warehouse ACLs
- the caller references a group, user, or service principal that does not yet exist in the target workspace
- warehouse creation fails due to Databricks workspace capabilities or unsupported compute settings

## Dependency Model

The module does not discover or create identities. The root caller is responsible for resolving principal identifiers before passing ACLs into the module.

Root dependencies should therefore remain explicit:

- depend on `module.users_groups` when warehouse ACLs reference workspace groups or users managed through that path
- depend on `module.service_principals` when warehouse ACLs reference Terraform-managed service principals

The root caller should extend those dependencies rather than replacing them if additional prerequisites are introduced later.

## Validation

Module and root verification should include:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- a caller-backed validation path for the module because provider-backed workspace resources validate more reliably with a real caller context than in total isolation
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`

Negative-path verification should cover at least:

- unsupported `principal_type`
- unsupported warehouse permission levels
- empty `permissions`
- duplicate permission tuples
- duplicate warehouse names
- invalid enum values for warehouse settings
- invalid `min_num_clusters` and `max_num_clusters`
- `enable_serverless_compute = true` with `warehouse_type = "CLASSIC"`

## Non-Goals

This design intentionally does not:

- model pre-existing warehouses
- bundle identity creation into the warehouse module
- infer principal names from Terraform keys inside the module
- manage Unity Catalog access as part of warehouse creation
- add warehouse-specific opinions beyond the minimal validation and normalization needed for safe broad configurability
