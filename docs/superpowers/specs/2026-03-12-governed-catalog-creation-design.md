# Governed Catalog Creation Design

Date: 2026-03-12

## Summary

Add a new config-driven Terraform path for creating multiple workspace-isolated Unity Catalog catalogs backed by per-catalog AWS storage bootstrap.

The new path should derive governed catalog names from structured domain inputs and, when that governed domain input set is non-empty, implicitly add a `personal` catalog in the same rollout. When `local.governed_catalog_domains = {}`, the new path is a true no-op and does not create `personal` by itself. The existing single isolated-catalog path remains available for backward compatibility. This session stops at catalog creation plus AWS-backed storage. Schema creation is intentionally deferred to a later session.

## Scope

In scope:

- New root entrypoint: `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- Reuse and refactor `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation`
- Multi-catalog root orchestration using `for_each`
- Per-catalog AWS bootstrap:
  - S3 bucket
  - KMS key and alias
  - IAM role and policy
  - Databricks storage credential
  - Databricks external location
- Workspace-scoped catalog creation and explicit workspace bindings
- Optional additional isolated workspace bindings through `workspace_ids`
- Catalog admin grant to the existing `Platform Admins` identity group
- Outputs that make created catalogs and backing resources easy to reference later
- Module and root validation requirements
- Backward-compatible coexistence with the existing isolated-catalog path

Out of scope:

- Catalog schemas such as `raw`, `base`, `staging`, `final`, `uat`, or `personal.<user_key>`
- Unity Catalog table, volume, schema, or grant orchestration beyond the catalog admin grant
- New account-level identity provisioning behavior
- Replacing or deleting the legacy isolated-catalog path in this change
- Open/shared catalog visibility modes
- Non-commented default multi-workspace examples in the checked-in root config

## Context

This repository already has two newer Unity Catalog modules that set the current repo direction:

- `modules/databricks_workspace/unity_catalog_storage_locations`
- `modules/databricks_workspace/unity_catalog_volumes`

Those modules are workspace-scoped, config-driven from root locals, and explicit about authoritative grants and workspace bindings. The existing `unity_catalog_catalog_creation` module predates that pattern and currently mixes AWS bootstrap, Databricks resource creation, default namespace changes, and a single-catalog calling model.

The approved design keeps AWS bootstrap ownership inside the catalog module, but refactors that module so it can be reused from a new multi-catalog root config. This avoids duplicating AWS logic while still moving the caller shape toward the newer repo conventions.

This design also resolves the catalog naming rule for governed domains in this workflow:

- if `business_area` is non-empty, render `prod_<source>_<business_area>`
- if `business_area` is empty, render `prod_<source>`

That naming rule is specific to this governed-catalog workflow and should be treated as the governing rule for implementation.

Architecture conflict resolution:

- `ARCHITECTURE.md` currently describes governed catalogs as `prod_<source>_<business_area>`
- `docs/design-docs/unity-catalog.md` also currently describes governed catalogs as `prod_<source>_<business_area>` and recommends a sentinel for missing business area
- this approved design explicitly refines that rule for the governed-catalog workflow by allowing empty `business_area` and rendering `prod_<source>` in that case
- implementation planning for this change must treat this design doc as authoritative for naming
- implementation should include the necessary architecture-doc sync so repo-wide documentation no longer disagrees with the approved naming rule

Because the module also creates AWS resources, the design requires a second derived naming surface for AWS-safe identifiers:

- start from the rendered catalog name
- replace `_` with `-`
- use that AWS-safe suffix when building bucket, IAM, KMS alias, storage credential, and external location names

Recommended bucket pattern:

- `${resource_prefix}-${aws_safe_catalog_suffix}-${workspace_id}`

Examples:

- `prod_salesforce_revenue` -> bucket suffix `prod-salesforce-revenue`
- `prod_hubspot` -> bucket suffix `prod-hubspot`
- `personal` -> bucket suffix `personal`

The implementation should validate that the final AWS-safe identities remain unique after underscore-to-hyphen transformation.

## Recommended Architecture

Use one new root config file and one refactored single-catalog module.

### Root caller

`catalogs_config.tf` becomes the new preferred entrypoint for governed catalog creation.

It should:

- declare the governed catalog domain list as structured local data
- derive rendered catalog names from validated caller tokens
- implicitly add the `personal` catalog
- invoke `unity_catalog_catalog_creation` once per derived catalog using `for_each`
- pass the workspace-scoped `databricks.created_workspace` provider alias
- use the baseline root dependency contract `depends_on = [module.unity_catalog_metastore_assignment, module.users_groups]`

### Single-catalog module

`unity_catalog_catalog_creation` remains a single-catalog unit with one clear responsibility:

- create one AWS-backed Unity Catalog catalog and its directly required supporting resources

That module should own:

- one S3 bucket
- one KMS key and alias
- one IAM role and policy
- one Databricks storage credential
- one Databricks external location
- one Databricks catalog
- explicit workspace bindings for isolated securables
- one authoritative catalog admin grant

This preserves a clean unit boundary while allowing the root caller to scale to many catalogs through `for_each`.

## Root Configuration Shape

`catalogs_config.tf` should define a local catalog-domain matrix keyed by stable Terraform identifiers.

Recommended caller shape:

- `source` is required and non-empty after trimming
- `source` must already be lowercase snake_case matching `^[a-z0-9_]+$`
- `business_area` is optional and may be empty after trimming
- when non-empty, `business_area` must already be lowercase snake_case matching `^[a-z0-9_]+$`
- `workspace_ids` support is implemented in this change, but checked-in examples should keep it commented out by default
- the stable key `personal` is reserved for the implicit personal catalog and must not be reused by callers

Activation rule:

- `catalogs_config.tf` should default `local.governed_catalog_domains = {}`
- when the map is empty, the new governed-catalog path is a no-op and does not create `personal`
- when the map is non-empty, the root derives governed catalogs plus `personal` and invokes the module for each entry
- because these checks are driven by locals rather than input variables, root-level validation should be implemented with explicit Terraform `check` blocks or equivalent root-level preconditions in `catalogs_config.tf`

Example design shape:

```hcl
locals {
  governed_catalog_domains = {
    salesforce_revenue = {
      source        = "salesforce"
      business_area = "revenue"
      # workspace_ids = ["1234567890123456"] # Optional future shared-metastore visibility
    }
    hubspot_shared = {
      source        = "hubspot"
      business_area = ""
    }
  }
}
```

Derived name rules:

- `salesforce_revenue` renders `prod_salesforce_revenue`
- `hubspot_shared` renders `prod_hubspot`
- `personal` is added implicitly by the root derivation logic and does not need caller input

The stable map keys remain the Terraform addresses. Name derivation should be separate from stable key identity so future display-name changes do not accidentally force broad address churn.

The new path should also derive a second internal map keyed by the same stable identifiers that contains:

- `catalog_name`
- `aws_safe_catalog_suffix`
- `workspace_ids`
- whether the entry is governed or implicit `personal`

The implicit personal catalog must use the stable key `personal`.

## Module Interface

The module should stay focused on a single catalog instance.

### Provider Context

- Providers:
  - `aws` inherited from the root default AWS provider
  - `databricks` wired explicitly as `providers = { databricks = databricks.created_workspace }`
- Databricks provider scope: workspace-level only

The module must not use `databricks.mws`.

### Required inputs

- `aws_account_id`
- `aws_iam_partition`
- `aws_assume_partition`
- `unity_catalog_iam_arn`
- `cmk_admin_arn`
- `resource_prefix`
- `workspace_id`
- `catalog_name`
- `catalog_admin_principal`

### Optional inputs

- `enabled` (`bool`, default `true`)
- `workspace_ids` (`list(string)`, default `[]`)
- `set_default_namespace` (`bool`, default `false`)

### Outputs

Expose deterministic scalar outputs from the single-catalog module. When `enabled = false`, every scalar output should return `null`.

Required outputs:

- `catalog_name`
- `catalog_bucket_name`
- `storage_credential_name`
- `storage_credential_external_id`
- `storage_credential_unity_catalog_iam_arn`
- `external_location_name`
- `iam_role_arn`
- `kms_key_arn`

At the root layer, the new path must expose an aggregated `catalogs` map output keyed by the stable catalog key. When `local.governed_catalog_domains` is empty, `catalogs` must be `{}`.

Each `catalogs` map value must include:

- `catalog_kind` (`governed` or `personal`)
- `catalog_name`
- `catalog_bucket_name`
- `storage_credential_name`
- `storage_credential_external_id`
- `storage_credential_unity_catalog_iam_arn`
- `external_location_name`
- `iam_role_arn`
- `kms_key_arn`

The implicit personal catalog is included in `catalogs` with `catalog_kind = "personal"`.

## Resource Behavior

When `enabled = false`:

- create no resources
- return `null` for every module scalar output
- rely on the root caller to expose `{}` from the aggregated `catalogs` output map when the governed domain matrix is empty

When `enabled = true`:

1. Create the AWS KMS key and alias for the catalog bucket.
2. Create the Databricks storage credential first using the planned IAM role ARN so Databricks emits the `external_id` and `unity_catalog_iam_arn` needed for trust construction.
3. Build the AWS IAM assume-role policy and Unity Catalog access-policy inputs from those trust values.
4. Create the IAM role, IAM policy, and policy attachment.
5. Create the S3 bucket and encryption/public-access settings.
6. Create the Databricks external location for the bucket root.
7. Create the Databricks catalog with workspace-isolated visibility.
8. Create explicit `databricks_workspace_binding` resources for the storage credential, external location, and catalog.
9. Create an authoritative catalog admin grant for the configured `catalog_admin_principal`.
10. Skip default namespace changes unless `set_default_namespace = true`.

The root caller should extend baseline `depends_on` rather than replacing it when later work needs additional prerequisites.

Bootstrap contract for the first apply:

- preserve the current single-apply bootstrap pattern already used by the legacy module
- do not introduce a new caller-facing staged-apply or `skip_validation` toggle in this design
- keep the internal wait/ordering guard between AWS IAM readiness and external location creation
- treat a storage-credential bootstrap failure as an implementation defect to fix against the approved one-pass contract, not as planner discretion to redesign the rollout

## Access And Visibility Model

The new governed-catalog path is explicitly scoped to Unity Catalog plus workspace-level behavior.

Approved access behavior:

- each catalog is isolated to the workspace that creates it
- explicit workspace bindings are created even though the workspace is the creator
- optional extra `workspace_ids` add more isolated bindings on the same metastore and are implemented in this change
- the only catalog-level grant managed in this phase is the admin grant
- the admin principal is the existing `Platform Admins` group defined in `infra/aws/dbx/databricks/us-west-1/identify.tf`
- the workspace default namespace remains unchanged

Future-sharing posture:

- the active rollout should not expose open/shared catalogs by default
- root examples should include commented `workspace_ids` to show how future workspaces on the same metastore could be added later if needed

## Grants Model

Catalog administration should move from the legacy singular `databricks_grant` pattern to authoritative `databricks_grants`, matching the newer repo style.

Approved grant behavior:

- manage one authoritative catalog grant set when the module is enabled
- include the configured `catalog_admin_principal`
- default the new root path to `Platform Admins`
- do not manage schema-level or object-level grants in this session

Implication:

- out-of-band grants on the managed catalog are not preserved if they are not represented in the authoritative grant set

## Validation Rules

The new path should fail fast on bad caller input.

Root-level validation:

- each governed entry must declare non-empty `source`
- `business_area` may be empty
- callers must not use the reserved stable key `personal`
- rendered catalog names must be unique after derivation from trimmed, validated caller input
- AWS-safe catalog suffixes must remain unique after underscore-to-hyphen normalization
- implicit `personal` must not collide with any caller-derived catalog identity
- if the legacy isolated-catalog path is enabled in an existing-workspace flow, none of the derived governed catalog names may equal the legacy isolated catalog name derived from `replace("${resource_prefix}-catalog-${workspace_id}", "-", "_")`
- if the legacy isolated-catalog path is enabled in a create-workspace flow, that same overlap rule may be enforced at apply time once `workspace_id` is known
- if the existing-catalog flow is active, none of the derived governed catalog names may equal `var.uc_existing_catalog_name`
- if the existing-catalog flow is active, the implicit `personal` catalog is also invalid when `var.uc_existing_catalog_name == "personal"`

Module-level validation:

- `catalog_name` must be non-empty when enabled
- `catalog_admin_principal` must be non-empty when enabled
- `workspace_id` must be a non-empty numeric string when enabled
- `workspace_ids` must be non-empty numeric strings when present
- duplicate workspace-binding tuples must fail clearly rather than being silently deduplicated
- the computed S3 bucket name must satisfy S3 naming rules and length limits
- generated AWS and Databricks identifiers must fail early if they exceed provider-specific name limits; this design does not allow silent truncation or hashing

## Failure Modes

Expected runtime failure cases outside static validation:

- Databricks storage credential creation fails unexpectedly despite the approved one-pass bootstrap sequence
- Databricks external location creation fails if bucket or IAM permissions are incomplete
- Catalog creation fails if the metastore assignment is incomplete for the target workspace
- Authoritative grants remove unexpected out-of-band catalog access

Expected caller responsibilities:

- keep stable Terraform keys stable
- use the workspace-scoped Databricks provider alias
- ensure the metastore assignment exists before catalog creation
- keep the legacy isolated path and the new governed path from managing the same catalog names simultaneously

## Backward Compatibility And Migration

The new governed-catalog path should coexist with the legacy isolated-catalog path.

Coexistence rules:

- keep `catalogs_config.tf` defaulted off via an empty `local.governed_catalog_domains` map
- keep the legacy isolated-catalog path in `main.tf`
- update that legacy caller to the refactored module interface while preserving its current activation rule and isolated single-catalog behavior
- when the legacy isolated caller is rewired to the refactored module interface, preserve its current admin-principal behavior by passing the existing bootstrap/admin principal rather than switching that path to `Platform Admins`
- preserve the existing legacy resource names, Terraform addresses, and state shape for that isolated path; the refactor must not require planned forced replacements or state moves for the legacy path
- document the new path as the preferred direction for future governed catalog work
- note clearly that the legacy isolated path is planned for later archival once the new path is proven and adopted
- treat name overlap between the legacy isolated catalog and any new governed catalog as invalid root configuration

Root output contract during coexistence:

- preserve the existing singular root `catalog_name` output behavior for the legacy isolated path or existing-catalog flow
- do not silently repurpose that singular output to mean “first governed catalog”
- add and maintain a new root `catalogs` map output for the new path, returning `{}` when disabled

This keeps current users unblocked while creating a forward path for governed multi-catalog rollout.

## Testing And Verification

Implementation should add a local `SPEC.md` for `unity_catalog_catalog_creation` before code changes are considered complete.

Module verification:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation validate`

Repo formatting:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`

Root verification:

- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario1.premium-existing.tfvars`
- a second root plan that exercises the new governed-catalog path with a minimal non-empty `local.governed_catalog_domains` example while still using a non-enterprise scenario file

Suggested negative-path checks:

- empty `source`
- invalid `source` characters or uppercase letters
- invalid non-empty `business_area` characters or uppercase letters
- caller reuse of the reserved `personal` key
- duplicate rendered catalog names after derivation
- duplicate AWS-safe catalog suffixes after normalization
- overlap with the legacy isolated catalog name when that path is enabled
- overlap with `var.uc_existing_catalog_name` when the existing-catalog flow is active
- implicit `personal` colliding with `var.uc_existing_catalog_name`
- non-numeric workspace IDs
- duplicate workspace-binding tuples
- bootstrap failure behavior when IAM readiness ordering is broken

The approved rollout should use a non-enterprise scenario file and should not rely on enterprise-only SRA behavior.

## Implementation Notes For Planning

Expected files to create or modify:

- `ARCHITECTURE.md`
- `docs/design-docs/unity-catalog.md`
- `infra/aws/dbx/databricks/us-west-1/README.md`
- `infra/aws/dbx/databricks/us-west-1/catalogs_config.tf`
- `infra/aws/dbx/databricks/us-west-1/main.tf`
- `infra/aws/dbx/databricks/us-west-1/outputs.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/SPEC.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/README.md`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/variables.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/main.tf`
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_catalog_creation/outputs.tf`

The implementation plan should preserve a clean separation between:

- root catalog-domain configuration
- single-catalog AWS/bootstrap behavior
- authoritative grant and workspace-binding logic
- backward-compatibility with the legacy isolated path

The follow-on schema session should consume the outputs of this work rather than reintroducing catalog bootstrap logic elsewhere.
