# Workspace Cluster Policy Module

This module manages workspace-scoped Databricks cluster policies and the full Terraform-owned `CAN_USE` ACL for each policy it creates.

The caller owns the policy catalog. In this repo that catalog lives in `infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf`, which passes a `cluster_policies` map into this module using the workspace-scoped `databricks.created_workspace` provider alias.

## Usage

```hcl
module "cluster_policy" {
  source = "./modules/databricks_workspace/cluster_policy"

  providers = {
    databricks = databricks.created_workspace
  }

  cluster_policies = {
    bundle_dlt_job = {
      name        = "Bundle DLT Job Policy"
      description = "Used by Databricks Asset Bundles for DLT job clusters."
      definition  = jsonencode({})
      permissions = [
        {
          principal_type   = "group"
          principal_name   = "Platform Admins"
          permission_level = "CAN_USE"
        }
      ]
    }
  }

  depends_on = [module.users_groups]
}
```

## Principal Identifiers

- `principal_name = "Platform Admins"` uses the Databricks group display name, not the Terraform map key such as `platform_admins`.
- `principal_name` for `user` grants must match the Databricks `user_name`, usually the login email.
- `principal_name` for `service_principal` grants must be the Databricks application ID.

## ACL Ownership

This module manages the complete Terraform-owned ACL for each policy it creates by materializing one `databricks_permissions` resource per policy.

Do not expect out-of-band grants on those managed policies to be preserved. If a principal should keep `CAN_USE`, it must appear in the caller's `permissions` list for that policy.
