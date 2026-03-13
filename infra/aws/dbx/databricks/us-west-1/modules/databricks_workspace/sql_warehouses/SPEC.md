# Module Spec

## Summary

- **Module name**: `databricks_workspace/sql_warehouses`
- **One-liner**: Manage workspace-scoped Databricks SQL warehouses and their authoritative Terraform-owned warehouse ACLs.

## Scope

- In scope:
  - workspace-level only
  - one `databricks_sql_endpoint` per caller-defined warehouse key
  - one authoritative `databricks_permissions` resource per managed warehouse using `sql_endpoint_id`
  - creation of new Databricks SQL warehouses from a caller-owned map
  - authoritative warehouse ACL management for groups, users, and service principals
  - stable output maps for warehouse IDs, names, JDBC URLs, and ODBC parameters
- Out of scope:
  - adopting existing warehouses
  - discovering or creating identities
  - account-level resources, entitlements, or workspace assignments
  - Unity Catalog grants
  - jobs, dashboards, queries, or multi-workspace fan-out

## Interfaces

- Required inputs:
  - `sql_warehouses`
  - `sql_warehouses[*].name`
  - `sql_warehouses[*].cluster_size`
  - `sql_warehouses[*].max_num_clusters`
  - `sql_warehouses[*].enable_serverless_compute`
  - `sql_warehouses[*].permissions[*].principal_type`
  - `sql_warehouses[*].permissions[*].principal_name`
  - `sql_warehouses[*].permissions[*].permission_level`
- Optional inputs:
  - `enabled`
  - `sql_warehouses[*].min_num_clusters`
  - `sql_warehouses[*].auto_stop_mins`
  - `sql_warehouses[*].spot_instance_policy`
  - `sql_warehouses[*].enable_photon`
  - `sql_warehouses[*].warehouse_type`
  - `sql_warehouses[*].no_wait`
  - `sql_warehouses[*].channel`
  - `sql_warehouses[*].tags`
- Outputs:
  - `warehouse_ids`
  - `warehouse_names`
  - `jdbc_urls`
  - `odbc_params`

## Provider Context

- Provider(s):
  - `databricks` only, wired by the caller to `databricks.created_workspace`
- Authentication mode:
  - workspace-scoped Databricks authentication, validated in this repo with `DATABRICKS_AUTH_TYPE=oauth-m2m`
- Account-level vs workspace-level:
  - workspace-level only

## Behavior / Data Flow

- `sql_warehouses` is the single required caller-owned map input.
- When `enabled = false`, the module creates no resources and all outputs resolve to empty maps.
- When `enabled = true`, the module:
  1. iterates over stable caller-defined warehouse keys
  2. creates one `databricks_sql_endpoint` per key
  3. normalizes and validates the caller-supplied permission tuples
  4. creates one authoritative `databricks_permissions` resource per warehouse using `sql_endpoint_id`
  5. translates generic ACL entries into provider-specific warehouse access-control fields
  6. expands optional `channel` and `tags` inputs into provider block shapes
  7. publishes stable maps keyed by the same caller-owned warehouse keys
- groups, users, and service principals are referenced by Databricks-native identifiers only.

## Constraints and Failure Modes

- Stable map keys are the Terraform addresses and downstream lookup keys for managed warehouses.
- The module does not discover or create identities.
- The module does not adopt existing warehouses.
- The module does not manage account-level resources, entitlements, workspace assignments, or Unity Catalog grants.
- Insufficient workspace-level privileges to create SQL warehouses causes provider plan or apply failure.
- Insufficient workspace-level privileges to manage warehouse ACLs causes provider plan or apply failure.
- Principal identifiers that do not exist in the target workspace cause provider plan or apply failure.
- Workspace capability mismatches for serverless or other compute settings can cause provider plan or apply failure.

## Validation

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
- `enabled = false` returns empty output maps
- identity creation, entitlements, workspace assignments, and Unity Catalog grants remain outside this module
