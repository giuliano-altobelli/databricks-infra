# Sandbox Workspace Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a branch-local sandbox deployment workflow in `infra/aws/dbx/databricks/us-west-1` that creates a second Databricks workspace on the shared account and shared metastore, uses dedicated Terraform state, and creates only sandbox-owned Terraform-managed Databricks objects.

**Architecture:** Keep the existing root stack and existing `workspace_source = "create"` path. Add a dedicated local-backend configuration plus a dedicated sandbox var file, then hard-code sandbox-prefixed names in the root configuration catalogs that currently create or describe Databricks objects outside the `resource_prefix`-derived AWS path. Add Terraform `check` guardrails so a sandbox run fails early if it drifts back toward shared `main` naming, `uc_catalog_mode = "existing"`, or account-admin identity roles.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider `~> 1.84`, AWS provider `>= 5.76, <7.0`, `direnv`, `DATABRICKS_AUTH_TYPE=oauth-m2m`, `rg`, Markdown docs

---

**Spec:** `docs/superpowers/specs/2026-03-18-sandbox-workspace-design.md`

**Execution Notes:**
- Use `@subagent-driven-development` to execute the tasks.
- Use `@test-driven-development` before each behavioral Terraform change, even when the “test” is a failing `terraform validate`, `terraform state list`, or `terraform plan`.
- Use `@verification-before-completion` before claiming success.
- Use `@requesting-code-review` after the final verification pass.
- Do not invoke `@brainstorming`; the design and scope are already fixed by the approved spec.
- Before implementation starts, explicitly confirm the required access scope if the human has not already done so: this change spans Unity Catalog, workspace-level resources, and limited account-level resources needed for workspace creation, metastore assignment, identity lookup, and optional account-scoped service principals. Do not proceed on a looser or different scope assumption.
- Keep the implementation root-focused. Do not introduce a new environment abstraction, naming framework, provider fan-out model, or module rewrite.
- Keep `scenario1.premium-existing.tfvars`, `scenario2.premium-create-managed.tfvars`, and `scenario3.enterprise-create-isolated.tfvars` intact as the existing reference scenarios. Add a new sandbox file based on scenario 2 instead of repurposing the existing files.
- The sandbox branch must remain Premium plus managed networking. Do not route this plan through scenario 3 or Enterprise/SRA networking.
- Terraform commands in this repo must run outside the sandbox. Use the repo-standard command shape with `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 ...`.
- The repo `.gitignore` ignores `*.tfvars`, so the new sandbox var file must be committed with `git add -f`.
- If a full workspace `apply` and `destroy` cannot be executed in the session, do not claim the lifecycle success criteria are complete. Report the exact verification gap.
- Do not execute any `git commit` step until the user has approved this plan for implementation.

## File Structure

Create these sandbox workflow files:

- `infra/aws/dbx/databricks/us-west-1/backend.tf`
- `infra/aws/dbx/databricks/us-west-1/sandbox.local.tfbackend`
- `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars`
- `infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf`

Modify these root configuration catalogs:

- `infra/aws/dbx/databricks/us-west-1/identify.tf`
- `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`
- `infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf`
- `infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf`
- `infra/aws/dbx/databricks/us-west-1/README.md`

Reference these existing files during implementation, but do not change them unless validation uncovers a real defect:

- `AGENTS.md`
- `ARCHITECTURE.md`
- `docs/superpowers/specs/2026-03-18-sandbox-workspace-design.md`
- `infra/aws/dbx/databricks/us-west-1/provider.tf`
- `infra/aws/dbx/databricks/us-west-1/locals.tf`
- `infra/aws/dbx/databricks/us-west-1/main.tf`
- `infra/aws/dbx/databricks/us-west-1/catalog_schema_config.tf`
- `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- `infra/aws/dbx/databricks/us-west-1/outputs.tf`
- `infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/users_groups/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/cluster_policy/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/sql_warehouses/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations/SPEC.md`

Responsibilities:

- `backend.tf`: declare the explicit local backend so `terraform init -backend-config=...` can select a dedicated sandbox state path.
- `sandbox.local.tfbackend`: make the sandbox state location explicit and repeatable.
- `scenario2.sandbox-create-managed.tfvars`: pin the sandbox branch to Premium, create-workspace, managed networking, metastore reuse, isolated Unity Catalog mode, and a sandbox-specific `resource_prefix`.
- `sandbox_validations.tf`: fail fast when the branch drifts away from sandbox invariants or back toward `main`-style names and roles.
- `identify.tf`: reuse the same SCIM users by email while renaming Terraform-managed groups to sandbox-specific display names and removing account-wide roles.
- `catalogs_config.tf`: make all enabled governed catalog names and display names explicitly sandbox-prefixed instead of relying on production naming derivation.
- `service_principals.tf`: keep optional service-principal examples safe-by-default with sandbox-prefixed display names.
- `sql_warehouses.tf`: keep optional warehouse examples safe-by-default with sandbox-prefixed names and sandbox-oriented tags.
- `cluster_policy_config.tf`: rename the active cluster policy to a sandbox-prefixed Databricks display name.
- `storage_credential_config.tf`: keep optional storage credential and external location examples sandbox-prefixed so future enablement stays branch-safe.
- `README.md`: document the only supported sandbox init, validate, plan, apply, destroy, and manual review workflow.

## Chunk 1: Sandbox State And Entry Points

### Task 1: Add The Dedicated Sandbox Backend And Var File

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/backend.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/sandbox.local.tfbackend`
- Create: `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars`
- Reference: `infra/aws/dbx/databricks/us-west-1/scenario2.premium-create-managed.tfvars`

- [ ] **Step 1: Add an explicit local backend block**

Write `infra/aws/dbx/databricks/us-west-1/backend.tf` with exactly:

```hcl
terraform {
  backend "local" {}
}
```

- [ ] **Step 2: Create the dedicated sandbox backend config**

Write `infra/aws/dbx/databricks/us-west-1/sandbox.local.tfbackend` with exactly:

```hcl
path = "sandbox.terraform.tfstate"
```

- [ ] **Step 3: Create the sandbox scenario file from scenario 2**

Write `infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars` with these values:

```hcl
# Sandbox branch: Premium tier, create workspace, managed networking
aws_account_id        = "441735166692"
region                = "us-west-2"
admin_user            = "giulianoaltobelli@gmail.com"
databricks_account_id = "535f803e-200e-4ff7-985a-7673a0f53375"
resource_prefix       = "sandbox-infra"

pricing_tier            = "PREMIUM"
workspace_source        = "create"
existing_workspace_host = null
existing_workspace_id   = null
network_configuration   = "managed"

uc_catalog_mode          = "isolated"
uc_existing_catalog_name = "sandbox_do_not_use"
metastore_exists         = true

enable_audit_log_delivery          = false
audit_log_delivery_exists          = false
enable_example_cluster             = false
enable_security_analysis_tool      = false
enable_compliance_security_profile = false
compliance_standards               = ["Standard_A", "Standard_B"]

deployment_name      = null
databricks_gov_shard = null
```

- [ ] **Step 4: Format the new files**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt backend.tf
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt
```

Expected: Terraform reports the new files formatted and does not touch unrelated files outside the root module.

- [ ] **Step 5: Reinitialize Terraform against the sandbox backend**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=sandbox.local.tfbackend
```

Expected: `terraform init` succeeds and reports the local backend reconfigured to the sandbox state path rather than silently reusing `terraform.tfstate`.

- [ ] **Step 6: Prove the sandbox state is empty before the first apply**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
```

Expected: no output. If any resources appear here before the first sandbox apply, stop immediately because the backend points at the wrong state.

- [ ] **Step 7: Commit the backend and scenario scaffold after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/backend.tf
git add infra/aws/dbx/databricks/us-west-1/sandbox.local.tfbackend
git add -f infra/aws/dbx/databricks/us-west-1/scenario2.sandbox-create-managed.tfvars
git commit -m "feat(sandbox): add dedicated sandbox state workflow"
```

Expected: one commit containing only the new backend and sandbox scenario entrypoint files.

## Chunk 2: Fail-Fast Sandbox Guardrails

### Task 2: Add Validation Checks That Intentionally Fail Against The Current Root Names

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/identify.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf`

- [ ] **Step 1: Add the sandbox invariant checks before renaming anything**

Write `infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf` with this content:

```hcl
locals {
  sandbox_group_display_names = [for group in values(local.identity_groups) : group.display_name]
  sandbox_group_roles         = flatten([for group in values(local.identity_groups) : try(group.roles, [])])

  sandbox_enabled_catalog_domains = [
    for domain in values(local.normalized_governed_catalog_domains) : domain
    if domain.enabled
  ]

  sandbox_service_principal_names = [
    for principal in values(local.service_principals_identity) : principal.display_name
  ]

  sandbox_sql_warehouse_names = [
    for warehouse in values(local.sql_warehouses) : warehouse.name
  ]

  sandbox_cluster_policy_names = [
    for policy in values(local.cluster_policies) : policy.name
  ]

  sandbox_storage_credential_names = [
    for credential in values(local.uc_storage_credentials) : credential.name
  ]

  sandbox_external_location_names = [
    for location in values(local.uc_external_locations) : location.name
  ]
}

check "sandbox_run_shape" {
  assert {
    condition = (
      var.resource_prefix == "sandbox-infra" &&
      var.pricing_tier == "PREMIUM" &&
      local.create_workspace &&
      var.network_configuration == "managed" &&
      var.metastore_exists &&
      local.effective_uc_catalog_mode == "isolated" &&
      var.existing_workspace_host == null &&
      var.existing_workspace_id == null
    )
    error_message = "Sandbox runs must use sandbox-infra, PREMIUM, workspace_source=create, managed networking, metastore_exists=true, uc_catalog_mode=isolated, and null existing workspace values."
  }
}

check "sandbox_groups_prefixed" {
  assert {
    condition     = alltrue([for name in local.sandbox_group_display_names : startswith(name, "Sandbox ")])
    error_message = "All Terraform-managed sandbox group display names must start with \"Sandbox \"."
  }
}

check "sandbox_groups_no_account_roles" {
  assert {
    condition     = alltrue([for role in local.sandbox_group_roles : role != "account_admin"])
    error_message = "Sandbox-managed groups must not grant account-wide roles such as account_admin."
  }
}

check "sandbox_catalogs_explicit_and_prefixed" {
  assert {
    condition = alltrue([
      for domain in local.sandbox_enabled_catalog_domains :
      domain.catalog_name != "" &&
      startswith(domain.catalog_name, "sandbox_") &&
      domain.display_name != "" &&
      startswith(domain.display_name, "Sandbox ")
    ])
    error_message = "Enabled sandbox catalogs must set explicit sandbox-prefixed catalog_name and display_name values."
  }
}

check "sandbox_service_principals_prefixed" {
  assert {
    condition     = alltrue([for name in local.sandbox_service_principal_names : startswith(name, "Sandbox ")])
    error_message = "Sandbox service principal display names must start with \"Sandbox \"."
  }
}

check "sandbox_sql_warehouses_prefixed" {
  assert {
    condition     = alltrue([for name in local.sandbox_sql_warehouse_names : startswith(name, "Sandbox ")])
    error_message = "Sandbox SQL warehouse names must start with \"Sandbox \"."
  }
}

check "sandbox_cluster_policies_prefixed" {
  assert {
    condition     = alltrue([for name in local.sandbox_cluster_policy_names : startswith(name, "Sandbox ")])
    error_message = "Sandbox cluster policy names must start with \"Sandbox \"."
  }
}

check "sandbox_storage_credentials_prefixed" {
  assert {
    condition     = alltrue([for name in local.sandbox_storage_credential_names : startswith(name, "sandbox-")])
    error_message = "Sandbox storage credential names must start with \"sandbox-\"."
  }
}

check "sandbox_external_locations_prefixed" {
  assert {
    condition     = alltrue([for name in local.sandbox_external_location_names : startswith(name, "sandbox-")])
    error_message = "Sandbox external location names must start with \"sandbox-\"."
  }
}
```

- [ ] **Step 2: Run a sandbox scenario plan and confirm the checks fail before the rename work**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected: FAIL with one or more of the new sandbox check errors, including the current non-sandbox group, catalog, and cluster policy names or the current `account_admin` role.

- [ ] **Step 3: Commit the check scaffold only after the subsequent fixes make it pass**

Run later, after Tasks 3 and 4 pass:

```bash
git add infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf
git commit -m "feat(sandbox): add sandbox invariant guardrails"
```

Expected: do not create this commit until the root catalog changes satisfy the checks.

## Chunk 3: Rename Sandbox-Owned Databricks Objects

### Task 3: Update Active Identity And Catalog Configuration To Sandbox-Owned Names

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/identify.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`

- [ ] **Step 1: Replace the active identity group with a sandbox-specific display name and no account role**

Change the active `local.identity_groups` block in `infra/aws/dbx/databricks/us-west-1/identify.tf` to:

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

Important: remove `roles = ["account_admin"]` entirely instead of leaving it behind as an empty-but-confusing field.

- [ ] **Step 2: Make the active personal catalog explicitly sandbox-prefixed**

Replace the active `personal` entry in `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf` with:

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

- [ ] **Step 3: Update the commented governed catalog examples so future enablement stays sandbox-safe**

Rewrite the commented examples in `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf` so they use explicit sandbox names, for example:

```hcl
# salesforce_revenue = {
#   enabled             = true
#   display_name        = "Sandbox Salesforce Revenue"
#   catalog_name        = "sandbox_salesforce_revenue"
#   source              = "salesforce"
#   business_area       = "revenue"
#   catalog_type        = "standard_governed"
#   catalog_admin_group = "platform_admins"
#   reader_group        = []
#   managed_volume_overrides = {
#     final = {
#       model_artifacts = {
#         name = "model_artifacts"
#       }
#     }
#   }
# }
# main = {
#   enabled             = true
#   display_name        = "Sandbox Main"
#   catalog_name        = "sandbox_main"
#   source              = "main"
#   business_area       = ""
#   catalog_type        = "main_empty"
#   catalog_admin_group = "platform_admins"
#   reader_group        = []
# }
```

Important: do not leave any enabled or example governed catalog depending on the `prod_<source>...` derivation path in this branch.

- [ ] **Step 4: Format the active identity and catalog files**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt identify.tf
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt catalogs_config.tf
```

Expected: both files format cleanly.

- [ ] **Step 5: Re-run the sandbox scenario plan and confirm only the remaining non-sandbox root catalogs still fail**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected: the earlier group-role and personal-catalog failures are gone, but the plan may still fail on service principal, SQL warehouse, or cluster policy names until Task 4 is complete.

- [ ] **Step 6: Commit the identity and active catalog rename after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/identify.tf
git add infra/aws/dbx/databricks/us-west-1/catalogs_config.tf
git commit -m "feat(sandbox): isolate sandbox identity and catalog names"
```

Expected: one commit containing only the active identity and catalog configuration changes.

### Task 4: Update Active And Optional Workspace Objects To Sandbox-Safe Names

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf`

- [ ] **Step 1: Rename the checked-in service principal examples**

In `infra/aws/dbx/databricks/us-west-1/service_principals.tf`, update the example display names to:

```hcl
service_principals = {
  uat_promotion = {
    display_name    = "Sandbox UAT Promotion SP"
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
    display_name    = "Sandbox Workspace Agent SP"
    principal_scope = "workspace"
    entitlements = {
      workspace_access = true
    }
  }
}
```

Keep `local.service_principals_enabled = false`; this task is about branch-safe naming, not enabling the module.

- [ ] **Step 2: Rename the SQL warehouse example and make its tags explicitly sandbox-oriented**

In `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`, update the warehouse example to:

```hcl
sql_warehouses = {
  analytics_ci = {
    name                      = "Sandbox Analytics CI Warehouse"
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
      Environment = "sandbox"
      Owner       = "data-platform"
    }
    permissions = concat(
      [
        {
          principal_type   = "group"
          principal_name   = local.identity_groups.platform_admins.display_name
          permission_level = "CAN_MANAGE"
        }
      ],
      local.service_principals_enabled ? [
        {
          principal_type   = "service_principal"
          principal_name   = module.service_principals.application_ids["uat_promotion"]
          permission_level = "CAN_USE"
        }
      ] : []
    )
  }
}
```

Keep `local.sql_warehouses_enabled = false`.

- [ ] **Step 3: Rename the active cluster policy**

In `infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf`, update the active policy name to:

```hcl
cluster_policies = {
  bundle_dlt_job = {
    name        = "Sandbox Bundle DLT Job Policy"
    description = "Used by Databricks Asset Bundles for DLT job clusters."
    definition  = jsonencode({
      cluster_type = {
        type   = "fixed"
        value  = "dlt"
        hidden = true
      }
      num_workers = {
        type         = "unlimited"
        defaultValue = 3
        isOptional   = true
      }
      node_type_id = {
        type       = "unlimited"
        isOptional = true
      }
      spark_version = {
        type   = "unlimited"
        hidden = true
      }
    })
    permissions = [
      {
        principal_type   = "group"
        principal_name   = local.identity_groups.platform_admins.display_name
        permission_level = "CAN_USE"
      }
    ]
  }
}
```

- [ ] **Step 4: Rewrite the storage credential and external location examples with sandbox-prefixed names**

In `infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf`, update the commented examples so the first storage credential and external location examples read like:

```hcl
# bronze_raw = {
#   name            = "sandbox-bronze-raw-storage-credential"
#   role_arn        = "arn:aws:iam::123456789012:role/databricks-sandbox-bronze-raw"
#   comment         = "Sandbox storage credential for the bronze raw landing bucket."
#   owner           = "account users"
#   skip_validation = true
#   workspace_ids   = ["1234567890123456"]
#   grants = [
#     {
#       principal  = "Sandbox Platform Admins"
#       privileges = ["CREATE_EXTERNAL_LOCATION"]
#     }
#   ]
# }
#
# bronze_raw_root = {
#   name           = "sandbox-bronze-raw-root"
#   url            = "s3://company-sandbox-bronze-raw/"
#   credential_key = "bronze_raw"
#   comment        = "Sandbox root prefix for bronze raw datasets."
#   workspace_ids  = ["1234567890123456"]
#   grants = [
#     {
#       principal  = "Sandbox Platform Admins"
#       privileges = ["CREATE_EXTERNAL_TABLE"]
#     }
#   ]
# }
```

Repeat that same naming rule for the other commented examples in the file: every storage credential and external location example in this branch should start with `sandbox-`.

- [ ] **Step 5: Format the renamed root catalogs**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt service_principals.tf
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt sql_warehouses.tf
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt cluster_policy_config.tf
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt storage_credential_config.tf
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt sandbox_validations.tf
```

Expected: all renamed files format cleanly.

- [ ] **Step 6: Re-run the sandbox scenario plan and confirm the full sandbox guardrail set now passes**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected: a successful create-only plan with no sandbox guardrail failures.

- [ ] **Step 7: Commit the remaining sandbox naming updates after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/service_principals.tf
git add infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf
git add infra/aws/dbx/databricks/us-west-1/cluster_policy_config.tf
git add infra/aws/dbx/databricks/us-west-1/storage_credential_config.tf
git add infra/aws/dbx/databricks/us-west-1/sandbox_validations.tf
git commit -m "feat(sandbox): enforce sandbox-owned databricks naming"
```

Expected: one commit containing the remaining naming changes and the now-passing sandbox validation checks.

## Chunk 4: Operator Workflow And Lifecycle Verification

### Task 5: Document The Only Supported Sandbox Workflow In The Root README

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

- [ ] **Step 1: Add a dedicated sandbox section near the top of the README**

Add a new section titled `## Sandbox Workspace Workflow` near the top of `infra/aws/dbx/databricks/us-west-1/README.md` with this exact command sequence:

````md
## Sandbox Workspace Workflow

This branch creates a second Databricks workspace on the shared account and shared metastore. The only intentionally shared prerequisites are:

- the Databricks account
- the existing Unity Catalog metastore
- the existing Okta SCIM-provisioned users

Everything else created by Terraform in this branch must be sandbox-owned.

Initialize Terraform against the dedicated sandbox state:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=sandbox.local.tfbackend
```

Before the first apply, confirm the sandbox state is empty:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
```

Validate and create the sandbox plan:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars -out=sandbox-create.tfplan
```

Reject the plan if this command prints anything:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 show -no-color sandbox-create.tfplan | rg 'will be updated in-place|must be replaced|will be destroyed'
```

Apply only after manual review confirms the plan creates a new workspace and sandbox-prefixed duplicates only:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply sandbox-create.tfplan
```

After apply, confirm the sandbox stack is converged:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Create and inspect the destroy plan using the same backend config and the same var file:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -destroy -var-file=scenario2.sandbox-create-managed.tfvars -out=sandbox-destroy.tfplan
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 show -no-color sandbox-destroy.tfplan | rg 'will be created|will be updated in-place|must be replaced'
```

Apply the destroy plan only after review confirms that it targets sandbox-owned resources only:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply sandbox-destroy.tfplan
```
````

- [ ] **Step 2: Add an explicit reject checklist under that section**

Immediately after the command block, add this flat checklist:

```md
Reject the sandbox run immediately if any of the following are true:

- `terraform state list` shows existing `main` resources before the first sandbox apply
- the create plan includes any update, replace, or destroy action
- the create plan references shared names such as `Platform Admins`, `personal`, or unprefixed workspace object names
- the run is not using `scenario2.sandbox-create-managed.tfvars`
- the run is not initialized with `sandbox.local.tfbackend`
- the run attempts to use `uc_catalog_mode = "existing"` or account-wide roles
```

- [ ] **Step 3: Re-read the new README section in place**

Run:

```bash
rg -n 'Sandbox Workspace Workflow|scenario2.sandbox-create-managed.tfvars|sandbox.local.tfbackend|Reject the sandbox run immediately' infra/aws/dbx/databricks/us-west-1/README.md
```

Expected: all four anchors appear in the README.

- [ ] **Step 4: Commit the README workflow update after implementation approval**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs(sandbox): add sandbox workspace lifecycle workflow"
```

Expected: one docs-only commit containing the operator workflow and rejection rules.

### Task 6: Run End-To-End Verification Against The Sandbox State And Sandbox Var File

**Files:**
- Verify only: `infra/aws/dbx/databricks/us-west-1`

- [ ] **Step 1: Run a repo-wide Terraform format pass**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
```

Expected: no unexpected rewrites outside the files touched in this plan.

- [ ] **Step 2: Reinitialize explicitly against the sandbox backend**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 init -reconfigure -backend-config=sandbox.local.tfbackend
```

Expected: backend initialization succeeds.

- [ ] **Step 3: Reconfirm the sandbox state is empty before the first create apply**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
```

Expected: no output before the first sandbox create apply.

- [ ] **Step 4: Validate the root module with the sandbox var file**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: PASS.

- [ ] **Step 5: Produce the create plan**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars -out=sandbox-create.tfplan
```

Expected: a successful plan that creates the sandbox workspace and sandbox-owned resources.

- [ ] **Step 6: Reject non-create actions in the create plan**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 show -no-color sandbox-create.tfplan | rg 'will be updated in-place|must be replaced|will be destroyed'
```

Expected: no output.

- [ ] **Step 7: Manually inspect the create plan for sandbox-owned names only**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 show -no-color sandbox-create.tfplan
```

Expected manual confirmations:

- a new workspace is being created
- the metastore assignment targets that new workspace
- active Databricks display names are sandbox-prefixed, including `Sandbox Platform Admins`, `Sandbox Bundle DLT Job Policy`, and `sandbox_personal`
- there are no plan entries mutating the existing `main` workspace or `main`-owned Databricks objects

- [ ] **Step 8: Apply the create plan if real lifecycle verification is allowed**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply sandbox-create.tfplan
```

Expected: sandbox workspace creation succeeds. If this step is skipped for safety or access reasons, stop here and report that full lifecycle verification remains incomplete.

- [ ] **Step 9: Confirm the applied sandbox stack is converged**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars
```

Expected: `No changes. Your infrastructure matches the configuration.`

- [ ] **Step 10: Produce the destroy plan from the same sandbox state**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -destroy -var-file=scenario2.sandbox-create-managed.tfvars -out=sandbox-destroy.tfplan
```

Expected: a successful destroy plan targeting the applied sandbox stack.

- [ ] **Step 11: Reject non-destroy actions in the destroy plan**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 show -no-color sandbox-destroy.tfplan | rg 'will be created|will be updated in-place|must be replaced'
```

Expected: no output.

- [ ] **Step 12: Apply the destroy plan if lifecycle teardown is allowed**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply sandbox-destroy.tfplan
```

Expected: the sandbox workspace and sandbox-owned resources are removed.

- [ ] **Step 13: Confirm the sandbox state is empty again after destroy**

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state list
```

Expected: no output.

- [ ] **Step 14: Review the full diff before handing off**

Run:

```bash
git diff --stat
git diff -- infra/aws/dbx/databricks/us-west-1
git diff -- docs/superpowers/plans/2026-03-18-sandbox-workspace.md
```

Expected: the diff is limited to the files named in this plan plus the plan document itself.
