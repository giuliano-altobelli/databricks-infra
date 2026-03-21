Date: 2026-03-18

# Sandbox Workspace Design

## Summary

Define a temporary `sandbox`-branch deployment pattern in `infra/aws/dbx/databricks/us-west-1` that creates and destroys a second Databricks workspace from the existing root stack while sharing only:

- the Databricks account
- the existing Unity Catalog metastore
- the existing Okta SCIM-provisioned users

The `sandbox` branch owns its own Terraform var file, its own Terraform state, and sandbox-prefixed copies of Terraform-managed Databricks objects wherever those objects can be duplicated safely.

## Scope

In scope:

- a dedicated sandbox Terraform var file for create-workspace flows
- a dedicated sandbox Terraform state workflow
- root-level sandbox naming changes for currently managed Databricks objects that would otherwise collide with or appear shared with `main`
- use of the existing `workspace_source = "create"` path to build a separate sandbox workspace on the same Databricks account
- use of the existing metastore-assignment path to bind the shared metastore to the sandbox workspace
- full create, update, and destroy lifecycle for the sandbox workspace and sandbox-owned resources
- strict plan review rules that reject any sandbox run which mutates `main`-managed resources

Out of scope:

- a new environment abstraction or naming-derivation framework
- significant module rewrites
- duplicating SCIM users
- creating sandbox account-wide roles
- creating a separate Databricks account or a separate metastore
- sharing Databricks objects with `main` beyond the account, metastore, and SCIM users

## Context

This repo currently uses one Databricks root stack at `infra/aws/dbx/databricks/us-west-1` with a clean provider split:

- `databricks.mws` for account-level resources
- `databricks.created_workspace` for workspace-level resources

The root already supports two workspace entry modes:

- `workspace_source = "existing"`
- `workspace_source = "create"`

The root also already supports attaching a workspace to an existing metastore.

Important current-state constraints:

- `ARCHITECTURE.md` describes the current repo target as a single workspace today, with a future multi-workspace shared-metastore direction.
- `identify.tf` assumes human users already exist through Okta SCIM and are present in `okta-databricks-users`; the Terraform layer only adds groups, memberships, workspace assignments, and entitlements for those users.
- the root currently has no explicit backend block and the working directory contains a local `terraform.tfstate`, so sandbox isolation cannot rely on branch separation alone
- `scenario2.premium-create-managed.tfvars` currently uses `uc_catalog_mode = "existing"` and `uc_existing_catalog_name = "main"`, which would keep the legacy single-catalog path pointed at a shared catalog

The sandbox design therefore has to solve two concrete problems:

1. isolate Terraform state from `main`
2. ensure the sandbox root never points at shared Databricks objects except the approved shared prerequisites

## Recommended Architecture

Use the existing root stack as the sandbox deployment entrypoint and keep the implementation root-focused, not module-focused.

The recommended shape is:

- stay in `infra/aws/dbx/databricks/us-west-1`
- add a dedicated sandbox var file
- add a dedicated sandbox state workflow
- keep actual resource names hard-coded in the `sandbox` branch, but make them explicitly sandbox-prefixed
- keep stable Terraform map keys where that reduces churn and avoids unnecessary rewiring

This approach is preferred because it keeps the current provider model, module boundaries, and root call structure intact while still giving the sandbox branch independent lifecycle control.

### Shared prerequisites

Only these objects are intentionally shared with `main`:

- Databricks account
- existing Unity Catalog metastore
- existing Okta SCIM-provisioned users

Everything else should be sandbox-owned or intentionally absent from the sandbox configuration.

### Unity Catalog mode choice

The sandbox workspace should set:

- `workspace_source = "create"`
- `network_configuration = "managed"`
- `metastore_exists = true`
- `uc_catalog_mode = "isolated"`

`uc_catalog_mode = "isolated"` is required for the sandbox branch because, in this repo, `uc_catalog_mode = "existing"` keeps the legacy root-catalog path pointed at `var.uc_existing_catalog_name`, which is currently `main`.

Using `isolated` ensures the legacy `local.catalog_name` path resolves to a sandbox-owned catalog instead of a shared catalog name from `main`. Governed catalogs in `catalogs_config.tf` continue to work independently of this choice.

## Root Configuration Shape

### Sandbox var file

Create a dedicated sandbox create-workspace var file based on scenario 2.

Required characteristics:

- same Databricks account ID as `main`
- same AWS account ID as `main`
- same region as `main`
- `workspace_source = "create"`
- `network_configuration = "managed"`
- `metastore_exists = true`
- `uc_catalog_mode = "isolated"`
- sandbox-specific `resource_prefix`

Example intent:

```hcl
resource_prefix         = "sandbox-infra"
pricing_tier            = "PREMIUM"
workspace_source        = "create"
network_configuration   = "managed"
uc_catalog_mode         = "isolated"
metastore_exists        = true
existing_workspace_host = null
existing_workspace_id   = null
```

### Sandbox state

The sandbox branch must use a dedicated Terraform state location rather than the default `terraform.tfstate`.

This is mandatory because the current root has no explicit remote backend and already carries a local state file. Without a dedicated state path, sandbox runs could reuse or overwrite `main` state.

The exact mechanism can be a dedicated backend path or an equivalent dedicated local-state configuration, but the operator workflow must make the sandbox state explicit and repeatable for:

- `init`
- `plan`
- `apply`
- `destroy`

### Identity

`identify.tf` should continue to reuse the same SCIM-provisioned users by email, but the Terraform-managed groups should become sandbox-specific by actual Databricks display name.

Keep stable Terraform keys where helpful. For example, the group key can stay `platform_admins` while the actual Databricks group display name becomes `Sandbox Platform Admins`.

Illustrative sandbox shape:

```hcl
locals {
  identity_groups = {
    platform_admins = {
      display_name          = "Sandbox Platform Admins"
      workspace_permissions = ["ADMIN"]
      entitlements = {
        allow_cluster_create  = true
        databricks_sql_access = true
        workspace_access      = true
      }
    }
  }

  identity_users = {
    giuliano = {
      user_name = "giulianoaltobelli@gmail.com"
      groups    = ["platform_admins"]
      entitlements = {
        allow_cluster_create  = true
        databricks_sql_access = true
        workspace_access      = true
      }
    }
  }
}
```

Required identity rule:

- do not create sandbox account-wide roles such as `account_admin`

### Governed catalogs and schemas

`catalogs_config.tf` should use explicit sandbox-prefixed catalog names instead of relying on the existing derived names when a duplicate would otherwise overlap with `main`.

Example:

```hcl
personal = {
  enabled             = true
  display_name        = "Sandbox Personal"
  catalog_kind        = "personal"
  catalog_name        = "sandbox_personal"
  source              = "personal"
  business_area       = ""
  catalog_admin_group = "platform_admins"
  reader_group        = []
  workspace_ids       = []
}
```

If the sandbox branch enables additional governed catalogs, those catalog names should also be explicitly sandbox-prefixed rather than derived from the production naming formula.

### Other root-managed Databricks objects

Any root-managed object that is duplicated for sandbox should use an explicitly sandbox-prefixed actual Databricks name.

Examples:

- cluster policy name: `Sandbox Bundle DLT Job Policy`
- service principal display name: `Sandbox UAT Promotion SP`
- SQL warehouse name: `Sandbox Analytics CI Warehouse`
- storage credential name: `sandbox-...`
- external location name: `sandbox-...`

Stable Terraform keys may remain unchanged when the actual provider-facing name is what determines collision and operator clarity.

### AWS-backed resources

Workspace-creation resources that already derive from `var.resource_prefix` are naturally isolated by a sandbox-specific `resource_prefix`.

That includes resources such as:

- workspace name
- root S3 bucket
- cross-account role name
- storage configuration names
- network object names
- KMS aliases and related AWS names

No additional naming framework is required for these because the root already keys them from `resource_prefix`.

## Behavior And Data Flow

When operating the sandbox branch:

1. Initialize Terraform with the dedicated sandbox state configuration.
2. Run Terraform with the sandbox var file, not a `main` scenario file.
3. The root creates a new Databricks workspace through the existing create-workspace path.
4. The shared existing metastore is assigned to that new workspace.
5. The `databricks.created_workspace` provider points all workspace-scoped modules at the sandbox workspace.
6. Root-level identity configuration reuses the same SCIM users but creates sandbox-specific Terraform-managed groups and workspace assignments.
7. Root-level Unity Catalog configuration creates sandbox-owned catalogs, schemas, volumes, and any enabled storage credentials or external locations.
8. Any enabled cluster policies, service principals, SQL warehouses, or other duplicated Databricks objects are created with sandbox-prefixed names.
9. Destroy reuses the same sandbox state and sandbox var file so Terraform deletes the sandbox workspace and sandbox-owned resources without touching `main`.

The important operational detail is that the sandbox branch does not depend on implicit branch isolation. The sandbox branch is safe only when all three are true at once:

- sandbox state
- sandbox var file
- sandbox-prefixed resource names

## Constraints And Failure Modes

### Shared resources that are intentionally not duplicated

These are intentionally shared:

- Databricks account
- existing metastore
- SCIM users

These should not be represented as sandbox-owned duplicates.

### Unsafe or invalid isolation patterns

The following patterns are invalid for the sandbox branch:

- using the default local `terraform.tfstate`
- keeping `uc_catalog_mode = "existing"`
- leaving a hard-coded `main`-style resource name in an active sandbox definition
- creating sandbox groups with account-wide roles
- pointing sandbox storage credentials or external locations at `main` backing IAM roles or storage paths while treating them as isolated
- running destroy with the wrong state or wrong branch checkout

### Subtle account-level behavior

Account-scoped service principals are allowed when needed, but they are still account-level identities. Their names should be sandbox-prefixed and their permissions must remain limited to the intended sandbox workspace and sandbox-owned downstream grants.

## Validation

Required validation for the sandbox branch:

- `terraform fmt -recursive`
- `terraform validate`
- a sandbox `terraform init` using the dedicated sandbox state configuration
- a sandbox `terraform plan` using the dedicated sandbox var file
- strict manual inspection that the plan creates a new workspace and sandbox-owned duplicates only
- strict manual confirmation that no `main` workspace resources are updated, replaced, or destroyed

Required destroy validation:

- use the same sandbox state configuration and the same sandbox var file
- inspect a destroy plan before execution
- confirm the destroy path targets only sandbox-owned resources

## Success Criteria

The design is successful when all of the following are true:

- the `sandbox` branch can create a separate Databricks workspace on the shared account and shared metastore
- the sandbox workflow uses its own Terraform state and cannot accidentally reuse `main` state
- sandbox-managed Databricks objects are explicitly sandbox-prefixed where duplication is required
- sandbox does not create account-wide roles
- the only intentionally shared prerequisites are the Databricks account, the existing metastore, and the existing SCIM users
- a sandbox plan shows no changes to the current `main` workspace or other `main`-owned Databricks objects
- the sandbox workspace and sandbox-owned resources can be destroyed quickly using the same sandbox state and sandbox var file
