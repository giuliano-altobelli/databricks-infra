# Databricks Service Credentials Module Design Doc

Status: draft for feedback

This design describes the lightweight AWS-only Terraform module for Unity Catalog service credentials. The module lets approved Databricks principals use a Unity Catalog service credential backed by an AWS IAM role.

# Problem Context

This repository already separates Databricks identity, Unity Catalog securables, storage access, and workspace serving endpoints. Service credentials introduce another Unity Catalog securable: a metastore-governed credential that lets Databricks access external cloud services.

The immediate need is to support service credentials for AWS roles. Longer term, the same module family should be able to support Azure and GCP, but phase 1 should avoid a large cloud-neutral abstraction before the AWS path is proven.

The current Bedrock endpoint module still accepts `instance_profile_arn` because the provider path used there does not expose `uc_service_credential_name`. This design treats service credentials as the future metastore auth object and does not change Bedrock endpoint behavior by itself.

# Proposed Solution

The module lives at:

```text
infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_service_credentials/
```

The module should manage Unity Catalog service credentials through the workspace-scoped Databricks provider, mirroring the conventions in `databricks_workspace/unity_catalog_storage_locations`.

The provider resource is `databricks_credential` with `purpose = "SERVICE"`, not a separate `databricks_service_credential` resource.

Phase 1 creates AWS-backed service credentials from caller-supplied IAM role ARNs, manages explicit `ACCESS` grants for approved principals, optionally restricts credentials to specific workspaces through workspace bindings, and exposes Databricks-generated AWS trust fields for external IAM follow-up.

# Goals and Non-Goals

- Give platform developers a clear root-module configuration surface for declaring service credentials and the principals that can use them.
- Keep the child module generic by accepting Databricks-native principal names or IDs after root-level resolution.
- Support AWS IAM role backed service credentials only in phase 1.
- Preserve stable caller-defined map keys for Terraform addresses and outputs.
- Keep AWS IAM ownership outside this Databricks module.
- Leave a clean path to later Azure and GCP support without implementing those clouds now.

## Non-Goals

- Do not create or update AWS IAM roles, trust policies, inline policies, Bedrock permissions, or external-service resource permissions.
- Do not create Azure managed identities, Azure service principals, GCP service accounts, or cross-cloud provider fan-out.
- Do not create Unity Catalog storage credentials, external locations, catalogs, schemas, tables, volumes, or data grants.
- Do not create Databricks users, groups, service principals, workspace assignments, entitlements, service principal credentials, or AWS Secrets Manager secrets.
- Do not modify the current Bedrock external model endpoint module or migrate it from `instance_profile_arn` to `uc_service_credential_name`.
- Do not support Lakehouse Federation connection creation or `CREATE_CONNECTION` grants in phase 1.
- Do not import or adopt existing service credentials automatically.
- Do not run Terraform resources as part of this design-only task.

# Design

## Module Boundary

The module belongs under `databricks_workspace` because the Terraform provider manages Unity Catalog securables through a workspace-scoped provider, even though the service credential is conceptually a metastore-level object.

The root caller wires only:

```hcl
providers = {
  databricks = databricks.created_workspace
}
```

The module must not use `databricks.mws` or account-level resources.

## Developer Experience

When a root consumer is ready, platform developers should declare service credentials in one root config file, likely `service_credential_config.tf`. The root layer can provide a friendly `grant_principals` shape using repo-owned identity keys, then resolve those keys into Databricks-native principal strings before calling the child module.

Example future root configuration:

```hcl
locals {
  uc_service_credentials_enabled = false

  uc_service_credentials = {
    bedrock_runtime = {
      name    = "sandbox-bedrock-runtime-service-credential"
      comment = "Allows approved Databricks principals to use the AWS Bedrock runtime role."

      aws = {
        role_arn = "arn:aws:iam::123456789012:role/databricks-sandbox-bedrock-runtime"
      }

      skip_validation       = true
      workspace_access_mode = "ISOLATION_MODE_ISOLATED"
      workspace_ids         = []

      grant_principals = {
        groups             = ["platform_admins"]
        service_principals = ["uat_promotion"]
      }
    }
  }

  uc_service_credentials_resolved = {
    for credential_key, credential in local.uc_service_credentials : credential_key => {
      name                  = credential.name
      comment               = try(credential.comment, null)
      owner                 = try(credential.owner, null)
      aws                   = credential.aws
      skip_validation       = try(credential.skip_validation, false)
      force_destroy         = try(credential.force_destroy, false)
      force_update          = try(credential.force_update, false)
      workspace_access_mode = try(credential.workspace_access_mode, "ISOLATION_MODE_ISOLATED")
      workspace_ids         = try(credential.workspace_ids, [])

      grants = concat(
        [
          for group_key in try(credential.grant_principals.groups, []) : {
            principal  = local.identity_groups[group_key].display_name
            privileges = ["ACCESS"]
          }
        ],
        [
          for service_principal_key in try(credential.grant_principals.service_principals, []) : {
            principal  = module.service_principals.application_ids[service_principal_key]
            privileges = ["ACCESS"]
          }
        ],
        try(credential.grants, [])
      )
    }
  }
}

module "unity_catalog_service_credentials" {
  source = "./modules/databricks_workspace/unity_catalog_service_credentials"

  providers = {
    databricks = databricks.created_workspace
  }

  enabled             = local.uc_service_credentials_enabled
  current_workspace_id = local.workspace_id
  service_credentials = local.uc_service_credentials_resolved

  depends_on = [
    module.unity_catalog_metastore_assignment,
    module.users_groups,
    module.service_principals,
  ]
}
```

No root config is checked in for this phase. A future checked-in root config should default `uc_service_credentials_enabled = false` until a concrete consumer is ready. That keeps the design aligned with the current architecture note that Bedrock endpoints cannot yet consume Unity Catalog service credentials in this repo.

## Child Module Schema

The child module should accept already resolved principal identifiers. It should not know about `local.identity_groups`, `module.service_principals`, or any other root-local identity shape.

```hcl
variable "enabled" {
  description = "Whether this module is enabled."
  type        = bool
  default     = true
}

variable "current_workspace_id" {
  description = "Current workspace ID used to seed isolated workspace bindings."
  type        = string
}

variable "service_credentials" {
  description = "Unity Catalog service credentials keyed by stable caller-defined identifiers."
  type = map(object({
    name    = string
    comment = optional(string)
    owner   = optional(string)

    aws = object({
      role_arn = string
    })

    skip_validation       = optional(bool, false)
    force_destroy         = optional(bool, false)
    force_update          = optional(bool, false)
    workspace_access_mode = optional(string, "ISOLATION_MODE_ISOLATED")
    workspace_ids         = optional(list(string), [])

    grants = optional(list(object({
      principal  = string
      privileges = optional(list(string), ["ACCESS"])
    })), [])
  }))
  default = {}
}
```

Phase-1 validations should reject:

- blank credential names
- malformed AWS IAM role ARNs
- unsupported workspace access modes outside `ISOLATION_MODE_ISOLATED` and `ISOLATION_MODE_OPEN`
- `ISOLATION_MODE_OPEN` with explicit `workspace_ids`
- blank or non-numeric workspace IDs
- blank grant principals
- empty grant privilege lists
- grant privileges other than `ACCESS`
- duplicate grant tuples
- duplicate workspace binding tuples

When `enabled = false`, the module should ignore `service_credentials`, create no resources, and return empty output maps.

## Terraform Resources

When enabled, the module should create one `databricks_credential` per service credential key:

```hcl
resource "databricks_credential" "this" {
  for_each = local.enabled_service_credentials

  name             = each.value.name
  purpose          = "SERVICE"
  comment          = try(each.value.comment, null)
  owner            = try(each.value.owner, null)
  skip_validation  = each.value.skip_validation
  force_destroy    = each.value.force_destroy
  force_update     = each.value.force_update
  isolation_mode   = each.value.workspace_access_mode

  aws_iam_role {
    role_arn = each.value.aws.role_arn
  }
}
```

It should create one authoritative `databricks_grants` resource per credential when grants are declared. For phase 1, those grants should allow only `ACCESS`, because the module's purpose is to let approved principals use the credential, not administer it or create connections.

It should create `databricks_workspace_binding` resources when `workspace_access_mode = "ISOLATION_MODE_ISOLATED"`. The effective binding set should be `distinct([current_workspace_id] + workspace_ids)`, matching the storage-location module pattern. Open mode should create no explicit bindings.

## Outputs

The main output should be keyed by the same stable service credential keys:

```hcl
output "service_credentials" {
  description = "Unity Catalog service credential details keyed by stable service credential key."
  value = {
    for credential_key, credential in databricks_credential.this : credential_key => {
      name                  = credential.name
      id                    = credential.id
      credential_id         = try(credential.credential_id, null)
      full_name             = try(credential.full_name, null)
      external_id           = try(credential.aws_iam_role[0].external_id, null)
      unity_catalog_iam_arn = try(credential.aws_iam_role[0].unity_catalog_iam_arn, null)
    }
  }
}
```

Additional outputs should include:

- `grant_ids`: grant resource IDs keyed by service credential key
- `workspace_binding_ids`: binding IDs keyed by `<credential_key>:<workspace_id>`

The generated `external_id` and `unity_catalog_iam_arn` are important because the AWS IAM role trust policy usually needs a follow-up patch outside this module. If IAM trust is not ready on the first apply, callers should use `skip_validation = true`, update IAM externally, then re-enable validation.

## Security Model

Service credentials are Unity Catalog securables, not service principal credentials and not storage credentials.

The Databricks-side permission that lets a principal use a service credential is `ACCESS`. Root config should resolve principals from stable identity keys where possible:

- group keys to Databricks group display names
- service principal keys to Databricks service principal application IDs
- direct native principals only for exceptional or externally managed identities

The module should manage grants authoritatively. Out-of-band grants on managed service credentials are not preserved.

The module should not create AWS IAM trust or permissions. It should expose trust values and document that AWS ownership belongs to a separate AWS stack or manual operator workflow.

# Alternatives Considered

## Put Service Credentials In The Bedrock Endpoint Module

This makes endpoint config shorter, but it mixes a metastore-governed auth object with workspace-scoped serving endpoints. It also conflicts with the current provider limitation that keeps Bedrock on `instance_profile_arn`.

## Let The Child Module Accept Identity Keys

The child module could accept `group_keys` and `service_principal_keys`, but that couples a generic Unity Catalog module to this root module's identity implementation. Resolving principals in the root keeps the module reusable and matches existing grant patterns.

## Use A Cloud-Neutral Credential Object Now

A fully generic schema could model AWS, Azure, and GCP in phase 1, but that adds validation and provider-shape complexity before any non-AWS path is needed. The recommended schema uses an `aws` block now and can add `azure` or `gcp` blocks later with an exactly-one-cloud validation.

## Reuse The Storage Credential Module

Storage credentials and service credentials are distinct Unity Catalog securables with different purposes and privileges. The service credential module should copy the useful patterns, not share the implementation.

# Open Questions

- Which first consumer should enable this root path: Bedrock once `uc_service_credential_name` is available in the repo's provider path, Lakehouse Federation, or another external cloud service?
- Should platform operators receive `MANAGE` through grants in a later phase, or should management stay with the credential owner only?
- Should a future AWS companion module automate the IAM trust update using the emitted `external_id` and `unity_catalog_iam_arn`, or should that remain outside this repository?

# Module Acceptance

Implementation should include:

- module `SPEC.md` and `FACTS.md` before Terraform changes
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_service_credentials init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_service_credentials validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_service_credentials test`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- root validate and root plan using the repo command pattern:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars
```

# Appendix

- `ARCHITECTURE.md`: external foundation model serving notes and future Unity Catalog service credential direction.
- `CONTEXT.md`: terminology clarifying Unity Catalog service credentials versus service principal credentials.
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_storage_locations/SPEC.md`: closest existing module pattern for AWS role ARNs, authoritative grants, workspace bindings, and trust outputs.
- `infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/bedrock_external_model_endpoints/SPEC.md`: current Bedrock endpoint scope and future auth migration direction.
- Databricks Terraform provider docs: `databricks_credential`, `databricks_grants`, and `databricks_workspace_binding`.
