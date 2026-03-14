# Service Principal Unity Catalog Access Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional root-level Unity Catalog access metadata for Terraform-managed service principals and derive governed catalog, schema, and managed-volume grants from that metadata without changing the service-principals child module interface.

**Architecture:** Keep `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals` focused on identity lifecycle only. Normalize `unity_catalog_access` intent in `infra/aws/dbx/databricks/us-west-1/service_principals.tf`, resolve catalog targeting plus catalog `USE_CATALOG` grants in `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`, and resolve schema plus managed-volume defaults in `infra/aws/dbx/databricks/us-west-1/schema_config.tf` using service-principal application IDs and explicit `depends_on = [module.service_principals]` ordering.

**Tech Stack:** Terraform `~> 1.3`, Databricks provider `~> 1.84`, aliased providers `databricks.mws` and `databricks.created_workspace`, `direnv`, `DATABRICKS_AUTH_TYPE=oauth-m2m`, Markdown docs

---

**Spec:** `docs/superpowers/specs/2026-03-14-service-principal-unity-catalog-access-design.md`

**Required Context:**
- `ARCHITECTURE.md`
- `docs/design-docs/unity-catalog.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/SPEC.md`

**Execution Notes:**
- Use `@subagent-driven-development` to execute the tasks.
- Use `@test-driven-development` before each behavioral Terraform change, even when the “test” is a failing `terraform validate` or `terraform plan`.
- Use `@verification-before-completion` before claiming success.
- Use `@requesting-code-review` after the final verification pass.
- Keep the scope to Unity Catalog plus workspace-assignment ordering. Do not widen `modules/databricks_identity/service_principals`, and do not add secrets, account roles, group membership, warehouse ACL changes, or table/view grants.
- Preserve the existing `uat_promotion` key in `service_principals.tf`; `sql_warehouses.tf` already references `module.service_principals.application_ids["uat_promotion"]`.
- Do not model the future architecture-specific `uat_promotion` or `release` Unity Catalog write patterns with this generic `reader` / `writer` rollout. Keep those roles identity-only in checked-in config.
- Use the repo-standard root verification command shape for real-root runs: `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 <plan|apply> -var-file=scenario1.premium-existing.tfvars`
- Scratch-copy verification in this plan intentionally reuses the same `plan -var-file=scenario1.premium-existing.tfvars` shape against a disposable copy of the root module.
- Do not execute any `git commit` step until the user has approved this plan for implementation.

## File Structure

Modify these root entrypoints:

- `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- `infra/aws/dbx/databricks/us-west-1/README.md`

Reference these existing files while implementing, but do not change them unless a later review uncovers a real defect:

- `ARCHITECTURE.md`
- `docs/design-docs/unity-catalog.md`
- `docs/superpowers/specs/2026-03-14-service-principal-unity-catalog-access-design.md`
- `infra/aws/dbx/databricks/us-west-1/catalog_schema_config.tf`
- `infra/aws/dbx/databricks/us-west-1/catalog_types_config.tf`
- `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/SPEC.md`

Responsibilities:

- `service_principals.tf`: operator-authored service-principal catalog, root-only `unity_catalog_access` metadata, identity-only child-module input, and root validation for supported access shapes.
- `catalogs_config.tf`: resolve enabled governed catalog targets, validate catalog selectors against governed keys, merge service-principal application IDs into catalog reader principals, and extend catalog dependency ordering.
- `schema_config.tf`: derive service-principal reader and writer principals per governed catalog, add schema and managed-volume defaults, preserve override semantics, and extend dependency ordering.
- `README.md`: explain how operators declare `unity_catalog_access`, what values are supported, where grants are actually owned, and how explicit overrides replace derived defaults.

## Chunk 1: Root Metadata And Validation

### Task 1: Normalize Service Principal Unity Catalog Intent In The Root Caller

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_identity/service_principals/variables.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/sql_warehouses.tf`

- [ ] **Step 1: Extend the checked-in root examples with commented Unity Catalog access shapes**

Keep the active checked-in principals (`uat_promotion` and `workspace_agent`) unchanged as identity-only examples. Add commented examples immediately below them so operators can see the supported metadata shape without making the default plan depend on uncommented governed catalog keys.

Insert this commented example block inside `local.service_principals`:

```hcl
    # catalog_writer = {
    #   display_name    = "Catalog Writer SP"
    #   principal_scope = "account"
    #   workspace_assignment = {
    #     enabled     = true
    #     permissions = ["USER"]
    #   }
    #   entitlements = {
    #     databricks_sql_access = true
    #   }
    #   unity_catalog_access = {
    #     permission_level = "writer"
    #     catalogs         = "all"
    #   }
    # }
    #
    # reporting_reader = {
    #   display_name    = "Reporting Reader SP"
    #   principal_scope = "workspace"
    #   entitlements = {
    #     workspace_access = true
    #   }
    #   unity_catalog_access = {
    #     permission_level = "reader"
    #     catalogs         = ["salesforce_revenue"]
    #   }
    # }
```

Expected: the checked-in file demonstrates both supported access levels and both catalog-selector modes without attaching this generic grant model to `uat_promotion`.

- [ ] **Step 2: Derive an identity-only map and a normalized root-only Unity Catalog access map**

Add these locals beneath `local.service_principals` and switch the module input to the identity-only map:

```hcl
  service_principals_identity = {
    for principal_key, principal in local.service_principals :
    principal_key => {
      display_name         = principal.display_name
      principal_scope      = principal.principal_scope
      workspace_assignment = try(principal.workspace_assignment, null)
      entitlements         = try(principal.entitlements, null)
    }
  }

  service_principal_unity_catalog_access = !local.service_principals_enabled ? {} : {
    for principal_key, principal in local.service_principals :
    principal_key => {
      principal_scope               = principal.principal_scope
      workspace_assignment_enabled  = coalesce(try(principal.workspace_assignment.enabled, null), false)
      permission_level              = lower(trimspace(try(principal.unity_catalog_access.permission_level, "")))
      catalogs_all                  = try(principal.unity_catalog_access.catalogs, null) == "all"
      catalogs_is_string_list       = try(principal.unity_catalog_access.catalogs, null) != null && can(tolist(principal.unity_catalog_access.catalogs)) && can([
        for catalog_key in tolist(principal.unity_catalog_access.catalogs) :
        trimspace(catalog_key)
      ])
      explicit_catalog_keys         = try(principal.unity_catalog_access.catalogs, null) != null && can(tolist(principal.unity_catalog_access.catalogs)) && can([
        for catalog_key in tolist(principal.unity_catalog_access.catalogs) :
        trimspace(catalog_key)
      ]) ? [
        for catalog_key in tolist(principal.unity_catalog_access.catalogs) :
        trimspace(catalog_key)
      ] : []
    }
    if try(principal.unity_catalog_access, null) != null
  }
```

Then change the module call from:

```hcl
  service_principals = local.service_principals
```

to:

```hcl
  service_principals = local.service_principals_identity
```

Expected: the child module still receives exactly its approved identity-only contract, while the root retains all Unity Catalog metadata for downstream grant derivation.

- [ ] **Step 3: Add root checks for supported access levels, selector shapes, blank keys, duplicates, and workspace assignment prerequisites**

Add these `check` blocks in `service_principals.tf` after the module block:

```hcl
check "service_principal_uc_permission_levels" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      contains(["reader", "writer"], access.permission_level)
    ])
    error_message = "service_principals[*].unity_catalog_access.permission_level must be reader or writer."
  }
}

check "service_principal_uc_catalog_selectors" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.catalogs_all || access.catalogs_is_string_list
    ])
    error_message = "service_principals[*].unity_catalog_access.catalogs must be \"all\" or a list of catalog keys."
  }
}

check "service_principal_uc_catalog_keys_nonempty" {
  assert {
    condition = alltrue(flatten([
      for access in values(local.service_principal_unity_catalog_access) : [
        for catalog_key in access.catalogs_all ? [] : access.explicit_catalog_keys :
        catalog_key != ""
      ]
    ]))
    error_message = "service_principals[*].unity_catalog_access.catalogs list entries must be non-empty."
  }
}

check "service_principal_uc_catalog_key_lists_nonempty" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.catalogs_all || length(access.explicit_catalog_keys) > 0
    ])
    error_message = "service_principals[*].unity_catalog_access.catalogs list must contain at least one catalog key."
  }
}

check "service_principal_uc_catalog_keys_unique" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.catalogs_all || length(access.explicit_catalog_keys) == length(distinct(access.explicit_catalog_keys))
    ])
    error_message = "service_principals[*].unity_catalog_access.catalogs list entries must be unique."
  }
}

check "service_principal_uc_account_scope_workspace_assignment" {
  assert {
    condition = alltrue([
      for access in values(local.service_principal_unity_catalog_access) :
      access.principal_scope != "account" || access.workspace_assignment_enabled
    ])
    error_message = "Account-scoped service principals with unity_catalog_access must enable workspace_assignment."
  }
}
```

Expected: invalid permission levels, invalid selector shapes, empty catalog lists, blank catalog keys, duplicate catalog keys, and account-scoped principals without workspace assignment now fail at root validation time.

- [ ] **Step 4: Format and verify the root still validates in the checked-in disabled state**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 init
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected:

- `service_principals.tf` is formatted cleanly
- root validation succeeds
- the new Unity Catalog checks stay inert while `local.service_principals_enabled = false`

- [ ] **Step 5: Commit the root metadata change after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/service_principals.tf
git commit -m "feat(uc): normalize service principal access intent"
```

Expected: one commit containing only the root caller metadata and validation changes.

## Chunk 2: Catalog And Schema Grant Fan-Out

### Task 2: Resolve Catalog Targets And Merge Catalog-Level `USE_CATALOG` Principals

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/main.tf`

- [ ] **Step 1: Prove the current root is still missing catalog-level service-principal grants**

Run:

```bash
scratch_dir="$(mktemp -d /tmp/service-principal-uc-catalog-red.XXXXXX)"
rsync -a --exclude='.terraform/' --exclude='.terraform.lock.hcl' --exclude='*.tfstate*' --exclude='crash.log' infra/aws/dbx/databricks/us-west-1/ "${scratch_dir}/"
terraform -chdir="${scratch_dir}" init -backend=false
```

Then make these exact temporary edits in the scratch copy:

- in `${scratch_dir}/service_principals.tf`, change `service_principals_enabled = false` to `service_principals_enabled = true`
- in `${scratch_dir}/service_principals.tf`, uncomment the exact `catalog_writer` and `reporting_reader` examples from Task 1
- in `${scratch_dir}/catalogs_config.tf`, uncomment the checked-in `salesforce_revenue` and `hubspot_shared` examples under `local.governed_catalog_domains`

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
rm -rf "${scratch_dir}"
```

Expected:

- the scratch-root plan succeeds
- `module.governed_catalogs["salesforce_revenue"].databricks_grants.workspace_catalog[0]` shows only the admin grant block
- `module.governed_catalogs["hubspot_shared"].databricks_grants.workspace_catalog[0]` shows only the admin grant block
- this is the red test proving catalog-level service-principal `USE_CATALOG` grants are not wired yet

- [ ] **Step 2: Derive enabled governed catalog keys and service-principal catalog targets without introducing a local cycle**

Add these locals to `catalogs_config.tf` after `local.derived_governed_catalog_names` and before `local.derived_governed_catalogs`:

```hcl
  enabled_governed_catalog_keys = [
    for catalog_key, domain in local.normalized_governed_catalog_domains :
    catalog_key
    if domain.enabled && (domain.catalog_kind == "" || domain.catalog_kind == "governed")
  ]

  service_principal_catalog_targets = {
    for principal_key, access in local.service_principal_unity_catalog_access :
    principal_key => access.catalogs_all ? local.enabled_governed_catalog_keys : access.explicit_catalog_keys
  }

  service_principal_catalog_use_catalog_application_ids = {
    for catalog_key in local.enabled_governed_catalog_keys :
    catalog_key => [
      for principal_key, access in local.service_principal_unity_catalog_access :
      module.service_principals.application_ids[principal_key]
      if contains(local.service_principal_catalog_targets[principal_key], catalog_key)
    ]
  }
```

Expected: catalog targeting is resolved only after the governed catalog set is known, and the root now has a stable per-catalog list of service-principal application IDs for catalog grants.

- [ ] **Step 3: Add root checks for `personal` exclusions and unknown governed catalog keys**

Add these `check` blocks in `catalogs_config.tf`:

```hcl
check "service_principal_uc_catalog_keys_exclude_personal" {
  assert {
    condition = alltrue(flatten([
      for access in values(local.service_principal_unity_catalog_access) : [
        for catalog_key in access.catalogs_all ? [] : access.explicit_catalog_keys :
        catalog_key != "personal"
      ]
    ]))
    error_message = "service_principals[*].unity_catalog_access.catalogs must not target the personal catalog."
  }
}

check "service_principal_uc_catalog_keys_known" {
  assert {
    condition = alltrue(flatten([
      for access in values(local.service_principal_unity_catalog_access) : [
        for catalog_key in access.catalogs_all ? [] : access.explicit_catalog_keys :
        contains(local.enabled_governed_catalog_keys, catalog_key)
      ]
    ]))
    error_message = "service_principals[*].unity_catalog_access.catalogs entries must reference enabled governed catalog keys."
  }
}
```

Expected: explicit `personal` targets and explicit non-governed or disabled catalog keys fail clearly before apply.

- [ ] **Step 4: Merge service-principal application IDs into the governed catalog reader principal list**

Replace the `catalog_reader_principals` expression in `local.derived_governed_catalogs` with:

```hcl
      catalog_reader_principals = concat(
        [
          for group_key in domain.reader_group :
          try(local.identity_groups[group_key].display_name, "")
        ],
        try(local.service_principal_catalog_use_catalog_application_ids[catalog_key], [])
      )
```

Keep the rest of the object unchanged.

Expected:

- group-driven behavior remains intact
- service-principal readers and writers both receive catalog `USE_CATALOG`
- catalog grants keep using a flat principal list so the child module interface stays unchanged

- [ ] **Step 5: Extend the root dependency contract so catalog grants wait for workspace assignment**

Add `module.service_principals` to the existing `depends_on` list in `module "governed_catalogs"`:

```hcl
  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.service_principals,
  ]
```

Expected: account-scoped service principals are fully assigned to the workspace before Unity Catalog catalog grants are attempted.

- [ ] **Step 6: Format and verify the catalog entrypoint after the merge**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt catalogs_config.tf
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Then recreate the enabled scratch scenario:

```bash
scratch_dir="$(mktemp -d /tmp/service-principal-uc-catalog-green.XXXXXX)"
rsync -a --exclude='.terraform/' --exclude='.terraform.lock.hcl' --exclude='*.tfstate*' --exclude='crash.log' infra/aws/dbx/databricks/us-west-1/ "${scratch_dir}/"
terraform -chdir="${scratch_dir}" init -backend=false
```

Apply the same temporary edits as in Step 1:

- in `${scratch_dir}/service_principals.tf`, set `service_principals_enabled = true`
- in `${scratch_dir}/service_principals.tf`, uncomment `catalog_writer` and `reporting_reader`
- in `${scratch_dir}/catalogs_config.tf`, uncomment `salesforce_revenue` and `hubspot_shared`

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
rm -rf "${scratch_dir}"
```

Expected:

- `catalogs_config.tf` formats cleanly
- root validation still succeeds with the checked-in disabled service-principal path
- the enabled scratch-root plan now shows three grant blocks in `module.governed_catalogs["salesforce_revenue"].databricks_grants.workspace_catalog[0]`: admin plus two service-principal `USE_CATALOG` grants
- the enabled scratch-root plan now shows two grant blocks in `module.governed_catalogs["hubspot_shared"].databricks_grants.workspace_catalog[0]`: admin plus one writer `USE_CATALOG` grant

- [ ] **Step 7: Commit the catalog grant fan-out change after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/catalogs_config.tf
git commit -m "feat(uc): derive service principal catalog grants"
```

Expected: one commit containing only the catalog-target resolution, validation, dependency-ordering, and catalog grant fan-out change.

### Task 3: Derive Schema And Managed-Volume Defaults For Service Principal Readers And Writers

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/catalog_schema_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_schemas/main.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_volumes/main.tf`

- [ ] **Step 1: Prove the current root still gives service-principal writers only reader-level schema and volume defaults**

Run:

```bash
scratch_dir="$(mktemp -d /tmp/service-principal-uc-schema-red.XXXXXX)"
rsync -a --exclude='.terraform/' --exclude='.terraform.lock.hcl' --exclude='*.tfstate*' --exclude='crash.log' infra/aws/dbx/databricks/us-west-1/ "${scratch_dir}/"
terraform -chdir="${scratch_dir}" init -backend=false
```

Then make these exact temporary edits in the scratch copy:

- in `${scratch_dir}/service_principals.tf`, set `service_principals_enabled = true`
- in `${scratch_dir}/service_principals.tf`, uncomment `catalog_writer` and `reporting_reader`
- in `${scratch_dir}/catalogs_config.tf`, uncomment `salesforce_revenue` and `hubspot_shared`

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
rm -rf "${scratch_dir}"
```

Expected:

- the scratch-root plan succeeds
- `module.unity_catalog_schemas.databricks_grants.schema["salesforce_revenue:raw"]` shows the service-principal writer grant only with `USE_SCHEMA`, not `ALL_PRIVILEGES`
- `module.unity_catalog_volumes.databricks_grants.volume["salesforce_revenue:final:model_artifacts"]` shows the service-principal writer grant only with `READ_VOLUME`, not `READ_VOLUME` plus `WRITE_VOLUME`
- this is the red test proving schema and managed-volume defaults still treat service-principal writers like readers

- [ ] **Step 2: Derive group readers, service-principal readers, and service-principal writers per governed catalog**

Add these locals near the top of `schema_config.tf`, before `local.effective_governed_schema_config`:

```hcl
  governed_catalog_group_reader_principals = {
    for catalog_key, catalog in local.governed_catalogs_for_schemas :
    catalog_key => [
      for group_key in catalog.reader_group :
      local.identity_groups[group_key].display_name
    ]
  }

  governed_catalog_service_principal_readers = {
    for catalog_key in keys(local.governed_catalogs_for_schemas) :
    catalog_key => [
      for principal_key, access in local.service_principal_unity_catalog_access :
      module.service_principals.application_ids[principal_key]
      if access.permission_level == "reader" && contains(local.service_principal_catalog_targets[principal_key], catalog_key)
    ]
  }

  governed_catalog_service_principal_writers = {
    for catalog_key in keys(local.governed_catalogs_for_schemas) :
    catalog_key => [
      for principal_key, access in local.service_principal_unity_catalog_access :
      module.service_principals.application_ids[principal_key]
      if access.permission_level == "writer" && contains(local.service_principal_catalog_targets[principal_key], catalog_key)
    ]
  }

  governed_catalog_schema_reader_principals = {
    for catalog_key in keys(local.governed_catalogs_for_schemas) :
    catalog_key => concat(
      try(local.governed_catalog_group_reader_principals[catalog_key], []),
      try(local.governed_catalog_service_principal_readers[catalog_key], [])
    )
  }
```

Expected: schema and volume defaults can distinguish service-principal readers from writers even though catalog-level grants treat both as catalog readers.

- [ ] **Step 3: Extend default schema grants so readers receive `USE_SCHEMA` and writers receive `ALL_PRIVILEGES`**

Replace the derived default `grants` expression inside `local.governed_schemas` with:

```hcl
            grants = try(schema.grants, null) != null ? schema.grants : concat(
              [
                {
                  principal  = catalog.catalog_admin_principal
                  privileges = ["ALL_PRIVILEGES"]
                }
              ],
              [
                for principal in local.governed_catalog_schema_reader_principals[catalog_key] : {
                  principal  = principal
                  privileges = ["USE_SCHEMA"]
                }
              ],
              [
                for principal in local.governed_catalog_service_principal_writers[catalog_key] : {
                  principal  = principal
                  privileges = ["ALL_PRIVILEGES"]
                }
              ]
            )
```

Expected:

- existing reader groups still inherit `USE_SCHEMA`
- service-principal readers also inherit `USE_SCHEMA`
- service-principal writers inherit `ALL_PRIVILEGES`
- explicit schema `grants` continue to replace this whole derived list

- [ ] **Step 4: Extend default managed-volume grants so readers receive `READ_VOLUME` and writers receive `READ_VOLUME` plus `WRITE_VOLUME`**

Replace the derived default `grants` expression inside `local.governed_managed_volumes` with:

```hcl
              grants = try(volume.grants, null) != null ? volume.grants : concat(
                [
                  {
                    principal  = catalog.catalog_admin_principal
                    privileges = ["ALL_PRIVILEGES"]
                  }
                ],
                [
                  for principal in local.governed_catalog_schema_reader_principals[catalog_key] : {
                    principal  = principal
                    privileges = ["READ_VOLUME"]
                  }
                ],
                [
                  for principal in local.governed_catalog_service_principal_writers[catalog_key] : {
                    principal  = principal
                    privileges = ["READ_VOLUME", "WRITE_VOLUME"]
                  }
                ]
              )
```

Expected:

- service-principal readers inherit the same `READ_VOLUME` default as reader groups
- service-principal writers inherit `READ_VOLUME` plus `WRITE_VOLUME`
- explicit volume `grants` continue to replace the entire derived list

- [ ] **Step 5: Extend schema and volume dependency ordering to wait for service-principal workspace assignment**

Add `module.service_principals` to both root `depends_on` lists:

```hcl
  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.governed_catalogs,
    module.service_principals,
  ]
```

for `module "unity_catalog_schemas"`, and:

```hcl
  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.governed_catalogs,
    module.unity_catalog_schemas,
    module.service_principals,
  ]
```

for `module "unity_catalog_volumes"`.

Expected: schema and volume grants wait on the same workspace-assignment prerequisite as catalog grants.

- [ ] **Step 6: Format and verify the schema entrypoint after the new defaults**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt schema_config.tf
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Then recreate the enabled scratch scenario:

```bash
scratch_dir="$(mktemp -d /tmp/service-principal-uc-schema-green.XXXXXX)"
rsync -a --exclude='.terraform/' --exclude='.terraform.lock.hcl' --exclude='*.tfstate*' --exclude='crash.log' infra/aws/dbx/databricks/us-west-1/ "${scratch_dir}/"
terraform -chdir="${scratch_dir}" init -backend=false
```

Apply the same temporary edits as in Step 1:

- in `${scratch_dir}/service_principals.tf`, set `service_principals_enabled = true`
- in `${scratch_dir}/service_principals.tf`, uncomment `catalog_writer` and `reporting_reader`
- in `${scratch_dir}/catalogs_config.tf`, uncomment `salesforce_revenue` and `hubspot_shared`

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
rm -rf "${scratch_dir}"
```

Expected:

- `schema_config.tf` formats cleanly
- root validation still succeeds in the checked-in disabled state
- `module.unity_catalog_schemas.databricks_grants.schema["salesforce_revenue:raw"]` now shows `ALL_PRIVILEGES` for the writer path and `USE_SCHEMA` for the reader path
- `module.unity_catalog_schemas.databricks_grants.schema["hubspot_shared:raw"]` now shows the admin grant plus the writer service-principal grant
- `module.unity_catalog_volumes.databricks_grants.volume["salesforce_revenue:final:model_artifacts"]` now shows `READ_VOLUME` for the reader path and `READ_VOLUME` plus `WRITE_VOLUME` for the writer path

- [ ] **Step 7: Commit the schema and volume default change after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/schema_config.tf
git commit -m "feat(uc): derive service principal schema and volume grants"
```

Expected: one commit containing only the schema and managed-volume derivation plus dependency-ordering changes.

## Chunk 3: Operator Docs And Verification

### Task 4: Update Operator Documentation For Root-Level Service Principal Unity Catalog Access

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`
- Reference: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/schema_config.tf`

- [ ] **Step 1: Expand the `Service Principal Identity Catalog` section with the new root metadata contract**

Add these bullets beneath the existing `service_principals.tf` section:

```md
- Each service principal may optionally declare `unity_catalog_access` in `service_principals.tf`.
- `unity_catalog_access.permission_level` supports only `reader` and `writer`.
- `unity_catalog_access.catalogs` supports either `"all"` or an explicit list of enabled governed catalog keys such as `salesforce_revenue`.
- `unity_catalog_access.catalogs = "all"` means enabled governed catalogs only and explicitly excludes `personal`.
- Explicit `unity_catalog_access.catalogs` lists must not contain `personal`.
- Account-scoped service principals with `unity_catalog_access` must also enable `workspace_assignment`.
- The child module still manages only service principal creation, optional workspace assignment, and workspace entitlements.
```

Expected: operators can discover the new metadata shape directly from the root README without assuming the child module now owns Unity Catalog grants.

- [ ] **Step 2: Expand the governed catalog and schema sections so grant ownership stays explicit**

Add these bullets in the `Governed Catalog Creation` and `Governed Unity Catalog Schemas And Managed Volumes` sections:

```md
- Catalog-level `USE_CATALOG` grants are still derived in `catalogs_config.tf`.
- Service-principal Unity Catalog grants use `module.service_principals.application_ids`, not display names.
- Schema defaults in `schema_config.tf` grant `USE_SCHEMA` to reader groups plus service-principal readers and `ALL_PRIVILEGES` to service-principal writers.
- Managed-volume defaults in `schema_config.tf` grant `READ_VOLUME` to readers and `READ_VOLUME` plus `WRITE_VOLUME` to writers.
- This rollout still does not manage table, view, function, model, or schema-object `SELECT` privileges.
- Explicit schema or managed-volume `grants` remain authoritative replacements, so operators must re-declare any service-principal access they still want when overriding defaults.
```

Expected: the README makes the ownership boundary explicit and warns operators about the replacement semantics on explicit overrides.

- [ ] **Step 3: Format the Markdown section manually and re-read the edited README**

Run:

```bash
sed -n '30,220p' infra/aws/dbx/databricks/us-west-1/README.md
```

Expected: the new bullets sit beside the existing service-principal and Unity Catalog sections, do not duplicate the module spec, and clearly separate identity provisioning from Unity Catalog grant ownership.

- [ ] **Step 4: Commit the README update after user approval to execute**

Run:

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs(uc): document service principal access metadata"
```

Expected: one commit containing only the operator-facing documentation update.

### Task 5: Run Root Success-Path And Negative-Path Verification

**Files:**
- Reference: `infra/aws/dbx/databricks/us-west-1/service_principals.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/schema_config.tf`
- Reference: `infra/aws/dbx/databricks/us-west-1/scenario1.premium-existing.tfvars`

- [ ] **Step 1: Run formatting, init, validation, and the checked-in disabled plan**

Run:

```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 init
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars
```

Expected:

- formatting produces no remaining diffs
- root validation succeeds
- the default checked-in plan still succeeds with `local.service_principals_enabled = false`
- the checked-in plan does not propose Unity Catalog grants derived from commented example metadata

- [ ] **Step 2: Exercise the enabled success path in a disposable scratch copy**

Run:

```bash
scratch_dir="$(mktemp -d /tmp/service-principal-uc-root.XXXXXX)"
rsync -a --exclude='.terraform/' --exclude='.terraform.lock.hcl' --exclude='*.tfstate*' --exclude='crash.log' infra/aws/dbx/databricks/us-west-1/ "${scratch_dir}/"
terraform -chdir="${scratch_dir}" init -backend=false
```

Then make these exact temporary edits in the scratch copy:

In `${scratch_dir}/service_principals.tf`:

- change `service_principals_enabled = false` to `service_principals_enabled = true`
- uncomment the exact `catalog_writer` and `reporting_reader` examples added in Task 1

In `${scratch_dir}/catalogs_config.tf`, uncomment exactly these governed catalog examples:

```hcl
    salesforce_revenue = {
      enabled             = true
      display_name        = "Salesforce Revenue"
      source              = "salesforce"
      business_area       = "revenue"
      catalog_type        = "standard_governed"
      catalog_admin_group = "platform_admins"
      reader_group        = []
      managed_volume_overrides = {
        final = {
          model_artifacts = {
            name = "model_artifacts"
          }
        }
      }
    }

    hubspot_shared = {
      enabled             = true
      display_name        = "HubSpot Shared"
      source              = "hubspot"
      business_area       = ""
      catalog_type        = "standard_governed"
      catalog_admin_group = "platform_admins"
      reader_group        = []
    }
```

Run:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir="${scratch_dir}" plan -var-file=scenario1.premium-existing.tfvars
awk 'BEGIN{depth=0;seen=0} /module "governed_catalogs"/{seen=1} seen{print; depth+=gsub(/\{/,"{"); depth-=gsub(/\}/,"}"); if (seen && depth==0) exit}' "${scratch_dir}/catalogs_config.tf"
awk 'BEGIN{depth=0;seen=0} /module "unity_catalog_schemas"/{seen=1} seen{print; depth+=gsub(/\{/,"{"); depth-=gsub(/\}/,"}"); if (seen && depth==0) exit}' "${scratch_dir}/schema_config.tf"
awk 'BEGIN{depth=0;seen=0} /module "unity_catalog_volumes"/{seen=1} seen{print; depth+=gsub(/\{/,"{"); depth-=gsub(/\}/,"}"); if (seen && depth==0) exit}' "${scratch_dir}/schema_config.tf"
```

Expected:

- the scratch-root plan succeeds
- `module.service_principals` plans `catalog_writer` and `reporting_reader` in addition to the checked-in identity-only examples
- the three printed module blocks each show `module.service_principals` inside their `depends_on` lists
- `module.governed_catalogs["salesforce_revenue"].databricks_grants.workspace_catalog[0]` shows three grant blocks: one admin grant plus two service-principal `USE_CATALOG` grants whose principals are still unknown until apply
- `module.governed_catalogs["hubspot_shared"].databricks_grants.workspace_catalog[0]` shows two grant blocks: one admin grant plus one service-principal `USE_CATALOG` grant for the writer path
- `module.governed_catalogs["personal"].databricks_grants.workspace_catalog[0]` remains admin-only, with no derived service-principal `USE_CATALOG` grant from `catalog_writer.catalogs = "all"`
- `module.unity_catalog_schemas.databricks_grants.schema["salesforce_revenue:raw"]` shows admin, reader, and writer grant blocks, with the service-principal principals still unknown until apply
- `module.unity_catalog_schemas.databricks_grants.schema["hubspot_shared:raw"]` shows admin plus writer grant blocks and no extra reader grant block
- `module.unity_catalog_volumes.databricks_grants.volume["salesforce_revenue:final:model_artifacts"]` shows admin, reader, and writer grant blocks, with the writer block carrying both `READ_VOLUME` and `WRITE_VOLUME`

- [ ] **Step 3: Run the negative-path matrix in the same scratch copy**

Test these one at a time. Revert the previous invalid edit before running the next one, and rerun the same scratch `terraform plan` command after each edit:

- In `${scratch_dir}/service_principals.tf`, change `catalog_writer` to `permission_level = "admin"`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.permission_level must be reader or writer.`
- In `${scratch_dir}/service_principals.tf`, change `catalog_writer` to `catalogs = "salesforce_revenue"`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs must be "all" or a list of catalog keys.`
- In `${scratch_dir}/service_principals.tf`, change `reporting_reader` to `catalogs = { bad = "salesforce_revenue" }`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs must be "all" or a list of catalog keys.`
- In `${scratch_dir}/service_principals.tf`, change `reporting_reader` to `catalogs = [123]`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs must be "all" or a list of catalog keys.`
- In `${scratch_dir}/service_principals.tf`, change `reporting_reader` to `catalogs = []`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs list must contain at least one catalog key.`
- In `${scratch_dir}/service_principals.tf`, change `reporting_reader` to `catalogs = ["salesforce_revenue", ""]`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs list entries must be non-empty.`
- In `${scratch_dir}/service_principals.tf`, change `reporting_reader` to `catalogs = ["salesforce_revenue", "salesforce_revenue"]`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs list entries must be unique.`
- In `${scratch_dir}/service_principals.tf`, change `reporting_reader` to `catalogs = ["personal"]`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs must not target the personal catalog.`
- In `${scratch_dir}/service_principals.tf`, change `reporting_reader` to `catalogs = ["missing_catalog"]`.
  Expected: FAIL with `service_principals[*].unity_catalog_access.catalogs entries must reference enabled governed catalog keys.`
- In `${scratch_dir}/service_principals.tf`, change `catalog_writer.workspace_assignment.enabled = true` to `false`.
  Expected: FAIL with `Account-scoped service principals with unity_catalog_access must enable workspace_assignment.`

- [ ] **Step 4: Clean up the disposable scratch copy**

Run:

```bash
rm -rf "${scratch_dir}"
```

Expected: the temporary caller-backed verification copy is removed after both the success path and negative-path matrix have been exercised.

- [ ] **Step 5: Capture the verification evidence in the execution notes**

Record these facts in the final implementation response to the user in this session:

- `terraform validate` succeeded in the real root
- the checked-in disabled root plan succeeded
- the scratch-copy code inspection confirmed `module.service_principals` appears in all three required `depends_on` lists
- the scratch enabled root plan showed catalog, schema, and managed-volume grants for service-principal readers and writers
- the negative-path cases that were exercised and their failure messages

Expected: the final user-facing execution summary is concrete enough for a reviewer to confirm the implementation matches the spec without re-deriving what was tested.
