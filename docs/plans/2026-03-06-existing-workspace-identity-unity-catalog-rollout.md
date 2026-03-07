# Existing Workspace Identity and Unity Catalog Rollout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement `ARCHITECTURE.md` on the existing Databricks workspace and existing metastore by rolling out phase 1 human identity provisioning, phase 2 fresh Terraform-managed catalogs and schemas, and phase 3 SQL-only CI service principals with dedicated SQL warehouse ACLs.

**Architecture:** Keep the existing workspace and metastore, but stop treating pre-existing Unity Catalog objects as the target state. Phase 1 refactors Terraform so it looks up Okta SCIM-provisioned humans and manages only additional Databricks groups, memberships, workspace assignments, and entitlements. Phase 2 creates fresh `personal` and `prod_<source>_<business_area>` catalogs plus schemas in the existing metastore, derives `personal.<user_key>` from live membership in the workspace-level `okta-databricks-users` group, and adds human Unity Catalog grants without changing the workspace default namespace. Phase 3 creates Terraform-managed SQL-only CI service principals, assigns them to the workspace as `USER`, grants `databricks_sql_access` only, provisions one dedicated SQL warehouse per principal, grants `CAN_USE` only on each warehouse, and adds schema-scoped Unity Catalog grants without pulling credentials into Terraform state.

**Tech Stack:** Terraform (~> 1.3), Databricks Terraform Provider (`databricks/databricks ~> 1.84`), AWS provider, `direnv`, existing workspace/metastore scenario (`scenario1.premium-existing.tfvars`), Markdown docs

---

Implementation guardrails:

- Use `@superpowers:using-git-worktrees` before editing.
- Use `@superpowers:test-driven-development` on every Terraform change.
- Use `@superpowers:verification-before-completion` before calling any phase complete.
- Use `@superpowers:requesting-code-review` before merge.
- Use only `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars` for `plan` and `apply` in this rollout.
- Do not broaden this work to workspace creation, isolated Unity Catalog catalogs, cluster/job identities, or `databricks_service_principal_secret`.
- Keep provider scope explicit in every child module:
  - `databricks.mws` for account-scoped users, groups, service principals, and workspace permission assignment
  - `databricks.created_workspace` for `databricks_entitlements`, SQL warehouses, SQL warehouse ACLs, and Unity Catalog resources

## Phase 1: Human Identity Provisioning

### Task 1: Refactor `users_groups` to look up existing SCIM users instead of creating them

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/variables.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/main.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/outputs.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/README.md`
- Reference: `ARCHITECTURE.md`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Capture the failing phase-1 behavior**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: the plan includes `databricks_user.users` or `databricks_user.users_protected` actions for `local.identity_users`, which violates the architecture because human users must already exist via Okta SCIM.

**Step 2: Change the module input contract to "lookup existing users"**

Replace the current user object schema with a lookup-only shape:

```hcl
variable "users" {
  description = "Existing account-level users to look up and assign."
  type = map(object({
    user_name             = string
    groups                = optional(set(string), [])
    roles                 = optional(set(string), [])
    workspace_permissions = optional(set(string), [])
    entitlements = optional(object({
      allow_cluster_create       = optional(bool)
      allow_instance_pool_create = optional(bool)
      databricks_sql_access      = optional(bool)
      workspace_access           = optional(bool)
      workspace_consume          = optional(bool)
    }))
  }))
  default = {}
}
```

Remove user-creation-only fields from `variables.tf` and `README.md`:

- `display_name`
- `active`
- `force`

Keep the existing validation rules for `workspace_permissions` and `workspace_consume`.

**Step 3: Replace account user resources with account user data sources**

Remove these resources from `main.tf`:

- `resource "databricks_user" "users"`
- `resource "databricks_user" "users_protected"`

Replace them with account-level lookups:

```hcl
data "databricks_user" "users" {
  provider  = databricks.mws
  for_each  = local.enabled_users
  user_name = each.value.user_name
}

locals {
  user_id_map = { for user_key, user in data.databricks_user.users : user_key => user.id }
}
```

Keep the rest of the module flow unchanged:

- `databricks_group`
- `databricks_group_member`
- `databricks_user_role`
- `databricks_group_role`
- `databricks_mws_permission_assignment`
- `databricks_entitlements`

Update `outputs.tf` so `output "user_ids"` still returns looked-up user IDs.

**Step 4: Run formatting, validation, and the scenario 1 plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected after change:

- `terraform validate` succeeds
- no `databricks_user` create actions remain for human users
- the plan still shows group, membership, workspace assignment, and entitlement resources

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups
git commit -m "refactor(users_groups): look up existing scim users"
```

### Task 2: Rework `identify.tf` into phase-1-only human identity inputs

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/identify.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/main.tf`
- Reference: `ARCHITECTURE.md`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Capture the failing root-level behavior**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: `identify.tf` still mixes human identity state with Unity Catalog grant state through `local.unity_catalog_group_catalog_privileges` and `resource "databricks_grant" "unity_catalog_group_catalog_grants"`.

**Step 2: Replace the locals with placeholder-safe human identity inputs**

Reshape `identify.tf` around already-provisioned humans and additional Databricks groups only. Placeholder names are acceptable here until the real groups and usernames are approved.

Use a structure like:

```hcl
locals {
  identity_groups = {
    platform_admins = {
      display_name          = "Platform Admins"
      roles                 = ["account_admin"]
      workspace_permissions = ["ADMIN"]
      entitlements = {
        databricks_sql_access = true
        workspace_access      = true
      }
    }

    revenue_readers = {
      display_name = "Revenue Readers"
    }
  }

  identity_users = {
    jane_doe = {
      user_name = "jane.doe@example.com"
      groups    = ["revenue_readers"]
    }

    john_smith = {
      user_name = "john.smith@example.com"
      groups    = ["platform_admins"]
    }
  }
}
```

Key points:

- Keep human identity placeholders in `identify.tf`
- Do not create any users in Terraform
- Use additional group membership only where requested
- Let baseline workspace access continue to come from Okta SCIM and `okta-databricks-users`

**Step 3: Remove the root-level Unity Catalog grant block from phase 1**

Delete:

- `local.unity_catalog_group_catalog_privileges`
- `resource "databricks_grant" "unity_catalog_group_catalog_grants"`

Replace them with a short comment in `identify.tf` noting that Unity Catalog grants move to phase 2 and phase 3.

**Step 4: Re-run validation and the scenario 1 plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected after change:

- no root-level Unity Catalog grants remain in phase 1
- plan output is limited to account/workspace identity resources for humans and groups

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/identify.tf
git commit -m "refactor(identity): make identify tf phase-1 human identity only"
```

### Task 3: Update root usage docs for the existing-workspace human identity path

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`
- Reference: `ARCHITECTURE.md`

**Step 1: Write the failing doc expectation**

The root README currently describes a broad deployment surface, but this architecture rollout must be implemented and verified only against the existing workspace and existing metastore path.

**Step 2: Add the human identity rollout notes**

Add a short section to the root README that states:

- this rollout uses the existing workspace and existing metastore path only
- human users are provisioned through Okta SCIM before Terraform runs
- `identify.tf` manages additional Databricks groups and memberships only
- phase 2 creates fresh Terraform-managed catalogs and schemas later

**Step 3: Re-read the updated section**

Run:

```bash
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/README.md
```

Expected: the README no longer implies that this architecture rollout is being validated against workspace creation or existing-catalog reuse.

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs(readme): document existing workspace scim identity path"
```

## Phase 2: Fresh Unity Catalog Catalogs and Schemas on the Existing Metastore

### Task 4: Create a workspace-level Unity Catalog namespace module

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/versions.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/variables.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/main.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/outputs.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/README.md`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Capture the failing phase-2 behavior**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: there are no Terraform-managed `personal` or `prod_*` catalogs and no `raw`, `base`, `staging`, `final`, `uat`, or `personal.<user_key>` schemas.

**Step 2: Define the module contract**

Create `variables.tf` with a minimal phase-2 shape:

```hcl
variable "admin_principals" {
  type = set(string)
}

variable "domain_catalogs" {
  type = map(object({
    catalog_name      = string
    reader_principals = set(string)
  }))
}

variable "personal_users" {
  type = map(object({
    schema_name = string
    principal   = string
  }))
}

variable "uat_writer_principals" {
  type    = set(string)
  default = []
}

variable "release_writer_principals" {
  type    = set(string)
  default = []
}
```

Add `versions.tf` with the Databricks provider requirement for a workspace-level module.

**Step 3: Implement fresh catalog and schema resources**

Create `main.tf` with:

- `databricks_catalog.personal`
- `databricks_catalog.domain_catalogs`
- one `databricks_schema` per domain schema in `raw`, `base`, `staging`, `final`, `uat`
- one `databricks_schema` per personal user schema

Use a flattening local so all schema resources are driven from a predictable map:

```hcl
locals {
  governed_schema_names = toset(["raw", "base", "staging", "final", "uat"])

  governed_schema_map = {
    for schema in flatten([
      for domain_key, domain in var.domain_catalogs : [
        for schema_name in local.governed_schema_names : {
          key         = "${domain_key}:${schema_name}"
          catalog_name = domain.catalog_name
          schema_name = schema_name
        }
      ]
    ]) : schema.key => schema
  }
}
```

Create `outputs.tf` for at least:

- `catalog_names`
- `governed_schema_names`
- `personal_schema_names`

**Step 4: Re-run formatting and re-read the new module**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/variables.tf
sed -n '1,260p' infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/main.tf
```

Expected: the new module files read cleanly and are ready to be validated from the root once Task 5 wires them into the existing workspace entrypoint.

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace
git commit -m "feat(uc): add workspace namespace module"
```

### Task 5: Wire fresh catalogs and personal schemas from live `okta-databricks-users` membership

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/unity_catalog.tf`
- Delete: `infra/aws/dbx/databricks/us-west-1/uc_existing_catalog.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/provider.tf`
- Reference: `docs/design-docs/unity-catalog.md`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Add root locals and data sources for the fresh namespace model**

Create `unity_catalog.tf` with:

- placeholder domain catalog definitions
- an admin principal set
- a workspace-level lookup of `okta-databricks-users`
- one workspace-level `databricks_user` lookup per member to derive `personal.<user_key>`

Use a shape like:

```hcl
locals {
  domain_catalogs = {
    salesforce_revenue = {
      catalog_name      = "prod_salesforce_revenue"
      reader_principals = toset([local.identity_groups.revenue_readers.display_name])
    }
  }

  uc_admin_principals = toset([
    local.identity_groups.platform_admins.display_name,
    var.admin_user,
  ])
}

data "databricks_group" "workspace_okta_users" {
  provider     = databricks.created_workspace
  display_name = "okta-databricks-users"
}

data "databricks_user" "workspace_okta_users" {
  provider = databricks.created_workspace
  for_each = data.databricks_group.workspace_okta_users.members
  user_id  = each.key
}

locals {
  personal_users = {
    for _, user in data.databricks_user.workspace_okta_users :
    user.alphanumeric => {
      schema_name = user.alphanumeric
      principal   = user.user_name
    }
  }
}
```

**Step 2: Instantiate the child module with explicit provider wiring**

Wire the child module explicitly because aliased providers do not flow automatically:

```hcl
module "unity_catalog_namespace" {
  source = "./modules/databricks_workspace/unity_catalog_namespace"

  providers = {
    databricks = databricks.created_workspace
  }

  admin_principals          = local.uc_admin_principals
  domain_catalogs           = local.domain_catalogs
  personal_users            = local.personal_users
  uat_writer_principals     = toset([])
  release_writer_principals = toset([])
}
```

**Step 3: Delete the existing-catalog default namespace file**

Delete `uc_existing_catalog.tf` entirely.

Why:

- phase 2 starts fresh with Terraform-managed catalogs
- the architecture says to keep the workspace default namespace unchanged for now
- this rollout should no longer manage an existing catalog grant or default namespace setting

**Step 4: Run the scenario 1 plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- fresh `personal` and `prod_*` catalogs appear
- `raw`, `base`, `staging`, `final`, and `uat` schemas appear for every domain catalog
- `personal.<user_key>` schemas appear for live `okta-databricks-users` members
- no `databricks_default_namespace_setting` changes remain

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/unity_catalog.tf infra/aws/dbx/databricks/us-west-1/uc_existing_catalog.tf
git commit -m "feat(uc): wire fresh catalogs and personal schemas"
```

### Task 6: Add phase-2 human-only Unity Catalog grants

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/main.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/README.md`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Capture the missing-access behavior**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: catalogs and schemas exist, but there are no reader grants, no personal schema owner grants, and no break-glass admin grants on the new Unity Catalog objects.

**Step 2: Add catalog-level and schema-level grants for humans**

Add `databricks_grant` resources in the namespace module for:

- `admin_principals` -> `ALL_PRIVILEGES` on every governed catalog, `personal` catalog, and every governed/personal schema
- `reader_principals` -> `USE_CATALOG` on each governed catalog
- `reader_principals` -> `USE_SCHEMA` and `SELECT` on each governed schema
- each personal schema owner -> `ALL_PRIVILEGES` on `personal.<user_key>`

Use a flattening pattern so catalog/schema grants remain deterministic:

```hcl
resource "databricks_grant" "governed_catalog_readers" {
  for_each = {
    for pair in flatten([
      for domain_key, domain in var.domain_catalogs : [
        for principal in domain.reader_principals : {
          key        = "${domain_key}:${principal}"
          catalog    = domain.catalog_name
          principal  = principal
        }
      ]
    ]) : pair.key => pair
  }

  catalog     = each.value.catalog
  principal   = each.value.principal
  privileges  = ["USE_CATALOG"]
}
```

Keep `uat_writer_principals` and `release_writer_principals` empty in phase 2.

**Step 3: Run validation and the scenario 1 plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected after change:

- reader groups receive `USE_CATALOG`, `USE_SCHEMA`, and `SELECT` only
- personal schema owners receive `ALL_PRIVILEGES` only on their own schema
- no CI service principal grants or SQL warehouse resources exist yet

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace
git commit -m "feat(uc): add human catalog and schema grants"
```

### Task 7: Align the design docs with the phase-2 implementation

**Files:**
- Modify: `docs/design-docs/unity-catalog.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`
- Reference: `ARCHITECTURE.md`

**Step 1: Write the failing doc expectation**

`docs/design-docs/unity-catalog.md` still says personal schema users come from `keys(local.identity_users)`, but phase 2 derives them from live workspace membership in `okta-databricks-users`.

**Step 2: Update the docs**

In `docs/design-docs/unity-catalog.md`:

- replace `keys(local.identity_users)` with live workspace membership
- note that `personal.<user_key>` comes from `data.databricks_group.workspace_okta_users.members` plus `data.databricks_user.*.alphanumeric`
- keep the existing Unity Catalog boundary model intact

In the root README:

- call out `unity_catalog.tf` as the phase-2 entrypoint
- note that the workspace default namespace is intentionally left unchanged
- note that pre-existing catalogs are not the target state for this rollout

**Step 3: Re-read the updated docs**

Run:

```bash
sed -n '1,260p' docs/design-docs/unity-catalog.md
sed -n '1,260p' infra/aws/dbx/databricks/us-west-1/README.md
```

Expected: the docs describe live workspace membership for `personal` schemas and the fresh-catalog phase-2 model without referencing existing-catalog reuse.

**Step 4: Commit**

```bash
git add docs/design-docs/unity-catalog.md infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs(uc): align design docs with fresh catalog rollout"
```

## Phase 3: SQL-Only CI Service Principals, Warehouses, and Grants

### Task 8: Add a dedicated account/workspace service principal module for SQL-only CI identities

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/service_principals/versions.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/service_principals/variables.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/service_principals/main.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/service_principals/outputs.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/service_principals/README.md`
- Create: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Capture the missing phase-3 identity path**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: there is no Terraform-managed path for the `UAT promotion` and `release` service principals.

**Step 2: Create the service principal module contract**

In `variables.tf`, define:

```hcl
variable "workspace_id" {
  type = string
}

variable "service_principals" {
  type = map(object({
    display_name          = string
    workspace_permissions = optional(set(string), ["USER"])
    entitlements = optional(object({
      databricks_sql_access = optional(bool)
    }))
  }))
}
```

In `versions.tf`, require both provider aliases explicitly:

```hcl
terraform {
  required_providers {
    databricks = {
      source = "databricks/databricks"
      configuration_aliases = [
        databricks.mws,
        databricks.workspace,
      ]
    }
  }
}
```

**Step 3: Implement account creation, workspace assignment, and SQL-only entitlements**

Create these resources in `main.tf`:

```hcl
resource "databricks_service_principal" "this" {
  provider     = databricks.mws
  for_each     = var.service_principals
  display_name = each.value.display_name
}

resource "databricks_mws_permission_assignment" "workspace" {
  provider     = databricks.mws
  for_each     = var.service_principals
  workspace_id = var.workspace_id
  principal_id = databricks_service_principal.this[each.key].id
  permissions  = sort(tolist(each.value.workspace_permissions))
}

resource "databricks_entitlements" "workspace" {
  provider             = databricks.workspace
  for_each             = var.service_principals
  service_principal_id = databricks_service_principal.this[each.key].id
  databricks_sql_access = coalesce(try(each.value.entitlements.databricks_sql_access, null), false)
}
```

Do not add:

- `workspace_access`
- `workspace_consume`
- `allow_cluster_create`
- `allow_instance_pool_create`
- `databricks_service_principal_secret`

Add `outputs.tf` for at least:

- `ids`
- `application_ids`
- `display_names`

**Step 4: Wire the root module with explicit providers**

Create `service_principals.tf` with placeholder-safe display names:

```hcl
locals {
  ci_service_principals = {
    uat_promotion = {
      display_name = "UAT Promotion SP"
      entitlements = {
        databricks_sql_access = true
      }
    }

    release = {
      display_name = "Release SP"
      entitlements = {
        databricks_sql_access = true
      }
    }
  }
}

module "ci_service_principals" {
  source = "./modules/databricks_account/service_principals"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  workspace_id        = local.workspace_id
  service_principals  = local.ci_service_principals
}
```

**Step 5: Run formatting, validation, and the scenario 1 plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- two service principals are created or managed
- both are assigned to the workspace as `USER`
- both receive `databricks_sql_access = true`
- no secret resources appear anywhere in the plan

**Step 6: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_account/service_principals infra/aws/dbx/databricks/us-west-1/service_principals.tf
git commit -m "feat(identity): add sql only ci service principals"
```

### Task 9: Add dedicated SQL warehouses and `CAN_USE`-only warehouse ACLs

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Capture the missing warehouse boundary**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: there are no dedicated SQL warehouses and no warehouse ACLs for the two CI service principals.

**Step 2: Create one warehouse per principal**

Create `sql_warehouses.tf` with one `databricks_sql_endpoint` per CI principal. Use placeholder sizing values and confirm them before apply if needed.

Use a root local like:

```hcl
locals {
  ci_sql_warehouses = {
    uat_promotion = {
      name             = "uat-promotion-warehouse"
      cluster_size     = "2X-Small"
      auto_stop_mins   = 10
      max_num_clusters = 1
    }

    release = {
      name             = "governed-release-warehouse"
      cluster_size     = "2X-Small"
      auto_stop_mins   = 10
      max_num_clusters = 1
    }
  }
}

resource "databricks_sql_endpoint" "ci" {
  provider = databricks.created_workspace
  for_each = local.ci_sql_warehouses

  name             = each.value.name
  cluster_size     = each.value.cluster_size
  auto_stop_mins   = each.value.auto_stop_mins
  max_num_clusters = each.value.max_num_clusters
}
```

**Step 3: Add `CAN_USE`-only ACLs tied to each service principal's own warehouse**

Use `databricks_permissions` with the workspace provider and the service principal application ID output:

```hcl
resource "databricks_permissions" "ci_warehouse_use" {
  provider        = databricks.created_workspace
  for_each        = databricks_sql_endpoint.ci
  sql_endpoint_id = each.value.id

  access_control {
    service_principal_name = module.ci_service_principals.application_ids[each.key]
    permission_level       = "CAN_USE"
  }
}
```

Do not add:

- `CAN_MANAGE`
- cluster permissions
- cluster policy permissions
- job permissions

**Step 4: Run validation and the scenario 1 plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- one dedicated SQL warehouse per CI principal
- each principal receives `CAN_USE` only on its own warehouse
- no principal receives `CAN_MANAGE`

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf
git commit -m "feat(sql): add dedicated ci warehouses and can use acls"
```

### Task 10: Add schema-scoped Unity Catalog grants for the SQL-only CI principals

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/variables.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/main.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace/README.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/unity_catalog.tf`
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Capture the missing CI data-access boundary**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: the new service principals exist, but they have no Unity Catalog grants and therefore cannot use their warehouses to access the target schemas.

**Step 2: Pass the CI service principals into the namespace module**

Update `unity_catalog.tf` to pass the service principal application IDs as the grant principals:

```hcl
module "unity_catalog_namespace" {
  source = "./modules/databricks_workspace/unity_catalog_namespace"

  providers = {
    databricks = databricks.created_workspace
  }

  admin_principals          = local.uc_admin_principals
  domain_catalogs           = local.domain_catalogs
  personal_users            = local.personal_users
  uat_writer_principals     = toset([module.ci_service_principals.application_ids["uat_promotion"]])
  release_writer_principals = toset([module.ci_service_principals.application_ids["release"]])
}
```

**Step 3: Add the CI grants in the module without crossing the intended boundaries**

In `main.tf`, add:

- `USE_CATALOG` grants for UAT promotion and release on each governed catalog
- `ALL_PRIVILEGES` on `*.uat` schemas for `uat_writer_principals`
- `ALL_PRIVILEGES` on `*.raw`, `*.base`, `*.staging`, and `*.final` schemas for `release_writer_principals`

Do not grant:

- any `uat_writer_principals` access to `raw`, `base`, `staging`, or `final`
- any `release_writer_principals` access to `uat`

Use a filtered schema map so the boundary is obvious in code:

```hcl
locals {
  uat_schema_map = {
    for key, schema in local.governed_schema_map : key => schema
    if schema.schema_name == "uat"
  }

  release_schema_map = {
    for key, schema in local.governed_schema_map : key => schema
    if contains(["raw", "base", "staging", "final"], schema.schema_name)
  }
}
```

Then flatten `(schema, principal)` pairs into `databricks_grant` resources.

**Step 4: Run validation and the scenario 1 plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- UAT promotion SP has `USE_CATALOG` plus schema-scoped `ALL_PRIVILEGES` only on `prod_*.*.uat`
- Release SP has `USE_CATALOG` plus schema-scoped `ALL_PRIVILEGES` only on `prod_*.*.(raw|base|staging|final)`
- the Unity Catalog boundary model stays unchanged
- there is still no credential management in the plan

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/unity_catalog.tf infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_namespace
git commit -m "feat(uc): add sql only ci principal grants"
```

## Final Verification and Docs

### Task 11: Update architecture docs and run the end-to-end verification sequence

**Files:**
- Modify: `ARCHITECTURE.md`
- Modify: `docs/design-docs/unity-catalog.md`
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`
- Reference: `infra/aws/dbx/databricks/us-west-1/identify.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/unity_catalog.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`

**Step 1: Update the architecture documents to match the implemented model**

In `ARCHITECTURE.md`, add or confirm:

- phase 1 human identities are looked up from Okta SCIM and assigned to additional Databricks groups
- phase 2 creates fresh catalogs and schemas in the existing workspace/metastore
- phase 3 creates SQL-only CI service principals and dedicated SQL warehouses
- warehouse ACLs are `CAN_USE` only
- credentials are intentionally out of scope for the main Terraform plan

In `docs/design-docs/unity-catalog.md`, add the same SQL-only service principal and warehouse boundary notes.

**Step 2: Review the combined diff**

Run:

```bash
git diff -- ARCHITECTURE.md docs/design-docs/unity-catalog.md infra/aws/dbx/databricks/us-west-1
```

Expected: the diff shows a coherent progression from human identity setup, to fresh catalog/schema rollout, to SQL-only CI principals with warehouse ACLs.

**Step 3: Run the full local verification sequence**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- formatting is clean
- validation succeeds
- scenario 1 plan shows only the intended existing-workspace and existing-metastore changes
- no cluster, job, or secret-management resources appear

**Step 4: Optional apply after explicit plan review**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply -var-file=scenario1.premium-existing.tfvars
```

Expected: successful creation or update of human groups/memberships, fresh catalogs/schemas/grants, SQL-only CI service principals, dedicated SQL warehouses, warehouse `CAN_USE` ACLs, and phase-3 Unity Catalog grants.

**Step 5: Commit**

```bash
git add ARCHITECTURE.md docs/design-docs/unity-catalog.md infra/aws/dbx/databricks/us-west-1
git commit -m "feat(databricks): roll out existing workspace identity and uc model"
```
