# Module Spec

## Summary

- **Module name**: `databricks_workspace/unity_catalog_table_permissions`
- **One-liner**: Manage authoritative `SELECT` grants for existing Unity Catalog managed tables.

## Scope

- In scope:
  - one authoritative `databricks_grants` resource per listed table
  - one grant block per resolved reader principal
  - hard-coded table `SELECT` privileges only
  - existing Unity Catalog managed tables only
  - workspace-level Databricks provider only
  - stable output map keyed by caller-defined identifiers
- Out of scope:
  - no table, view, schema, or catalog creation
  - no view grants
  - no `USE_CATALOG` or `USE_SCHEMA` prerequisite grants
  - no ownership, write, manage, admin, or privilege override support
  - no account-level resources or `databricks.mws`
  - no table data-source lookups

## Interfaces

- Optional inputs:
  - `enabled` (`bool`, default `true`)
- Required inputs:
  - `tables` (`map(object)`): existing Unity Catalog managed tables keyed by stable caller-defined identifiers
  - `tables[*].catalog_name` (`string`)
  - `tables[*].schema_name` (`string`)
  - `tables[*].table_name` (`string`)
  - `tables[*].reader_principals` (`list(string)`)
- Outputs:
  - `tables`: map keyed by the stable caller key. Each value includes:
    - `catalog_name`
    - `schema_name`
    - `table_name`
    - `full_name`
- Output contract when `enabled = false`:
  - the module creates no resources
  - the `tables` output returns `{}`

## Provider Context

- Provider(s):
  - `databricks` only, wired by the caller to `databricks.created_workspace`
- Authentication mode:
  - workspace-scoped Databricks authentication supplied by the root module; repo verification uses `DATABRICKS_AUTH_TYPE=oauth-m2m`
- Account-level vs workspace-level:
  - workspace-level only

## Behavior / Data Flow

- The caller provides a stable-keyed `tables` map.
- Each table entry contains the resolved Unity Catalog object identity and resolved principal names. Root-specific catalog keys and group keys stay outside this reusable module.
- The module builds a fully qualified table name as `catalog_name.schema_name.table_name`.
- The module creates one `databricks_grants` resource per listed table using the `table` argument.
- Each reader principal receives exactly `["SELECT"]`.
- `reader_principals` may contain Databricks groups, users, or service principals.
- Casing supplied by the caller is preserved in provider arguments and outputs. Lowercased, trimmed identities are used only for validation and duplicate detection.

## Constraints and Failure Modes

- Tables must already exist before apply. Missing tables are Databricks provider/runtime failures from `databricks_grants`.
- Grants are authoritative for each listed table. Adopting an existing table into this module can remove out-of-band table grants that are not represented in `reader_principals`.
- Stable caller keys are Terraform identities for managed grant resources. Renaming a key changes the Terraform address even if the table name stays the same.
- Catalog and schema namespace grants are prerequisites managed by existing catalog/schema grant paths.

## Validation

- Module-level validation must reject:
  - blank `catalog_name`
  - blank `schema_name`
  - blank `table_name`
  - empty `reader_principals`
  - blank reader principals after trimming
  - duplicate reader principals per table after trimming and lowercasing
  - duplicate fully qualified table identities across stable keys after trimming and lowercasing
- Verification commands:
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_table_permissions init -backend=false`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_table_permissions validate`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_table_permissions test`
  - `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
  - root verification from `infra/aws/dbx/databricks/us-west-1`:
    - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
    - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars`
