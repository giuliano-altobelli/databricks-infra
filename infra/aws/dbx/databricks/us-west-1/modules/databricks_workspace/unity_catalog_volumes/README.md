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

When `grants` are declared for a managed volume, the module uses `databricks_grants`, which is authoritative for that volume. Out-of-band grants are not preserved.

## Destroy Safety

- `force_destroy` is optional per volume and defaults to `false`.
- Non-empty volume deletion is intentionally conservative unless the caller opts in with `force_destroy = true`.

## Outputs

The `volumes` output map returns `storage_location = null` for `MANAGED` volumes.
