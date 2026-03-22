# Unity Catalog Catalog Creation Module

This module's approved target interface is a generic single-catalog contract for creating one AWS-backed, workspace-isolated Unity Catalog catalog. It is the reusable unit behind the governed catalog rollout.

## Usage

```hcl
module "revenue_catalog" {
  source = "./modules/databricks_workspace/unity_catalog_catalog_creation"

  providers = {
    databricks = databricks.created_workspace
  }

  aws_account_id        = var.aws_account_id
  aws_iam_partition     = local.computed_aws_partition
  aws_assume_partition  = local.assume_role_partition
  unity_catalog_iam_arn = local.unity_catalog_iam_arn
  cmk_admin_arn         = var.cmk_admin_arn
  resource_prefix       = var.resource_prefix
  workspace_id          = local.workspace_id

  catalog_name            = "prod_salesforce_revenue"
  catalog_admin_principal = "Platform Admins"
  catalog_reader_principals = ["Revenue Readers"]
  workspace_ids           = ["1234567890123456"]
  set_default_namespace   = false
}
```

## Provider And Naming Contract

- The Databricks provider must be wired explicitly to `databricks.created_workspace`.
- The module is workspace-scoped only and must not use `databricks.mws`.
- AWS-safe names derive from `replace(catalog_name, "_", "-")`.
- The AWS-safe suffix feeds bucket, IAM, KMS alias, storage credential, and external location names. The governed rollout uses that suffix in patterns such as `${resource_prefix}-${replace(catalog_name, "_", "-")}-${workspace_id}`.
- `set_default_namespace` defaults to `false`. The module should not change the workspace default namespace unless the caller opts in.

## Workspace Visibility

- The catalog, storage credential, and external location are created in isolated mode.
- The creating `workspace_id` relies on Databricks' implicit isolated binding and is not managed through explicit binding resources.
- `workspace_ids` adds extra isolated bindings for other workspaces on the same metastore.
- This interface does not expose open/shared visibility in the governed catalog rollout.

## Grant Ownership

- Catalog grants are authoritative through `databricks_grants`.
- `catalog_admin_principal` receives `ALL_PRIVILEGES`.
- Each principal in `catalog_reader_principals` receives `USE_CATALOG`.
- `set_default_namespace` only changes the workspace default namespace; it does not change grant ownership.

## Outputs

The module exposes scalar outputs that the root governed-catalog `catalogs` map aggregates per stable catalog key:

- `catalog_name`
- `catalog_bucket_name`
- `storage_credential_name`
- `storage_credential_external_id`
- `storage_credential_unity_catalog_iam_arn`
- `external_location_name`
- `iam_role_arn`
- `kms_key_arn`

When `enabled = false`, the module creates no resources and every scalar output resolves to `null`.
