# Premium Trial Compatibility for `infra/aws/dbx/databricks/us-west-1`

This plan updates the “free-tier compatibility” concept to target a **14‑day Premium trial account**, with a **default workflow that targets an existing workspace**, while preserving the ability to **create new workspaces via Terraform later**.

## Summary
Make the Terraform in `infra/aws/dbx/databricks/us-west-1` usable on a Premium trial by:
- Defaulting to **existing workspace** operations (no workspace creation, no customer-managed VPC/PrivateLink, no CMKs, no restrictive AWS hardening).
- Keeping **Unity Catalog always on**, but defaulting to **use an existing UC catalog** (avoid provisioning UC S3/IAM/KMS during trial).
- Keeping the **enterprise SRA** behavior available behind tier/source gates for future upgrade (create workspace + Enterprise tier).

Scope confirmation (per repo rules): this plan supports **Account-level + Workspace-level + Unity Catalog**.

---

## Public Interface Changes (Terraform Inputs/Outputs)

### New root variables (in `infra/aws/dbx/databricks/us-west-1/variables.tf`)
#### Workspace targeting
- `workspace_source` (string)
  - Allowed: `existing`, `create`
  - Default: `existing`
- `existing_workspace_host` (string, nullable)
  - Required when `workspace_source = "existing"`
- `existing_workspace_id` (string, nullable)
  - Required when `workspace_source = "existing"`

#### Tier / feature gating
- `pricing_tier` (string)
  - Allowed: `PREMIUM`, `ENTERPRISE`
  - Default: `PREMIUM` (trial)

#### Network configuration
- Extend existing `network_configuration` to also allow `managed`:
  - Allowed: `managed`, `isolated`, `custom`
  - Default: `managed` (trial)
  - Meaning of `managed`: Databricks-managed networking (skip customer VPC assets + `databricks_mws_networks`).

#### Unity Catalog (always on)
- `uc_catalog_mode` (string, nullable)
  - Allowed: `existing`, `isolated`
  - Default: `null` (computed):
    - `existing` for Premium-trial + existing-workspace flow
    - `isolated` for Enterprise + create-workspace flow
- `uc_existing_catalog_name` (string)
  - Default: `main`
  - Used when effective `uc_catalog_mode = "existing"`.

#### Trial-safe defaults
- `enable_audit_log_delivery` (bool)
  - Default: `false`
- `enable_example_cluster` (bool)
  - Default: `false`

#### Metastore creation safety
- `metastore_storage_root` (string, nullable)
  - Default: `null`
  - Required when `metastore_exists = false` (so metastore creation is well-defined).

### Root outputs (in `infra/aws/dbx/databricks/us-west-1/outputs.tf`)
- `workspace_host` becomes `local.workspace_host` (works for both existing/create).
- `catalog_name` becomes `local.catalog_name` (works for `existing`/`isolated` UC modes).

---

## Implementation Steps

### 1. Add a single “source of truth” locals file
Add `infra/aws/dbx/databricks/us-west-1/locals.tf` defining:
- Workspace selection:
  - `local.create_workspace = var.workspace_source == "create"`
  - `local.workspace_host = local.create_workspace ? module.databricks_mws_workspace[0].workspace_url : var.existing_workspace_host`
  - `local.workspace_id = local.create_workspace ? module.databricks_mws_workspace[0].workspace_id : var.existing_workspace_id`
- Tier:
  - `local.is_enterprise = var.pricing_tier == "ENTERPRISE"`
- Network:
  - `local.use_managed_network = var.network_configuration == "managed"`
- Derived enables (decision-complete defaults):
  - `local.enable_enterprise_infra = local.is_enterprise && local.create_workspace`
  - `local.enable_customer_managed_network = local.enable_enterprise_infra && !local.use_managed_network`
  - `local.enable_customer_managed_keys = local.enable_enterprise_infra`
  - `local.enable_privatelink = local.enable_customer_managed_network && var.network_configuration == "isolated"`
  - `local.enable_network_policy = local.enable_enterprise_infra`
  - `local.enable_network_connectivity_configuration = local.enable_enterprise_infra`
  - `local.enable_restrictive_root_bucket = local.enable_enterprise_infra`
  - `local.enable_disable_legacy_settings = local.is_enterprise` (OFF in trial; ON in Enterprise)
- Unity Catalog (always on):
  - `local.effective_uc_catalog_mode = var.uc_catalog_mode != null ? var.uc_catalog_mode : (local.enable_enterprise_infra ? "isolated" : "existing")`
  - `local.catalog_name = local.effective_uc_catalog_mode == "isolated" ? module.unity_catalog_catalog_creation[0].catalog_name : var.uc_existing_catalog_name`

### 2. Provider wiring for “existing vs create” workspace
Update `infra/aws/dbx/databricks/us-west-1/provider.tf`:
- Keep `databricks.mws` as-is.
- Change `databricks.created_workspace.host` to `local.workspace_host`.

Note (doc-only): creating a workspace and using it as a provider host in the same apply may require a two-phase apply in some environments; default to `workspace_source="existing"` for the trial.

### 3. Make the workspace-creation module compatible with Premium + managed networking
Update `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/workspace`.

#### 3.1 Module interface changes
Edit `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/workspace/variables.tf`:
- Add:
  - `pricing_tier` (string)
  - `enable_customer_managed_network` (bool)
  - `enable_customer_managed_keys` (bool)
  - `enable_private_access_settings` (bool)
  - `enable_network_policy_attachment` (bool)
  - `enable_ncc_binding` (bool)
- Make these existing vars nullable with `default = null` so the module can be used when features are disabled:
  - `backend_relay`, `backend_rest`, `vpc_id`, `subnet_ids`, `security_group_ids`
  - `managed_services_key`, `managed_services_key_alias`, `workspace_storage_key`, `workspace_storage_key_alias`
  - `network_policy_id`, `network_connectivity_configuration_id`

#### 3.2 Conditional resources + null arguments
Edit `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/workspace/main.tf`:
- Set `databricks_mws_workspaces.workspace.pricing_tier = var.pricing_tier`.
- Guard customer-managed network objects:
  - `databricks_mws_vpc_endpoint.*` and `databricks_mws_networks.this` use `count = var.enable_customer_managed_network ? 1 : 0`.
  - In `databricks_mws_workspaces.workspace`, set `network_id = var.enable_customer_managed_network ? databricks_mws_networks.this[0].network_id : null`.
- Guard CMK objects:
  - `databricks_mws_customer_managed_keys.*` use `count = var.enable_customer_managed_keys ? 1 : 0`.
  - In the workspace resource, set CMK IDs to `null` when disabled.
- Guard PAS:
  - `databricks_mws_private_access_settings.pas` uses `count = var.enable_private_access_settings ? 1 : 0`.
  - In the workspace resource, set `private_access_settings_id` to `null` when disabled.
- Guard attachments:
  - `databricks_workspace_network_option.workspace_assignment` uses `count = var.enable_network_policy_attachment && var.network_policy_id != null ? 1 : 0`.
  - `databricks_mws_ncc_binding.ncc_binding` uses `count = var.enable_ncc_binding && var.network_connectivity_configuration_id != null ? 1 : 0`.

### 4. Gate root modules/resources to match trial vs enterprise behavior
Update `infra/aws/dbx/databricks/us-west-1/main.tf`:
- Workspace creation:
  - `module.databricks_mws_workspace`: `count = local.create_workspace ? 1 : 0`
  - Pass:
    - `pricing_tier = var.pricing_tier`
    - `enable_customer_managed_network = local.enable_customer_managed_network`
    - `enable_customer_managed_keys = local.enable_customer_managed_keys`
    - `enable_private_access_settings = local.enable_enterprise_infra`
    - `enable_network_policy_attachment = local.enable_network_policy`
    - `enable_ncc_binding = local.enable_network_connectivity_configuration`
  - When features are disabled, pass `null` for related args.
- Account-level network/security objects (enterprise only):
  - `module.network_connectivity_configuration`: `count = local.enable_network_connectivity_configuration ? 1 : 0`
  - `module.network_policy`: `count = local.enable_network_policy ? 1 : 0`
- Unity Catalog (always on):
  - Ensure `module.unity_catalog_metastore_creation` and `module.unity_catalog_metastore_assignment` always run.
  - Change metastore assignment to use `workspace_id = local.workspace_id`.
  - Update metastore creation module interface (see step 6) to accept `metastore_storage_root`.
- Workspace-level UC:
  - `module.unity_catalog_catalog_creation`: `count = local.effective_uc_catalog_mode == "isolated" ? 1 : 0`
  - Add a new file `infra/aws/dbx/databricks/us-west-1/uc_existing_catalog.tf` that, when mode is `existing`:
    - Sets default namespace to `var.uc_existing_catalog_name`
    - Grants `var.admin_user` `ALL_PRIVILEGES` on that catalog
- Hardening:
  - `module.restrictive_root_bucket`: `count = local.enable_restrictive_root_bucket ? 1 : 0` and use `workspace_id = local.workspace_id`
  - `module.disable_legacy_settings`: `count = local.enable_disable_legacy_settings ? 1 : 0`
- Audit logs:
  - `module.log_delivery`: `count = (var.enable_audit_log_delivery && !var.audit_log_delivery_exists) ? 1 : 0`
- Cluster example:
  - `module.cluster_configuration`: `count = var.enable_example_cluster ? 1 : 0`

### 5. Make AWS “workspace foundation” resources conditional and trial-safe

#### 5.1 Cross-account role policy: use Databricks standard policy in Premium trial
Edit `infra/aws/dbx/databricks/us-west-1/credential.tf`:
- Add `count = local.create_workspace ? 1 : 0` to:
  - `data.databricks_aws_assume_role_policy.this`
  - `aws_iam_role.cross_account_role`
  - `aws_iam_role_policy.cross_account`
- Add `data "databricks_aws_crossaccount_policy" "this"` with `count = (!local.is_enterprise && local.create_workspace) ? 1 : 0`.
- For the role policy:
  - Premium: use `data.databricks_aws_crossaccount_policy.this[0].json`
  - Enterprise: keep the existing restrictive `jsonencode(...)`

#### 5.2 Root bucket encryption: SSE-S3 in Premium trial (no CMKs)
Edit `infra/aws/dbx/databricks/us-west-1/root_s3_bucket.tf`:
- Add `count = local.create_workspace ? 1 : 0` to all resources in this file.
- Split encryption into two resources:
  - KMS-backed encryption with `count = local.enable_customer_managed_keys ? 1 : 0`
  - SSE-S3 (`sse_algorithm = "AES256"`) with `count = local.enable_customer_managed_keys ? 0 : 1`

#### 5.3 CMKs only for Enterprise + create workspace
Edit `infra/aws/dbx/databricks/us-west-1/cmk.tf`:
- Add `count = local.enable_customer_managed_keys ? 1 : 0` for keys and aliases.

#### 5.4 Network/PrivateLink only for Enterprise + isolated/custom networking
Edit `infra/aws/dbx/databricks/us-west-1/network.tf` and `infra/aws/dbx/databricks/us-west-1/privatelink.tf`:
- Replace existing `count = var.network_configuration != "custom" ? 1 : 0` patterns with:
  - `count = local.enable_privatelink ? 1 : 0` (or equivalent gating per-resource)

### 6. Fix metastore module typing + add storage_root support
Update `infra/aws/dbx/databricks/us-west-1/modules/databricks_account/unity_catalog_metastore_creation`:
- Fix `metastore_exists` variable type to `bool` (currently defined as string).
- Add `metastore_storage_root` input and set it on the `databricks_metastore` resource when creating a new metastore.

### 7. Update identity/UC grant glue to work for both UC modes
Edit `infra/aws/dbx/databricks/us-west-1/identify.tf`:
- Pass `workspace_id = local.workspace_id` into `module.users_groups`.
- Change UC catalog grants resource to:
  - `for_each = local.unity_catalog_group_catalog_privileges`
  - `catalog = local.catalog_name`

### 8. Update outputs to not break when workspace creation is disabled
Edit `infra/aws/dbx/databricks/us-west-1/outputs.tf`:
- `workspace_host = local.workspace_host`
- `catalog_name = local.catalog_name`

### 9. Update examples + docs for Premium trial first
- Copy current `infra/aws/dbx/databricks/us-west-1/template.tfvars.example` to `infra/aws/dbx/databricks/us-west-1/template.enterprise_sra.tfvars.example` (unchanged).
- Rewrite `infra/aws/dbx/databricks/us-west-1/template.tfvars.example` for Premium trial + existing workspace:
  - `pricing_tier = "PREMIUM"`
  - `workspace_source = "existing"`
  - `existing_workspace_host = ""`
  - `existing_workspace_id = ""`
  - `network_configuration = "managed"`
  - `uc_catalog_mode = "existing"`
  - `uc_existing_catalog_name = "main"`
  - `enable_audit_log_delivery = false`
  - `enable_example_cluster = false`
  - Recommend `metastore_exists = true` for trial (unless user provides `metastore_storage_root`)
- Update `infra/aws/dbx/databricks/us-west-1/README.md`:
  - Add “Premium Trial Quickstart (Existing Workspace)” and “Create Workspace Later” sections.
  - Add “Upgrade to Enterprise SRA” section explaining which flags/tier/source combinations turn on the full AWS/network/security footprint.

---

## Test Cases / Acceptance Criteria
- Premium trial, existing workspace (default path):
  - Vars: `pricing_tier="PREMIUM"`, `workspace_source="existing"`, `network_configuration="managed"`, `uc_catalog_mode="existing"`
  - `terraform plan` includes no: `aws_vpc*`, `aws_vpc_endpoint*`, `aws_security_group*`, `aws_kms_key*`, `databricks_mws_networks`, `databricks_mws_customer_managed_keys`, `databricks_mws_log_delivery`.
- Premium trial, create workspace (future path):
  - Vars: `pricing_tier="PREMIUM"`, `workspace_source="create"`, `network_configuration="managed"`
  - Workspace uses Premium pricing tier and omits network/CMK/PAS attachments; cross-account role policy uses `databricks_aws_crossaccount_policy`; root bucket uses SSE-S3.
- Enterprise SRA, create workspace:
  - Vars: `pricing_tier="ENTERPRISE"`, `workspace_source="create"`, `network_configuration="isolated"` (or `custom`)
  - Plan remains functionally equivalent to today: PrivateLink + CMKs + network policy + NCC binding + restrictive bucket policy + disable legacy settings.

---

## Assumptions / Defaults
- “Premium trial” here means an **AWS E2 account console** where `pricing_tier="PREMIUM"` is available.
- `databricks_mws_workspaces` allows omitting `network_id` and CMK IDs (Databricks-managed VPC + default encryption) when using `network_configuration="managed"`.
- UC is always enabled; by default the plan assumes an existing UC catalog named `main` is present (and will grant/admin + set default namespace accordingly).
