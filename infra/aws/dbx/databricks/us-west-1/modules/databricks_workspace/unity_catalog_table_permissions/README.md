# Unity Catalog Table Permissions Module

This module manages authoritative `SELECT` grants for existing Databricks Unity Catalog managed tables. It creates one `databricks_grants` resource per stable caller-defined table key and one grant block per reader principal.

## Usage

```hcl
module "unity_catalog_table_permissions" {
  source = "./modules/databricks_workspace/unity_catalog_table_permissions"

  providers = {
    databricks = databricks.created_workspace
  }

  tables = {
    "finance_raw:transactions" = {
      catalog_name      = "finance"
      schema_name       = "raw"
      table_name        = "transactions"
      reader_principals = ["Finance Readers"]
    }
  }
}
```

## Provider And Scope Contract

- The Databricks provider must be wired explicitly to `databricks.created_workspace`.
- The module is workspace-scoped only and must not use `databricks.mws`.
- Tables, schemas, and catalogs stay outside this module.
- The module does not grant `USE_CATALOG` or `USE_SCHEMA`; callers must manage prerequisite namespace access through the existing catalog and schema grant modules.

## Grant Ownership

This module uses `databricks_grants`, which is authoritative for each listed table. Adopting an existing table into this module can remove out-of-band table grants that are not represented in `reader_principals`. Operators should inspect current table grants and include every intended reader principal before adding a real table entry.

## Reader Principals

`reader_principals` are resolved Databricks principal names. They may represent groups, users, or service principals. Every principal receives exactly `SELECT`; ownership, write, manage, and admin privileges are out of scope.

## Outputs

The `tables` output map is keyed by the same stable caller-defined identifiers passed into `tables`. Each value includes `catalog_name`, `schema_name`, `table_name`, and `full_name`.

When `enabled = false`, the module creates no resources and returns an empty `tables` map.
