# Bedrock External Model Endpoints

This module manages workspace-scoped Databricks Model Serving endpoints for Amazon Bedrock external foundation models.

Phase 1 intentionally creates only:

- `databricks_model_serving`
- `databricks_permissions`

It does not create Unity Catalog service credentials yet. The current root stack provider generation used for this path does not expose `uc_service_credential_name` on the Bedrock external model shape this module uses, so the current interface accepts endpoint-level `instance_profile_arn`.

Databricks agent serving endpoints are a separate workspace serving shape. They can also be queried through `ai_query`, but this Phase 1 module only creates Bedrock external foundation model endpoints.

## Boundary

- Put future Bedrock auth in the shared Unity Catalog metastore as a service credential when the provider path can use `uc_service_credential_name`.
- Put serving endpoints and endpoint permissions in each workspace.
- Keep AWS IAM roles, instance profiles, trust policies, Bedrock permissions, and Bedrock model access outside this module.

A unique `instance_profile_arn` is not required for every workspace. Reuse an instance profile only when the same AWS account, Bedrock region, model permissions, audit boundary, billing boundary, and blast-radius boundary are acceptable. Use separate instance profiles when those boundaries differ.

## Example

Root stack `terraform.tfvars` opt-in:

```hcl
bedrock_external_model_endpoints_enabled = true

bedrock_external_model_endpoints = {
  foundation_models = {
    name                 = "bedrock-foundation-models"
    aws_region           = "us-west-2"
    instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"

    served_entities = {
      claude_sonnet = {
        name               = "claude_sonnet"
        task               = "llm/v1/chat"
        bedrock_provider   = "Anthropic"
        bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
        traffic_percentage = 90
      }

      claude_haiku = {
        name               = "claude_haiku"
        task               = "llm/v1/chat"
        bedrock_provider   = "Anthropic"
        bedrock_model      = "anthropic.claude-3-haiku-20240307-v1:0"
        traffic_percentage = 10
      }
    }

    permissions = [
      {
        principal_type   = "user"
        principal_name   = "<platform-operator@example.com>"
        permission_level = "CAN_MANAGE"
      },
      {
        principal_type   = "group"
        principal_name   = "<ai-query-users-group>"
        permission_level = "CAN_QUERY"
      },
    ]
  }
}
```

Direct module call:

```hcl
module "bedrock_external_model_endpoints" {
  source = "./modules/databricks_workspace/bedrock_external_model_endpoints"

  providers = {
    databricks = databricks.created_workspace
  }

  enabled = true

  bedrock_external_model_endpoints = {
    foundation_models = {
      name                 = "bedrock-foundation-models"
      aws_region           = "us-west-2"
      instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-bedrock"

      served_entities = {
        claude_sonnet = {
          name               = "claude_sonnet"
          task               = "llm/v1/chat"
          bedrock_provider   = "Anthropic"
          bedrock_model      = "anthropic.claude-3-5-sonnet-20240620-v1:0"
          traffic_percentage = 90
        }

        claude_haiku = {
          name               = "claude_haiku"
          task               = "llm/v1/chat"
          bedrock_provider   = "Anthropic"
          bedrock_model      = "anthropic.claude-3-haiku-20240307-v1:0"
          traffic_percentage = 10
        }
      }

      permissions = [
        {
          principal_type   = "group"
          principal_name   = "platform-admins"
          permission_level = "CAN_MANAGE"
        },
        {
          principal_type   = "group"
          principal_name   = "ai-query-users"
          permission_level = "CAN_QUERY"
        },
      ]
    }
  }
}
```

## Smoke Test

After apply, wait for the endpoint to report `state.ready = READY` and `state.config_update = NOT_UPDATING`:

```bash
export DATABRICKS_HOST="$(DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 output -raw workspace_host)"
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 databricks serving-endpoints get bedrock-foundation-models -o json
```

Then run from a Databricks SQL warehouse or compatible compute in the same workspace as a principal with `CAN_QUERY` on the endpoint:

```sql
SELECT ai_query('bedrock-foundation-models', 'Return a one sentence health check.');
```

See `ACCEPTANCE.md` for the full apply and smoke-test runbook.
