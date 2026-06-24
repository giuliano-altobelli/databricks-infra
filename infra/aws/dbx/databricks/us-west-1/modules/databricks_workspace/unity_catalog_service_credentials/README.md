# Unity Catalog Service Credentials

This module manages AWS-backed Unity Catalog service credentials.

It creates `databricks_credential` resources with `purpose = "SERVICE"`, optional authoritative `databricks_grants`, and optional `databricks_workspace_binding` resources for workspace-restricted credentials.

## Provider

Callers must wire a workspace-scoped Databricks provider:

```hcl
providers = {
  databricks = databricks.created_workspace
}
```

The module does not use `databricks.mws`.

## Example

```hcl
module "unity_catalog_service_credentials" {
  source = "./modules/databricks_workspace/unity_catalog_service_credentials"

  providers = {
    databricks = databricks.created_workspace
  }

  current_workspace_id = local.workspace_id

  service_credentials = {
    bedrock_runtime = {
      name = "sandbox-bedrock-runtime-service-credential"
      aws = {
        role_arn = "arn:aws:iam::123456789012:role/databricks-sandbox-bedrock-runtime"
      }
      skip_validation = true
      grants = [
        {
          principal = "Data Engineers"
        }
      ]
    }
  }
}
```

## AWS IAM Boundary

This module does not create or update AWS IAM roles, policies, trust policies, Bedrock permissions, or external-service permissions.

When Databricks emits `external_id` and `unity_catalog_iam_arn`, an external AWS workflow must use those values to complete IAM trust if the role is not already trusted. Use `skip_validation = true` during bootstrap when IAM trust is not ready, then re-enable validation after the AWS side is patched.

## Grants

Grant entries are authoritative for each managed service credential. Out-of-band grants on managed credentials are not preserved.

Phase 1 allows only the `ACCESS` privilege. The child module accepts Databricks-native principal identifiers; root config should resolve repo-local group or service-principal keys before calling this module.

## Workspace Access

`workspace_access_mode` defaults to `ISOLATION_MODE_ISOLATED`. In isolated mode, the module creates bindings for `current_workspace_id` plus any extra `workspace_ids`.

Use `ISOLATION_MODE_OPEN` only when every workspace attached to the metastore may see the credential. Open mode does not allow explicit `workspace_ids`.
