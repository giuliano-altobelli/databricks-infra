# Service Principals Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a mixed account-level and workspace-level Databricks service-principal identity module plus a root `service_principals.tf` caller that can create new principals, optionally assign account-scoped principals into one workspace, and manage workspace entitlements without handling secrets or downstream grants.

**Architecture:** Create a new `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals` module that accepts a single stable-keyed `service_principals` map, splits behavior internally by `principal_scope`, and uses `databricks.mws` only for account-scoped creation plus workspace assignment while using `databricks.workspace` only for workspace-scoped creation plus workspace entitlements. Keep the checked-in root surface in `infra/aws/dbx/databricks/us-west-1/service_principals.tf`, wire the aliased providers explicitly, keep the checked-in configuration safe by default on `main`, and leave Unity Catalog grants, warehouse ACLs, roles, group membership, and credentials outside this identity layer.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider `~> 1.84`, aliased providers `databricks.mws` and `databricks.created_workspace`, `direnv`, `DATABRICKS_AUTH_TYPE=oauth-m2m`, Markdown docs

---

**Spec:** `docs/superpowers/specs/2026-03-13-service-principals-design.md`

**Execution Notes:**
- Use `@subagent-driven-development` to execute the tasks.
- Use `@test-driven-development` before each behavioral Terraform change, even when the “test” is a failing `terraform validate` or `terraform plan`.
- Use `@verification-before-completion` before claiming success.
- Use `@requesting-code-review` after the final verification pass.
- Do not use `@using-git-worktrees`; the user explicitly asked to stay on `main`.
- Keep the scope mixed account-level plus workspace-level only. Do not add service principal secrets, group membership, account roles, Unity Catalog grants, SQL warehouse ACLs, or multi-workspace fan-out.
- Use the repo-standard root verification command shape only: `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 <plan|apply> -var-file=scenario1.premium-existing.tfvars`
- Do not execute any `git commit` step until the user has approved this plan for implementation.

## File Structure

Create these module files:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/versions.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/outputs.tf`

Delete this template-only file after scaffolding:

- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/FACTS.md`

Create this root caller:

- `infra/aws/dbx/databricks/us-west-1/service_principals.tf`

Modify this operator doc:

- `infra/aws/dbx/databricks/us-west-1/README.md`

Reference these existing files while implementing, but do not change them unless a later review uncovers a real defect:

- `ARCHITECTURE.md`
- `docs/superpowers/specs/2026-03-13-service-principals-design.md`
- `infra/aws/dbx/databricks/us-west-1/provider.tf`
- `infra/aws/dbx/databricks/us-west-1/locals.tf`
- `infra/aws/dbx/databricks/us-west-1/identify.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/versions.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/outputs.tf`

Responsibilities:

- `service_principals/SPEC.md`: local implementation contract for mixed-scope principal creation, optional workspace assignment, entitlement behavior, validation, and outputs.
- `service_principals/README.md`: mixed-scope usage example, provider wiring, stable-key rules, and explicit out-of-scope boundaries.
- `service_principals/versions.tf`: Databricks provider version plus required alias declarations.
- `service_principals/variables.tf`: public input contract and validation rules.
- `service_principals/main.tf`: scope split, resource graph, normalized entitlement locals, and dependency ordering.
- `service_principals/outputs.tf`: stable maps for IDs, application IDs, display names, workspace assignment IDs, and entitlement IDs.
- `service_principals.tf`: root identity catalog for Terraform-managed service principals and the explicit provider wiring to `databricks.mws` plus `databricks.created_workspace`.
- root `README.md`: operator guidance for enabling and populating the new service-principal identity catalog without expecting it to manage secrets or Unity Catalog grants.

## Chunk 1: Module Contract And Resource Graph

### Task 1: Scaffold The Mixed-Scope Service Principal Module

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/SPEC.md`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/README.md`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/versions.tf`
- Delete: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/FACTS.md`

- [ ] **Step 1: Scaffold the new module from the repo template**

Run:

```bash
test ! -e infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals
scripts/new_module.sh databricks_identity/service_principals
```

Expected: the new module directory exists with the template file set and no existing implementation is overwritten.

- [ ] **Step 2: Replace `SPEC.md` with the approved mixed-scope contract**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/SPEC.md` with these exact top-level sections:

```md
# Module Spec

## Summary
## Scope
## Interfaces
## Provider Context
## Behavior / Data Flow
## Constraints and Failure Modes
## Validation
```

The spec must encode these boundaries explicitly:

```md
- one `databricks_service_principal` resource set on `databricks.mws` for `principal_scope = "account"`
- one `databricks_service_principal` resource set on `databricks.workspace` for `principal_scope = "workspace"`
- optional `databricks_mws_permission_assignment` only for account-scoped principals whose `workspace_assignment.enabled = true`
- optional `databricks_entitlements` only for principals whose `entitlements` object is present
- exactly one target workspace per module invocation
- no service principal credentials or secret resources
- no group membership
- no account roles
- no Unity Catalog grants
- no warehouse permissions
- no multi-workspace fan-out
```

In `## Interfaces`, list:

- required provider aliases `databricks.mws` and `databricks.workspace`
- required input `service_principals`
- optional inputs `enabled` and `workspace_id`
- `service_principals[*].display_name`
- `service_principals[*].principal_scope`
- `service_principals[*].workspace_assignment.enabled`
- `service_principals[*].workspace_assignment.permissions`
- `service_principals[*].entitlements.allow_cluster_create`
- `service_principals[*].entitlements.allow_instance_pool_create`
- `service_principals[*].entitlements.databricks_sql_access`
- `service_principals[*].entitlements.workspace_access`
- `service_principals[*].entitlements.workspace_consume`
- output maps `ids`, `application_ids`, `display_names`, `workspace_assignment_ids`, and `entitlements_ids`
- the `enabled = false` behavior returning empty maps for every output

In `## Validation`, list the required failure cases from the governing design:

- invalid `principal_scope`
- invalid workspace assignment permission values
- conflicting `workspace_consume`
- workspace assignment requested for workspace-scoped principals
- account-scoped entitlements requested without workspace assignment
- workspace assignment requested without a usable `workspace_id`

Also call out these runtime failure modes in `## Constraints and Failure Modes`:

- insufficient account-level privileges on `databricks.mws`
- insufficient workspace-level privileges on `databricks.workspace`
- `display_name` collisions with an existing service principal
- caller/provider mismatch where `workspace_id` and `databricks.workspace` point at different workspaces

- [ ] **Step 3: Rewrite `README.md` with a concrete mixed-scope usage example**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/README.md` with a working-shaped example like this:

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

The README must also explain:

- stable map keys are Terraform addresses and downstream lookup keys
- `databricks.mws` is required for account-scoped creation and workspace assignment
- `databricks.workspace` is required for workspace-scoped creation and all entitlements
- account-scoped entitlements require workspace assignment
- workspace-scoped principals must not request workspace assignment
- entitlement fields are authoritative when the `entitlements` object exists, and omitted entitlement fields are treated as `false`
- `enabled = false` returns empty maps
- credentials, Unity Catalog grants, warehouse ACLs, group membership, and account roles stay outside this module

- [ ] **Step 4: Set the provider aliases in `versions.tf` and remove the unused facts file**

Replace `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/versions.tf` with:

```hcl
terraform {
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      version               = "~> 1.84"
      configuration_aliases = [databricks.mws, databricks.workspace]
    }
  }

  required_version = "~> 1.3"
}
```

Then remove the template-only facts file:

```bash
rm infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/FACTS.md
```

- [ ] **Step 5: Format and re-read the scaffold before deeper implementation**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals fmt
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/SPEC.md
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/README.md
sed -n '1,120p' infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/versions.tf
```

Expected: the scaffold is formatted, the provider aliases match the design, and the module docs state the mixed-scope contract without mentioning secrets or downstream grants.

- [ ] **Step 6: Commit the scaffold after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals
git commit -m "feat(identity): scaffold mixed scope service principal module"
```

Expected: one commit containing only the new module scaffold and docs.

### Task 2: Define The Public Variable Contract And Validation Rules

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/variables.tf`

- [ ] **Step 1: Replace `variables.tf` with the approved mixed-scope input contract**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/variables.tf` as:

```hcl
variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "workspace_id" {
  description = "Target workspace ID for account-scoped workspace assignment. The databricks.workspace provider must point at this same workspace when entitlements are managed."
  type        = string
  default     = ""
}

variable "service_principals" {
  description = "Databricks service principals keyed by stable caller-defined identifiers."
  type = map(object({
    display_name    = string
    principal_scope = string
    workspace_assignment = optional(object({
      enabled     = optional(bool, false)
      permissions = optional(set(string), ["USER"])
    }))
    entitlements = optional(object({
      allow_cluster_create       = optional(bool)
      allow_instance_pool_create = optional(bool)
      databricks_sql_access      = optional(bool)
      workspace_access           = optional(bool)
      workspace_consume          = optional(bool)
    }))
  }))
  default = {}

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      contains(["account", "workspace"], principal.principal_scope)
    ])
    error_message = "service_principals[*].principal_scope must be either account or workspace."
  }

  validation {
    condition = !var.enabled || alltrue(flatten([
      for principal in values(var.service_principals) : [
        for permission in coalesce(try(principal.workspace_assignment.permissions, null), toset([])) :
        contains(["ADMIN", "USER"], permission)
      ]
    ]))
    error_message = "service_principals[*].workspace_assignment.permissions may only contain ADMIN or USER."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      principal.entitlements == null ? true : !(
        coalesce(try(principal.entitlements.workspace_consume, null), false) &&
        (
          coalesce(try(principal.entitlements.workspace_access, null), false) ||
          coalesce(try(principal.entitlements.databricks_sql_access, null), false)
        )
      )
    ])
    error_message = "service_principals[*].entitlements.workspace_consume cannot be true with workspace_access or databricks_sql_access."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      principal.principal_scope != "workspace" || !coalesce(try(principal.workspace_assignment.enabled, null), false)
    ])
    error_message = "Workspace-scoped service principals must not request workspace assignment."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      principal.principal_scope != "account" || principal.entitlements == null || coalesce(try(principal.workspace_assignment.enabled, null), false)
    ])
    error_message = "Account-scoped service principals may manage entitlements only when workspace_assignment.enabled is true."
  }

  validation {
    condition = !var.enabled || alltrue([
      for principal in values(var.service_principals) :
      !coalesce(try(principal.workspace_assignment.enabled, null), false) || trimspace(var.workspace_id) != ""
    ])
    error_message = "workspace_id must be non-empty when any service principal requests workspace assignment."
  }
}
```

- [ ] **Step 2: Format and module-validate the input contract**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals fmt
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals validate
```

Expected: the module validates successfully with the default empty map and the provider alias declarations are accepted.

- [ ] **Step 3: Commit the variable contract after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/variables.tf infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/.terraform.lock.hcl
git commit -m "feat(identity): add service principal module contract"
```

Expected: one commit containing only the public input contract and module initialization metadata if Terraform created a lockfile.

### Task 3: Implement The Mixed-Scope Resource Graph And Stable Outputs

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/main.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/outputs.tf`

- [ ] **Step 1: Replace `main.tf` with the mixed-scope implementation**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/main.tf` as:

```hcl
locals {
  enabled_service_principals = var.enabled ? var.service_principals : {}

  account_service_principals = {
    for principal_key, principal in local.enabled_service_principals :
    principal_key => principal
    if principal.principal_scope == "account"
  }

  workspace_service_principals = {
    for principal_key, principal in local.enabled_service_principals :
    principal_key => principal
    if principal.principal_scope == "workspace"
  }

  workspace_assignments = {
    for principal_key, principal in local.account_service_principals :
    principal_key => sort(tolist(coalesce(try(principal.workspace_assignment.permissions, null), toset(["USER"]))))
    if coalesce(try(principal.workspace_assignment.enabled, null), false)
  }

  entitlement_principals = {
    for principal_key, principal in local.enabled_service_principals :
    principal_key => {
      allow_cluster_create       = coalesce(try(principal.entitlements.allow_cluster_create, null), false)
      allow_instance_pool_create = coalesce(try(principal.entitlements.allow_instance_pool_create, null), false)
      databricks_sql_access      = coalesce(try(principal.entitlements.databricks_sql_access, null), false)
      workspace_access           = coalesce(try(principal.entitlements.workspace_access, null), false)
      workspace_consume          = coalesce(try(principal.entitlements.workspace_consume, null), false)
    }
    if principal.entitlements != null
  }
}

resource "databricks_service_principal" "account" {
  provider = databricks.mws
  for_each = local.account_service_principals

  display_name = each.value.display_name
}

resource "databricks_service_principal" "workspace" {
  provider = databricks.workspace
  for_each = local.workspace_service_principals

  display_name = each.value.display_name
}

locals {
  service_principal_ids = merge(
    { for principal_key, principal in databricks_service_principal.account : principal_key => principal.id },
    { for principal_key, principal in databricks_service_principal.workspace : principal_key => principal.id }
  )

  service_principal_application_ids = merge(
    { for principal_key, principal in databricks_service_principal.account : principal_key => principal.application_id },
    { for principal_key, principal in databricks_service_principal.workspace : principal_key => principal.application_id }
  )

  service_principal_display_names = merge(
    { for principal_key, principal in databricks_service_principal.account : principal_key => principal.display_name },
    { for principal_key, principal in databricks_service_principal.workspace : principal_key => principal.display_name }
  )
}

resource "databricks_mws_permission_assignment" "workspace" {
  provider = databricks.mws
  for_each = local.workspace_assignments

  workspace_id = var.workspace_id
  principal_id = local.service_principal_ids[each.key]
  permissions  = each.value
}

resource "databricks_entitlements" "workspace" {
  provider = databricks.workspace
  for_each = local.entitlement_principals

  service_principal_id       = local.service_principal_ids[each.key]
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create
  databricks_sql_access      = each.value.databricks_sql_access
  workspace_access           = each.value.workspace_access
  workspace_consume          = each.value.workspace_consume

  depends_on = [databricks_mws_permission_assignment.workspace]
}
```

Implementation notes for this step:

- do not add `databricks_service_principal_secret`
- do not add account roles, memberships, grants, warehouses, or permissions resources
- keep `databricks_entitlements` authoritative by always sending every supported field when `entitlements` is present
- keep the resource split strictly by `principal_scope`

- [ ] **Step 2: Replace `outputs.tf` with stable map outputs keyed by caller-defined principal keys**

Write `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/outputs.tf` as:

```hcl
output "ids" {
  description = "Map of service principal keys to Databricks service principal IDs."
  value       = local.service_principal_ids
}

output "application_ids" {
  description = "Map of service principal keys to Databricks application IDs."
  value       = local.service_principal_application_ids
}

output "display_names" {
  description = "Map of service principal keys to created display names."
  value       = local.service_principal_display_names
}

output "workspace_assignment_ids" {
  description = "Map of workspace assignment IDs keyed by service principal key."
  value       = { for principal_key, assignment in databricks_mws_permission_assignment.workspace : principal_key => assignment.id }
}

output "entitlements_ids" {
  description = "Map of workspace entitlement IDs keyed by service principal key."
  value       = { for principal_key, entitlement in databricks_entitlements.workspace : principal_key => entitlement.id }
}
```

- [ ] **Step 3: Run module formatting and module validation again**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals fmt
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals validate
```

Expected:

- the module validates with the default empty `service_principals` map
- `enabled = false` still implies no resources and empty outputs
- the mixed-scope resource split is syntactically valid with both aliased providers

- [ ] **Step 4: Re-read the new implementation files before wiring the root caller**

Run:

```bash
sed -n '1,240p' infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/main.tf
sed -n '1,220p' infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/outputs.tf
```

Expected: the implementation contains only the resources in scope and publishes only the stable maps required by the design.

- [ ] **Step 5: Commit the module implementation after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals
git commit -m "feat(identity): implement mixed scope service principal module"
```

Expected: one commit containing the working module implementation and no root-caller changes yet.

## Chunk 2: Root Caller, Validation Harness, And Operator Docs

### Task 4: Create The Root Caller And Prove The Validation Failures

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`

- [ ] **Step 1: Create a temporary failing root harness for the workspace-scoped assignment check**

Write `infra/aws/dbx/databricks/us-west-1/service_principals.tf` as:

```hcl
locals {
  service_principals_enabled = true

  service_principals = {
    workspace_assignment_invalid = {
      display_name    = "Workspace Assignment Invalid SP"
      principal_scope = "workspace"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
    }
  }
}

module "service_principals" {
  source = "./modules/databricks_identity/service_principals"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  enabled            = local.service_principals_enabled
  workspace_id       = local.workspace_id
  service_principals = local.service_principals

  depends_on = [module.unity_catalog_metastore_assignment]
}
```

- [ ] **Step 2: Run root validation and confirm the workspace-scope rule fails**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: FAIL with `Workspace-scoped service principals must not request workspace assignment.`

- [ ] **Step 3: Swap in an account-scoped principal with entitlements but no assignment and re-run validation**

Replace `locals.service_principals` with:

```hcl
  service_principals = {
    missing_assignment_invalid = {
      display_name    = "Missing Assignment Invalid SP"
      principal_scope = "account"
      entitlements = {
        databricks_sql_access = true
      }
    }
  }
```

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: FAIL with `Account-scoped service principals may manage entitlements only when workspace_assignment.enabled is true.`

- [ ] **Step 4: Swap in an invalid workspace permission and re-run validation**

Replace `locals.service_principals` with:

```hcl
  service_principals = {
    invalid_permission = {
      display_name    = "Invalid Permission SP"
      principal_scope = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["SUPERUSER"]
      }
    }
  }
```

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: FAIL with `service_principals[*].workspace_assignment.permissions may only contain ADMIN or USER.`

- [ ] **Step 5: Swap in a conflicting `workspace_consume` entitlement and re-run validation**

Replace `locals.service_principals` with:

```hcl
  service_principals = {
    conflicting_consume = {
      display_name    = "Conflicting Consume SP"
      principal_scope = "workspace"
      entitlements = {
        workspace_consume     = true
        databricks_sql_access = true
      }
    }
  }
```

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: FAIL with `service_principals[*].entitlements.workspace_consume cannot be true with workspace_access or databricks_sql_access.`

- [ ] **Step 6: Prove the empty `workspace_id` guard by changing only the module call**

Keep `service_principals_enabled = true` and replace the module input line:

```hcl
  workspace_id = ""
```

Use this `locals.service_principals` map:

```hcl
  service_principals = {
    assignment_requires_workspace_id = {
      display_name    = "Assignment Requires Workspace Id SP"
      principal_scope = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
    }
  }
```

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: FAIL with `workspace_id must be non-empty when any service principal requests workspace assignment.`

### Task 5: Install The Final Safe Root Caller And Update Operator Docs

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

- [ ] **Step 1: Replace the failing harness with the checked-in safe root caller**

Rewrite `infra/aws/dbx/databricks/us-west-1/service_principals.tf` as:

```hcl
locals {
  service_principals_enabled = false

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

module "service_principals" {
  source = "./modules/databricks_identity/service_principals"

  providers = {
    databricks.mws       = databricks.mws
    databricks.workspace = databricks.created_workspace
  }

  enabled            = local.service_principals_enabled
  workspace_id       = local.workspace_id
  service_principals = local.service_principals

  depends_on = [module.unity_catalog_metastore_assignment]
}
```

Requirements for this step:

- keep the checked-in file safe by default on `main` with `service_principals_enabled = false`
- keep both scope shapes visible in the checked-in example map
- keep stable Terraform keys `uat_promotion` and `workspace_agent`
- do not add outputs, grants, roles, or secrets in the root file

- [ ] **Step 2: Add a short service-principal identity section to the root README**

Update `infra/aws/dbx/databricks/us-west-1/README.md` with a new section that states:

- `service_principals.tf` is the root catalog for Terraform-managed Databricks service principals
- the checked-in example demonstrates one account-scoped principal and one workspace-scoped principal
- the file is intentionally disabled by default on `main`
- replace the example display names with real service principal names before setting `service_principals_enabled = true`
- this layer manages only principal creation, optional workspace assignment, and workspace entitlements
- credentials, Unity Catalog grants, warehouse permissions, group membership, and account roles remain outside this file

Use wording consistent with `ARCHITECTURE.md` and `docs/superpowers/specs/2026-03-13-service-principals-design.md`.

- [ ] **Step 3: Re-run root validation with the safe checked-in defaults**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected:

- formatting succeeds
- validation succeeds
- the checked-in `service_principals.tf` is safe because the module is disabled by default

### Task 6: Smoke-Test The Happy Path, Restore The Safe Default, And Finish Verification

**Files:**
- Modify temporarily: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`

- [ ] **Step 1: Temporarily enable the mixed-scope example map for a smoke plan**

Change only this line in `infra/aws/dbx/databricks/us-west-1/service_principals.tf`:

```hcl
  service_principals_enabled = true
```

- [ ] **Step 2: Run the full root verification flow against scenario 1**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals init -backend=false
terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals validate
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- module validation succeeds
- root validation succeeds
- the plan shows two `databricks_service_principal` resources
- the plan shows one `databricks_mws_permission_assignment` for `uat_promotion`
- the plan shows two `databricks_entitlements` resources
- the plan does not contain `databricks_service_principal_secret`
- the plan does not contain Unity Catalog grants, warehouse ACLs, roles, or membership resources from this new module

- [ ] **Step 3: Restore the safe checked-in default after the smoke plan**

Change only this line back:

```hcl
  service_principals_enabled = false
```

- [ ] **Step 4: Re-run root validation after restoring the checked-in safe default**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- validation still succeeds
- the checked-in `main` branch state is safe because `service_principals_enabled = false`
- the root plan no longer includes service principal creation, workspace assignment, or entitlements until an operator explicitly enables the catalog

- [ ] **Step 5: Commit the integrated root caller and docs after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/service_principals.tf infra/aws/dbx/databricks/us-west-1/README.md infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals
git commit -m "feat(identity): add mixed scope service principal catalog"
```

Expected: one final commit containing the new module, the root caller, and the operator docs with the safe checked-in default restored.
