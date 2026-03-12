# Unity Catalog Storage Locations Module

This module manages workspace-scoped Databricks Unity Catalog S3 storage credentials and external locations, plus optional authoritative grants and explicit workspace bindings.

It is intentionally Databricks-only. The caller supplies pre-existing AWS IAM role ARNs and S3 URLs, while the module exposes Databricks-generated trust outputs such as `external_id` and `unity_catalog_iam_arn` so AWS IAM trust can be patched in a separate stack when needed.

## Usage

```hcl
module "unity_catalog_storage_locations" {
  source = "./modules/databricks_workspace/unity_catalog_storage_locations"

  providers = {
    databricks = databricks.created_workspace
  }

  current_workspace_id = local.workspace_id

  storage_credentials = {
    bronze_raw = {
      name            = "bronze-raw-storage-credential"
      role_arn        = "arn:aws:iam::123456789012:role/databricks-bronze-raw"
      skip_validation = true
      grants = [
        {
          principal  = "Data Engineers"
          privileges = ["CREATE_EXTERNAL_LOCATION"]
        }
      ]
    }
  }

  external_locations = {
    bronze_raw_root = {
      name           = "bronze-raw-root"
      url            = "s3://company-bronze-raw/"
      credential_key = "bronze_raw"
      grants = [
        {
          principal  = "Data Engineers"
          privileges = ["CREATE_EXTERNAL_TABLE"]
        }
      ]
    }
  }
}
```

## Workspace Visibility

- `workspace_access_mode = "ISOLATION_MODE_ISOLATED"` is the default for both storage credentials and external locations.
- In isolated mode, the module always includes `current_workspace_id` and can add more workspace bindings through `workspace_ids`.
- `workspace_access_mode = "ISOLATION_MODE_OPEN"` leaves the securable open to all workspaces on the metastore and forbids `workspace_ids`.

## Grant Ownership

When `grants` are declared for a managed storage credential or external location, the module uses `databricks_grants`, which is authoritative for that securable.

Do not expect out-of-band grants on those managed securables to be preserved. If a principal should retain access, it must appear in the caller's `grants`.

Privilege guidance for the example configurations:

- On storage credentials, grant `CREATE_EXTERNAL_LOCATION`.
- On external locations, grant `CREATE_EXTERNAL_TABLE`, `CREATE_EXTERNAL_VOLUME`, or `CREATE_MANAGED_STORAGE` depending on the intended use.
- Add `READ_FILES` or `WRITE_FILES` only when direct path-based file access is intentional.

## AWS Bootstrap Note

If the AWS IAM trust policy has not yet been patched with the Databricks-generated `external_id`, first create the storage credential with `skip_validation = true`.

After the credential exists, use the module output `storage_credentials[*].external_id` and `storage_credentials[*].unity_catalog_iam_arn` to update IAM trust externally, then switch `skip_validation` back to `false` before relying on the credential for external locations.
