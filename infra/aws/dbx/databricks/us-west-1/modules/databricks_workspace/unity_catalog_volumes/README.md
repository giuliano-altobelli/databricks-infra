# Unity Catalog Volumes Module

This module manages workspace-scoped Databricks Unity Catalog volumes. It supports both `MANAGED` and `EXTERNAL` volumes from one `volumes` map and can manage authoritative volume grants when `grants` are declared.

## Usage

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

## Ordering Contract

- The module does not create catalogs, schemas, storage credentials, or external locations.
- For same-stack catalog or schema creation, prefer passing names from upstream resources or module outputs instead of duplicating string literals.
- If Terraform cannot infer the prerequisite edge for same-stack Unity Catalog objects, add explicit `depends_on` to the root module call.

## External Volumes

- `EXTERNAL` volumes require `storage_location`.
- The `storage_location` must point under a pre-existing external location that is already authorized for the target workspace.
- If the same root stack also creates the external location or its grants, the caller must enforce readiness through references and, when needed, explicit `depends_on`.

## Grant Ownership

When `grants` are declared for a module-managed volume, the module uses `databricks_grants`, which is authoritative for that volume. Out-of-band grants are not preserved for either `MANAGED` or `EXTERNAL` volumes.

If an automation identity relies on `MANAGE` or any other volume privilege, keep that identity present in the authoritative `grants` set or Terraform will remove its access on the next apply.

## Destroy Safety

- The Databricks provider does not expose a force-delete argument for volumes.
- Non-empty volume deletion is intentionally conservative and cannot be overridden by this module.

## Outputs

The `volumes` output map returns `storage_location = null` for `MANAGED` volumes.

## Operator Notes

- Stable map keys are Terraform addresses. Renaming a key changes the resource address even if the Databricks volume name stays the same.
- `EXTERNAL` volumes require the external location path and authorization to exist before this module runs.
- Prefer upstream resource or module outputs for same-stack catalog and schema names when they are available.
