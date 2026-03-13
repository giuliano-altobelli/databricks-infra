# Unity Catalog Schemas Module

This module manages workspace-scoped Databricks Unity Catalog schemas. It creates one schema per stable caller-defined key, can pass through optional schema `properties`, and can manage authoritative schema grants when `grants` are declared.

## Usage

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
      properties = {
        classification = "restricted"
      }
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

## Provider And Scope Contract

- The Databricks provider must be wired explicitly to `databricks.created_workspace`.
- The module is workspace-scoped only and must not use `databricks.mws`.
- Catalogs and volumes stay outside this module.

## Grant Ownership

When `grants` are declared for a module-managed schema, the module uses `databricks_grants`, which is authoritative for that schema. Out-of-band schema grants are not preserved.

## Schema Properties

When `properties` are declared, the module passes them directly to `databricks_schema`. Property keys must be non-empty.

## Outputs

The `schemas` output map is keyed by the same stable caller-defined identifiers passed into `schemas`. Each value includes `catalog_name`, `schema_name`, and `full_name`.

When `enabled = false`, the module creates no resources and returns an empty `schemas` map.

## Operator Notes

- Stable map keys are Terraform addresses. Renaming a key changes the resource address even if the Databricks schema name stays the same.
- Prefer passing catalog names from upstream module outputs when the catalog is created in the same root stack.
- The `schemas` output behavior is part of the module contract even though it is implemented through the resource graph in `outputs.tf`.
