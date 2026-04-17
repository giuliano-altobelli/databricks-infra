# Databricks AWS Secrets Module

This module creates one AWS Secrets Manager secret per stable Databricks service principal key and seeds each secret with a placeholder version for later manual population.

## Example

Use the same stable service-principal keys you already use for identity provisioning. Do not introduce a separate secret-specific key space.

```hcl
locals {
  service_principals_identity = {
    uat_promotion = {
      display_name       = "UAT Promotion SP"
      principal_scope    = "account"
      workspace_assignment = {
        enabled     = true
        permissions = ["USER"]
      }
    }

    workspace_agent = {
      display_name    = "Workspace Agent SP"
      principal_scope = "workspace"
    }
  }

  service_principals = {
    for principal_key, principal in local.service_principals_identity :
    principal_key => {
      display_name = principal.display_name
    }
  }
}

module "aws_secrets" {
  source = "./modules/databricks_identity/aws_secrets"

  providers = {
    aws = aws.us_west_1
  }

  region             = "us-west-1"
  name_prefix        = "/databricks/identity/service-principals"
  service_principals  = local.service_principals
}
```

The secret name for `uat_promotion` becomes `/databricks/identity/service-principals/uat_promotion`.

## Usage Notes

- `providers = { aws = aws.us_west_1 }` is required at the call site.
- `service_principals` keys are the stable caller-owned identifiers and the downstream secret lookup keys.
- `name_prefix` and the principal key are concatenated as `<name_prefix>/<principal_key>`.
- The bootstrap secret version is placeholder JSON with these fields:

```json
{
  "client_secret": "",
  "client_id": "",
  "application_id": ""
}
```

- The placeholder version exists only to create the secret cleanly on first apply.
- Terraform ignores later `secret_string` drift on that bootstrap version, so manual secret edits in AWS do not get forced back to the placeholder.
- `region` documents the intended region, but the passed AWS provider alias determines the actual region used.
- When `enabled = false`, the module is a no-op and all outputs are empty maps.

## Operator Workflow

1. Run `terraform apply` to create the secret and the placeholder version.
2. Open AWS Secrets Manager.
3. Paste the real secret values into each secret manually.
4. Leave Terraform alone after that; it will not fight later `secret_string` changes on the bootstrap version.

## Out Of Scope

- Secret rotation
- Secret policy customization
- KMS customization
- Databricks credential generation
- Automatic value population
- Databricks ID lookups
