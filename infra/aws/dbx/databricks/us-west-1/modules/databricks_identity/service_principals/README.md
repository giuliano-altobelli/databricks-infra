# Databricks Service Principals Module

This module manages Terraform-owned Databricks service principals keyed by stable caller-defined identifiers.

## Example

```hcl
module "service_principals" {
  source = "./modules/databricks_identity/service_principals"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  workspace_id = local.workspace_id

  service_principals = {
    uat_promotion = {
      display_name    = "UAT Promotion SP"
      principal_scope = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
      entitlements = {
        databricks_sql_access = true
      }
    }

    workspace_agent = {
      display_name    = "Workspace Agent SP"
      principal_scope = "workspace"
      entitlements = {
        workspace_access = true
      }
    }
  }
}
```

## Usage Notes

- Stable map keys are both Terraform addresses and downstream lookup keys. Renaming a key changes the Terraform instance address even if `display_name` stays the same.
- `databricks.mws` is required for account-scoped service principal creation and workspace assignment.
- `databricks.workspace` is required for workspace-scoped service principal creation and all workspace entitlements.
- Account-scoped entitlements require `workspace_assignment.enabled = true`.
- `workspace_assignment.permissions` must be non-empty when workspace assignment is enabled.
- Workspace-scoped principals must not request workspace assignment.
- Entitlements are authoritative when the `entitlements` object exists, and omitted entitlement fields are treated as effective `false`.
- The Databricks provider currently conflicts when `workspace_consume = false` is sent alongside other entitlement fields, so the module sends `workspace_consume` only when it is `true`; clearing a prior `workspace_consume` grant therefore depends on provider handling of omitted values.
- `enabled = false` returns empty maps for every output.

## Out Of Scope

- Credentials and service principal secrets
- Unity Catalog grants
- Warehouse ACLs and other warehouse permissions
- Group membership
- Account roles
