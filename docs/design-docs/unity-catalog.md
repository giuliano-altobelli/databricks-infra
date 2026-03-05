# Unity Catalog Option 1 (Env+Source+Business Area Catalogs) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement Unity Catalog naming + grants for Option 1: `<env>_<source>_<business_area>.<layer>.<object>` to support strict, per-(business area, source) access across large teams, while allowing dev workspace users to read prod objects only when granted access to that domain+source.

**Architecture:** Add a declarative Terraform input describing the `(source, business_area)` catalog matrix per environment. Use the workspace-scoped provider (`databricks.created_workspace`) to create catalogs + `raw/base/staging/final` schemas in the shared metastore, then apply UC grants driven by a map of principals per domain+source. Add workspace bindings once dev/qa/prod workspaces are represented in Terraform so prod catalogs can be bound into dev and access constrained by UC grants.

**Tech Stack:** Terraform (~>1.3), Databricks Terraform Provider (`databricks/databricks ~> 1.84`), direnv scenario tfvars workflow.

---

## What was decided (from `databricks_architecture.md` brainstorming)

- **Workspaces:** 3 workspaces (dev, qa, prod), all assigned to **one shared Unity Catalog metastore**.
- **Namespace convention (Option 1):** `<env>_<source>_<business_area>.<layer>.<object>`.
  - `<source>` is the upstream system/vendor (10s, <100).
  - `<layer>` is exactly: `raw`, `base`, `staging`, `final` (some may be unused).
- **Business area missing:** rare edge case; use a consistent sentinel (recommended: `unassigned`).
- **Multi-business-area edge cases:** acceptable to **duplicate shared objects** into each business area’s namespace (no canonical shared location required initially).
- **Access intent:** access is scoped to `(business_area, source)`; if you have access to that domain+source, you can read all prod layers (`prod_(raw|base|staging|final)`).

## Open questions to confirm before implementation

1. **Scope gate (REQUIRED by repo rules):** Is the initial implementation scope:
   - Unity Catalog only (catalogs/schemas/grants), or
   - Unity Catalog + workspace-level (workspace bindings), or
   - Unity Catalog + account-level (groups/service principals), or
   - A combination of the above?
2. **Dev/qa/prod Terraform shape:** Will dev/qa/prod be managed as:
   - separate Terraform states/directories (recommended), or
   - one Terraform state managing multiple workspaces/providers?
3. **Principal strategy:** Are UC principals (groups/SPs) managed in this repo (Terraform) or pre-existing (Okta/Entra/SCIM) and only referenced by name for grants?

---

### Task 1: Add Option 1 inputs (environment + domain catalog matrix)

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/variables.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/locals.tf`

**Step 1: Add new variables (backwards compatible)**

Add variables with safe defaults so existing scenario tfvars still work:

```hcl
variable "environment" {
  description = "Environment prefix for Option 1 Unity Catalogs (dev|qa|prod). Null disables Option 1 resources."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.environment == null || contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, prod (or null)."
  }
}

variable "uc_option1_domains" {
  description = "List of (source, business_area) pairs used to create Option 1 catalogs."
  type = list(object({
    source        = string
    business_area = string
  }))
  default = []
}

variable "uc_option1_layers" {
  description = "Schemas (layers) to create in each Option 1 catalog."
  type        = list(string)
  default     = ["raw", "base", "staging", "final"]
}
```

Add a cross-variable validation so `environment` is required when `uc_option1_domains` is non-empty:

```hcl
validation {
  condition     = length(var.uc_option1_domains) == 0 || (var.environment != null && trimspace(var.environment) != "")
  error_message = "environment is required when uc_option1_domains is non-empty."
}
```

**Step 2: Add locals to normalize + key domains**

In `locals.tf`, add:

```hcl
locals {
  uc_option1_enabled = var.environment != null && length(var.uc_option1_domains) > 0

  uc_option1_domains_normalized = [
    for d in var.uc_option1_domains : {
      source        = lower(trimspace(d.source))
      business_area = lower(trimspace(d.business_area))
    }
  ]

  # Stable keys for for_each usage: "<source>__<business_area>"
  uc_option1_domains_by_key = {
    for d in local.uc_option1_domains_normalized :
    "${d.source}__${d.business_area}" => d
  }
}
```

**Step 3: Run validate**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: `Success! The configuration is valid.` (or equivalent) and no required-var errors when `uc_option1_domains = []`.

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/variables.tf infra/aws/dbx/databricks/us-west-1/locals.tf
git commit -m "feat(uc): add option1 inputs for domain catalog matrix"
```

---

### Task 2: Create Option 1 catalogs (`<env>_<source>_<business_area>`)

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/uc_option1_catalogs.tf`

**Step 1: Create catalogs (metastore-scoped, created via workspace provider)**

Add:

```hcl
resource "databricks_catalog" "uc_option1_domain" {
  provider = databricks.created_workspace
  for_each = local.uc_option1_enabled ? local.uc_option1_domains_by_key : {}

  name    = replace("${var.environment}_${each.value.source}_${each.value.business_area}", "-", "_")
  comment = "Option 1 catalog for ${var.environment}/${each.value.source}/${each.value.business_area}"

  properties = {
    environment   = var.environment
    source        = each.value.source
    business_area = each.value.business_area
    layout        = "option1"
  }

  depends_on = [module.unity_catalog_metastore_assignment]
}
```

**Step 2: Run plan with a small domain list**

Temporarily set (via tfvars or `-var`) something like:

```hcl
environment = "prod"
uc_option1_domains = [
  { source = "googleads", business_area = "marketing" },
]
```

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: one `databricks_catalog` planned named `prod_googleads_marketing`.

**Step 3: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/uc_option1_catalogs.tf
git commit -m "feat(uc): create option1 catalogs per source+business area"
```

---

### Task 3: Create layer schemas in each Option 1 catalog (`raw/base/staging/final`)

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/uc_option1_catalogs.tf`

**Step 1: Add schema cartesian product locals**

Add locals (in the same file or `locals.tf`):

```hcl
locals {
  uc_option1_domain_layers = flatten([
    for domain_key, d in local.uc_option1_domains_by_key : [
      for layer in var.uc_option1_layers : {
        key        = "${domain_key}__${layer}"
        domain_key = domain_key
        layer      = layer
      }
    ]
  ])

  uc_option1_domain_layers_by_key = {
    for x in local.uc_option1_domain_layers : x.key => x
  }
}
```

**Step 2: Create `databricks_schema` resources**

Add:

```hcl
resource "databricks_schema" "uc_option1_layer" {
  provider = databricks.created_workspace
  for_each = local.uc_option1_enabled ? local.uc_option1_domain_layers_by_key : {}

  catalog_name = databricks_catalog.uc_option1_domain[each.value.domain_key].name
  name         = each.value.layer
  comment      = "Option 1 layer schema ${each.value.layer}"
}
```

**Step 3: Run plan**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: for each domain catalog, 4 schemas are planned by default (`raw/base/staging/final`).

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/uc_option1_catalogs.tf
git commit -m "feat(uc): create option1 layer schemas in each catalog"
```

---

### Task 4: Add UC grants for per-(business area, source) read access across all layers

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/variables.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/uc_option1_grants.tf`

**Step 1: Add a declarative read-access map**

In `variables.tf`:

```hcl
variable "uc_option1_read_principals_by_domain" {
  description = "Map of '<source>__<business_area>' => list of principals granted read access to all layers."
  type        = map(list(string))
  default     = {}
}
```

**Step 2: Add catalog-level grants (`USE_CATALOG`)**

In `uc_option1_grants.tf`:

```hcl
locals {
  uc_option1_catalog_read_grants = flatten([
    for domain_key, principals in var.uc_option1_read_principals_by_domain : [
      for principal in principals : {
        key        = "${domain_key}__${principal}"
        domain_key = domain_key
        principal  = principal
      }
    ]
  ])

  uc_option1_catalog_read_grants_by_key = {
    for g in local.uc_option1_catalog_read_grants : g.key => g
  }
}

resource "databricks_grant" "uc_option1_catalog_read" {
  provider = databricks.created_workspace
  for_each = local.uc_option1_enabled ? local.uc_option1_catalog_read_grants_by_key : {}

  catalog    = databricks_catalog.uc_option1_domain[each.value.domain_key].name
  principal  = each.value.principal
  privileges = ["USE_CATALOG"]
}
```

**Step 3: Add schema-level grants (`USE_SCHEMA` + `SELECT`) for every layer**

```hcl
locals {
  uc_option1_schema_read_grants = flatten([
    for domain_key, principals in var.uc_option1_read_principals_by_domain : [
      for principal in principals : [
        for layer in var.uc_option1_layers : {
          key        = "${domain_key}__${layer}__${principal}"
          domain_key = domain_key
          layer      = layer
          principal  = principal
        }
      ]
    ]
  ])

  uc_option1_schema_read_grants_by_key = {
    for g in local.uc_option1_schema_read_grants : g.key => g
  }
}

resource "databricks_grant" "uc_option1_schema_read" {
  provider = databricks.created_workspace
  for_each = local.uc_option1_enabled ? local.uc_option1_schema_read_grants_by_key : {}

  schema     = databricks_schema.uc_option1_layer["${each.value.domain_key}__${each.value.layer}"].id
  principal  = each.value.principal
  privileges = ["USE_SCHEMA", "SELECT"]
}
```

**Step 4: Run plan**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: grants are planned only for domains present in `uc_option1_read_principals_by_domain`.

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/variables.tf infra/aws/dbx/databricks/us-west-1/uc_option1_grants.tf
git commit -m "feat(uc): add option1 read grants per domain across all layers"
```

---

### Task 5 (Optional): Manage principals (groups/SPs) in Terraform

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/identify.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/users_groups`

**Step 1: Decide principal naming**

Pick a stable naming convention that matches how you want to grant access, for example:

- Domain+source scoped: `UC - <business_area> - <source> - Readers`
- Business-area scoped (less granular): `UC - <business_area> - Readers`

**Step 2: Implement**

If principals are Terraform-managed, add them to `local.identity_groups` and ensure they are assigned to the appropriate workspaces and have `workspace_access` entitlement as needed.

**Step 3: Verify**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: groups are created/managed before UC grants reference them.

---

### Task 6 (Optional, recommended later): Add workspace bindings for dev/qa/prod visibility control

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/provider.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/variables.tf`
- Create: `infra/aws/dbx/databricks/us-west-1/uc_option1_bindings.tf`

**Step 1: Represent the 3 workspaces in Terraform**

Add variables for workspace IDs/hosts (or create the workspaces via Terraform) so Terraform knows:

- prod workspace id + host
- qa workspace id + host
- dev workspace id + host

Add additional `databricks` provider aliases as needed (note: provider aliases must be explicitly wired into modules).

**Step 2: Bind prod catalogs into dev workspace**

Use `databricks_workspace_binding` so dev can “see” prod catalogs, then rely on UC grants from Task 4 to constrain per-(domain,source) access.

**Step 3: Verify**

Run plan and confirm bindings are created only for the intended workspaces.

---

### Task 7: Formatting, validation, and scenario plan

**Files:**
- Verify against: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

**Step 1: Format + validate**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: formatting clean and validation succeeds.

**Step 2: Run scenario 1 plan (required repo pattern)**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected: plan shows only the intended Option 1 catalog/schema/grant changes and no unintended enterprise/SRA-only resources.

**Step 3: Optional apply (only after plan review)**

Run:
```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply -var-file=scenario1.premium-existing.tfvars
```

Expected: catalogs and schemas exist, and grants are applied as declared.

