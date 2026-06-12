# Acceptance Runbook

This runbook proves the Phase 1 acceptance path: a caller in the workspace can invoke a Bedrock external foundation model through Databricks `ai_query`.

## Preconditions

- The AWS account has Bedrock model access enabled for the selected model IDs.
- The AWS IAM role behind `instance_profile_arn` can invoke the selected Bedrock models in `aws_region`.
- The Databricks workspace can use the instance profile ARN.
- The workspace is in a Databricks Model Serving region.
- The SQL caller has `CAN_QUERY` on the serving endpoint.
- The SQL caller runs from Databricks SQL or compatible compute in the same workspace. SQL Classic is not supported for `ai_query`.

## Apply

Define the root variables in the scenario var file:

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

Run the root plan/apply from the repository root. If the values live in `terraform.tfvars`, use the existing scenario command:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply -var-file=terraform.tfvars
```

If the values are kept in `bedrock-external-model-endpoints.tfvars.example` or a copied Bedrock-specific var file, pass both var files:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars -var-file=bedrock-external-model-endpoints.tfvars.example
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 apply -var-file=terraform.tfvars -var-file=bedrock-external-model-endpoints.tfvars.example
```

After apply, read the endpoint name:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 output bedrock_external_model_endpoint_names
```

Set the workspace host for Databricks CLI smoke-test commands:

```bash
export DATABRICKS_HOST="$(DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 output -raw workspace_host)"
```

## Smoke Test

Wait until the serving endpoint is ready:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 databricks serving-endpoints get bedrock-foundation-models -o json
```

Proceed when the response shows `state.ready = READY` and `state.config_update = NOT_UPDATING`.

Then run this SQL from the same workspace as a principal with `CAN_QUERY`:

```sql
SELECT ai_query(
  'bedrock-foundation-models',
  'Return exactly one short sentence confirming this Databricks to Bedrock endpoint is reachable.'
) AS bedrock_health_check;
```

For an automated smoke test through the Databricks CLI, use the SQL Statements API with an existing non-Classic SQL warehouse:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 databricks api post /api/2.0/sql/statements --json '{"warehouse_id":"<warehouse-id>","statement":"SELECT ai_query('\''bedrock-foundation-models'\'', '\''Return exactly one short sentence confirming this Databricks to Bedrock endpoint is reachable.'\'') AS bedrock_health_check","wait_timeout":"30s"}' -o json
```

If the statement response is still pending or running, poll the returned statement ID:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 databricks api get /api/2.0/sql/statements/<statement-id> -o json
```

Acceptance passes when the query returns a non-empty model response without permission, endpoint, or provider auth errors.

If `databricks serving-endpoints get` returns `Endpoint with name 'bedrock-foundation-models' does not exist`, confirm that:

- `DATABRICKS_HOST` matches the Terraform `workspace_host` output.
- The apply used the var file that sets `bedrock_external_model_endpoints_enabled = true`.
- Placeholder values were replaced with a real instance profile ARN and real workspace principals.

## Multi-Model Check

The example endpoint already declares two Bedrock served entities with the same `task` and traffic percentages that sum to 100. After apply, confirm:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 output bedrock_external_model_served_entity_names
```

The output should show both served entity names under the endpoint key. The same `ai_query` smoke test remains endpoint-level because Databricks routes according to `traffic_config`.

## Future Auth Migration

When the root stack deliberately moves to a Databricks provider generation that can pass `uc_service_credential_name` through the Bedrock external model serving path, migrate Bedrock auth to a Unity Catalog service credential at the shared metastore level. At that point this module should stop accepting `instance_profile_arn`.
