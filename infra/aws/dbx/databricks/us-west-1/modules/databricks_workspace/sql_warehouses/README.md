# Workspace SQL Warehouses Module

This module manages workspace-scoped Databricks SQL warehouses and the full Terraform-owned ACL for each warehouse it creates.

The caller owns the warehouse catalog. In this repo that catalog lives in `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`, which passes a stable-keyed `sql_warehouses` map into this module using the workspace-scoped `databricks.created_workspace` provider alias.

## Usage

```hcl
module "sql_warehouses" {
  source = "./modules/databricks_workspace/sql_warehouses"

  providers = {
    databricks = databricks.created_workspace
  }

  sql_warehouses = {
    analytics_ci = {
      name                      = "Analytics CI Warehouse"
      cluster_size              = "2X-Small"
      max_num_clusters          = 1
      auto_stop_mins            = 10
      enable_serverless_compute = false
      warehouse_type            = "PRO"
      enable_photon             = true
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
          principal_name   = "Platform Admins"
          permission_level = "CAN_MANAGE"
        },
        {
          principal_type   = "service_principal"
          principal_name   = "00000000-0000-0000-0000-000000000000"
          permission_level = "CAN_USE"
        }
      ]
    }
  }
}
```

## Stable Keys

- Stable map keys such as `analytics_ci` are Terraform addresses for the managed warehouses.
- Those same keys are the downstream lookup keys for `warehouse_ids`, `warehouse_names`, `jdbc_urls`, and `odbc_params`.
- Renaming a key changes Terraform addresses even if the Databricks display name stays the same.

## Provider Wiring

- This module requires only the workspace-scoped Databricks provider.
- The caller must wire `databricks` to `databricks.created_workspace`.
- This module does not use account-level provider aliases.

## Principal Identifiers

- `principal_name` for groups is the Databricks workspace display name.
- `principal_name` for users is the Databricks `user_name`, typically an email.
- `principal_name` for service principals is the Databricks application ID.
- This module does not create or discover principals; referenced identities must already resolve in the target workspace.

## ACL Ownership

This module manages the complete Terraform-owned ACL for each warehouse it creates by materializing one `databricks_permissions` resource per warehouse.

Do not expect out-of-band grants on those managed warehouses to be preserved. If a principal should keep access, it must remain present in that warehouse's `permissions` list.
