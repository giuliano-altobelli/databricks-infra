# Module Spec

## Summary

- **Module name**: `databricks_identity/aws_secrets`
- **One-liner**: Create AWS Secrets Manager placeholders for Databricks service principal credentials keyed by stable principal IDs.

## Scope

- In scope:
  - One AWS Secrets Manager secret per stable service principal key
  - One bootstrap `aws_secretsmanager_secret_version` per secret
  - Alias-wired AWS provider from the caller
  - Manual AWS console follow-up workflow for later secret value entry
- Out of scope:
  - Databricks credential creation
  - Rotation
  - Secret policy customization
  - KMS customization
  - Generic secret management

## Interfaces

- Required inputs:
  - `region`
  - `name_prefix`
  - `service_principals`
- Optional inputs:
  - `enabled` (defaults to `true`)
- Outputs:
  - `arns`
  - `names`
  - `version_ids`

Contract details:

- Caller-defined stable map keys are the Terraform addresses and output keys.
- Empty or whitespace-only principal keys must fail validation.
- Changing `name_prefix` or principal keys is replacement-by-contract.

## Provider Context

- The caller must pass `providers = { aws = aws.<target_region_alias> }`.
- The `region` input documents and validates intent.
- The AWS provider alias determines the real AWS region used by the resources.
- This module does not route resources by `region`; it relies on the passed provider configuration.

## Constraints / Failure Modes

- One secret and one bootstrap version are created per principal key when `enabled = true`.
- When `enabled = false`, the module must be a no-op and all outputs must be empty maps.
- Manual AWS UI updates create later secret versions and must not be reverted by Terraform.
- `aws_secretsmanager_secret_version` must ignore later `secret_string` changes.
- The module must not manage `version_stages`.
- Stable caller-defined map keys are the Terraform addresses and output keys.
- Empty or whitespace-only principal keys must fail validation.
- Changing `name_prefix` or principal keys is replacement-by-contract.
- The module intentionally uses a placeholder `aws_secretsmanager_secret_version` to bootstrap the secret, then preserves drift once operators create later versions manually in AWS Secrets Manager.

## Validation

- `terraform fmt -recursive`
- Isolated harness `terraform validate`
- Root `terraform validate`
- Root `terraform plan -var-file=terraform.tfvars`
