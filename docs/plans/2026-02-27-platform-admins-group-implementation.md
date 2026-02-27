# Platform Admins Group Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Configure `platform_admins` with `account_admin` role and a single member (`giulianoaltobelli@gmail.com`) to validate account/workspace/Unity Catalog identity flows, and add optional `force` support for module-managed users.

**Architecture:** Identity intent remains centralized in `identify.tf` locals and flows into `module.users_groups` with aliased providers (`databricks.mws` + workspace provider). The module creates account/workspace resources, while Unity Catalog grants remain root-managed through `databricks_grant`. We keep bootstrap admin resources in place for this validation pass to minimize risk.

**Tech Stack:** Terraform (~>1.3), Databricks Terraform Provider (`databricks/databricks ~> 1.84`), direnv scenario tfvars workflow.

---

### Task 1: Add `force` support in `users_groups` module input

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/variables.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/FACTS.md`

**Step 1: Write the failing validation scenario (schema gap check)**

Create a temporary scratch config that passes `users = { giuliano = { user_name = "giulianoaltobelli@gmail.com", force = true } }` to this module and run validate.

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected before change: validation/type error that `force` is not an expected attribute for `users` object.

**Step 2: Add minimal variable schema change**

Add optional `force` in the `users` object type:

```hcl
force = optional(bool)
```

Place it next to existing user properties (`user_name`, `display_name`, `active`, etc.).

**Step 3: Re-run validation**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected after change: no schema error related to `users[*].force`.

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/variables.tf
git commit -m "feat(users_groups): add optional force attribute for users"
```

### Task 2: Wire `force` to Databricks user resources

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/main.tf`
- Test/verify via: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Write the failing behavior expectation**

Document expected behavior: when `users[*].force` is set, it must be passed to both user resources (`databricks_user.users` and `databricks_user.users_protected`) so behavior is consistent regardless of `prevent_destroy` mode.

Run a plan with no implementation to capture current behavior baseline:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: any provider behavior requiring `force` cannot be configured from module input.

**Step 2: Write minimal implementation**

Add `force = each.value.force` to:

- `resource "databricks_user" "users"`
- `resource "databricks_user" "users_protected"`

**Step 3: Run formatting + validate**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: formatting clean and validation succeeds.

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/main.tf
git commit -m "feat(users_groups): pass optional force to databricks_user resources"
```

### Task 3: Configure `platform_admins` and single user membership in root identity locals

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/identify.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/main.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/uc_existing_catalog.tf`

**Step 1: Write the failing expectation (current empty locals)**

Current state keeps `identity_groups`/`identity_users` empty, so module validation target is not met.

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected before change: no module-managed `platform_admins` membership path present (or errors due to group grant reference mismatch if present).

**Step 2: Add minimal identity definitions**

In `local.identity_groups` add:

```hcl
platform_admins = {
  display_name          = "Platform Admins"
  roles                 = ["account_admin"]
  workspace_permissions = ["ADMIN"]
  entitlements = {
    allow_cluster_create  = true
    databricks_sql_access = true
    workspace_access      = true
  }
}
```

In `local.identity_users` add one user:

```hcl
giuliano = {
  user_name = "giulianoaltobelli@gmail.com"
  force     = true
  groups    = ["platform_admins"]
}
```

Keep `unity_catalog_group_catalog_privileges.platform_admins = ["ALL_PRIVILEGES"]`.

**Step 3: Run plan with scenario 1**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- `platform_admins` group created/managed
- `account_admin` group role attachment
- membership linking `giuliano` user to `platform_admins`
- workspace assignment/entitlement resources for module-managed identities
- UC group grant for `platform_admins`

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/identify.tf
git commit -m "feat(identity): configure platform_admins and giuliano membership"
```

### Task 4: Update module docs for `force` usage

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/README.md`

**Step 1: Write the failing doc expectation**

The README explains plain group vs account-admin group but does not yet explain `users[*].force` behavior.

**Step 2: Add minimal docs**

Add a short note in README that:

- `users[*].force` is optional
- use it when Terraform must manage/reconcile pre-existing Databricks users
- if omitted, provider default behavior applies

Include it in at least one usage snippet.

**Step 3: Verify formatting/readability**

Run:
```bash
sed -n '1,260p' infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/README.md
```

Expected: docs clearly distinguish group role modes and `force` behavior.

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups/README.md
git commit -m "docs(users_groups): document optional user force behavior"
```

### Task 5: Final verification and apply readiness

**Files:**
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Run full local checks**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: clean formatting and successful validation.

**Step 2: Run scenario 1 plan (required repo pattern)**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: changes align to accepted scope (account + workspace + UC) and no enterprise/SRA-only resources are introduced.

**Step 3: Optional apply (only after plan review)**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply -var-file=scenario1.premium-existing.tfvars
```

Expected: successful creation/update of group, membership, role, assignments, entitlements, and UC grant.

**Step 4: Commit any final cleanups**

```bash
git add infra/aws/dbx/databricks/us-west-1
git commit -m "chore: finalize platform_admins validation configuration"
```
