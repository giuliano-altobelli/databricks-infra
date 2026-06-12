# Module Spec

## Summary

- **Module name**: `databricks_workspace/bedrock_external_model_endpoints`
- **One-liner**: Manage workspace-scoped Databricks Model Serving endpoints for Amazon Bedrock external foundation models and their authoritative endpoint ACLs.

## Scope

- In scope:
  - workspace-level only
  - one `databricks_model_serving` endpoint per caller-defined endpoint key
  - Amazon Bedrock external models only, using `provider = "amazon-bedrock"`
  - `served_entities` only; do not use deprecated `served_models`
  - multi-model endpoint support through multiple Bedrock external served entities and explicit `traffic_config`
  - endpoint-level `instance_profile_arn` applied to every Bedrock served entity in the endpoint
  - endpoint-level `aws_region` applied to every Bedrock served entity in the endpoint
  - per-model `name`, `task`, `bedrock_provider`, `bedrock_model`, and `traffic_percentage`
  - one authoritative `databricks_permissions` resource per managed endpoint using `serving_endpoint_id`
  - endpoint ACLs for groups, users, and service principals
  - stable output maps for endpoint IDs, endpoint names, endpoint URLs, and served entity names
  - documenting the post-apply `ai_query` smoke test path
- Out of scope:
  - creating Unity Catalog service credentials in Phase 1
  - creating AWS IAM roles, AWS instance profiles, AWS policies, or Bedrock model access grants
  - creating Databricks users, groups, service principals, entitlements, or workspace assignments
  - creating SQL warehouses or running SQL
  - executing the `ai_query` acceptance smoke test from Terraform
  - non-Bedrock external model providers
  - Databricks agent serving endpoints
  - Databricks-hosted foundation models, provisioned throughput endpoints, custom models, UC models, or model registry entities
  - AI Gateway, inference tables, guardrails, rate limits, budget policies, fallback config, tags, and route optimization
  - per-model auth or cross-region routing inside one endpoint
  - adopting existing serving endpoints
  - multi-workspace fan-out from one module invocation

## Current Stack Usage

- This module is intended to be called from `infra/aws/dbx/databricks/us-west-1`.
- The caller must pass the workspace-scoped `databricks.created_workspace` provider alias.
- The root stack exposes `bedrock_external_model_endpoints_enabled` and `bedrock_external_model_endpoints` so endpoint definitions can be supplied through scenario vars without editing module code.
- The caller owns the AWS-side Bedrock IAM setup and passes an already usable `instance_profile_arn`.
- Phase 1 intentionally does not create a Unity Catalog service credential because the current root stack provider generation used for this path does not expose `uc_service_credential_name` for the Amazon Bedrock external model auth shape used by `databricks_model_serving`.

## Interfaces

- Required inputs:
  - `bedrock_external_model_endpoints` (`map(object)`): serving endpoints keyed by stable caller-defined identifiers. Each value contains:
    - `name` (`string`): Databricks serving endpoint name, unique in the workspace
    - `aws_region` (`string`): AWS Bedrock region used by every served entity in the endpoint
    - `instance_profile_arn` (`string`): AWS instance profile ARN used by every Bedrock served entity in the endpoint
    - `served_entities` (`map(object)`): Bedrock external served entities keyed by stable caller-defined identifiers. Each value contains:
      - `name` (`string`): Databricks served entity name, unique inside the endpoint
      - `task` (`string`): Databricks external model task type
      - `bedrock_provider` (`string`): underlying Bedrock provider value accepted by Databricks, such as `Anthropic`, `Cohere`, `AI21Labs`, or `Amazon`
      - `bedrock_model` (`string`): Bedrock model identifier used as `external_model.name`
      - `traffic_percentage` (`number`): integer route percentage for this served entity
    - `permissions` (`list(object)`): endpoint ACL entries. Each value contains:
      - `principal_type` (`string`): one of `group`, `user`, or `service_principal`
      - `principal_name` (`string`): Databricks-native principal identifier
      - `permission_level` (`optional(string, "CAN_QUERY")`): endpoint permission level
- Optional inputs:
  - `enabled` (`bool`, default `true`): when `false`, the module creates no resources and all outputs collapse to empty maps
- Outputs:
  - `endpoint_ids`: map of endpoint keys to `databricks_model_serving.serving_endpoint_id`
  - `endpoint_names`: map of endpoint keys to Databricks serving endpoint names
  - `endpoint_urls`: map of endpoint keys to serving endpoint URLs
  - `served_entity_names`: nested map of endpoint keys and served entity keys to Databricks served entity names
- Supporting docs:
  - `ACCEPTANCE.md`: root apply and `ai_query` smoke-test runbook
  - `bedrock-external-model-endpoints.tfvars.example`: root scenario-var example with placeholders

## Provider Context

- Provider(s):
  - `databricks` only, wired by the caller to `databricks.created_workspace`
- Authentication mode:
  - workspace-scoped Databricks authentication, validated in this repo with `DATABRICKS_AUTH_TYPE=oauth-m2m`
- Account-level vs workspace-level:
  - workspace-level only
  - this module must not use `databricks.mws` or any account-scoped provider alias

## Behavior / Data Flow

- `bedrock_external_model_endpoints` is the single required caller-owned map input.
- Stable endpoint keys are Terraform addresses and downstream lookup keys.
- Stable served entity keys are normalization keys. Databricks routing uses the served entity `name`.
- When `enabled = false`, the module creates no resources and all outputs are empty maps.
- When `enabled = true`, the module:
  1. iterates over stable caller-defined endpoint keys
  2. creates one `databricks_model_serving` resource per endpoint key
  3. emits one `config.served_entities` block per Bedrock served entity
  4. sets each served entity as an external model with `provider = "amazon-bedrock"`
  5. sets `external_model.name` from `bedrock_model`
  6. sets `external_model.task` from the model `task`
  7. sets `external_model.amazon_bedrock_config.aws_region` from the endpoint-level `aws_region`
  8. sets `external_model.amazon_bedrock_config.bedrock_provider` from the model `bedrock_provider`
  9. sets `external_model.amazon_bedrock_config.instance_profile_arn` from the endpoint-level `instance_profile_arn`
  10. creates one `traffic_config.routes` block per served entity using that entity's `traffic_percentage`
  11. normalizes and validates caller-supplied endpoint permission tuples
  12. creates one authoritative `databricks_permissions` resource per endpoint using `serving_endpoint_id`
  13. translates generic ACL entries into provider-specific group, user, or service principal access-control fields
  14. publishes stable output maps keyed by the same caller-owned endpoint keys

## Metastore vs Workspace Boundary

- Recommended metastore-level object, future phase:
  - Unity Catalog service credential for Bedrock cloud-service authentication.
  - Reason: this is the durable auth boundary when multiple workspaces share one Unity Catalog metastore. It can be governed once, granted through Unity Catalog privileges, and optionally workspace-bound so only approved workspaces can use it.
- Recommended workspace-level objects, Phase 1:
  - Databricks Model Serving endpoint.
  - Databricks endpoint ACLs through `databricks_permissions`.
  - Reason: endpoint invocation, endpoint readiness, endpoint permissions, and `ai_query` callers are scoped to a single workspace.
- AWS-level prerequisites, outside this module:
  - IAM role, instance profile, trust policy, Bedrock permissions, and Bedrock model access.
  - Reason: Terraform in this Databricks module should not own the AWS control surface for Bedrock auth.

## Bedrock Auth Direction

- Preferred long-term auth path:
  - Create a Unity Catalog service credential in a metastore-oriented module.
  - Grant and optionally workspace-bind that service credential according to the shared-metastore governance model.
  - Update this workspace endpoint module to accept `uc_service_credential_name` once the root stack deliberately moves to a Databricks Terraform provider generation that can pass it through the `databricks_model_serving` Amazon Bedrock external model path.
  - At that time, remove `instance_profile_arn` from this module interface or make the migration explicitly breaking.
- Phase 1 auth path:
  - Accept endpoint-level `instance_profile_arn`.
  - Apply the same `instance_profile_arn` to every Bedrock served entity in the endpoint.
  - Do not create Unity Catalog service credentials yet; that would create a partially unused control surface for the current root stack provider generation because the endpoint module does not consume them.
- Multi-workspace note:
  - A unique `instance_profile_arn` is not inherently required for every workspace.
  - The same instance profile ARN can be reused when the same AWS account, Bedrock region, model permissions, audit boundary, billing boundary, and blast-radius boundary are acceptable, and each workspace is configured or allowed to use it.
  - Use separate instance profiles when workspaces need different AWS accounts, Bedrock regions, model access policies, audit trails, cost attribution, or isolation boundaries.
  - The future Unity Catalog service credential path is preferred because it moves this choice to metastore-governed auth instead of duplicating auth decisions across workspace endpoint definitions.

## Constraints and Failure Modes

- Each endpoint must contain at least one served entity.
- Each endpoint can contain at most 10 served entities.
- All served entities in an endpoint must be Bedrock external models.
- All served entities in an endpoint must use the same `task`.
- Supported task values are `llm/v1/chat`, `llm/v1/completions`, and `llm/v1/embeddings`.
- Served entity names must be unique within an endpoint.
- Managed endpoint names must be unique across module input values.
- `instance_profile_arn` must be an AWS IAM instance profile ARN.
- Each served entity must have exactly one traffic route.
- Traffic percentages must be integers from 0 through 100.
- Traffic percentages must sum to exactly 100 per endpoint.
- Each endpoint must declare at least one permission entry.
- Each endpoint should declare at least one explicit `CAN_MANAGE` platform/operator principal; do not rely on implicit provider lockout prevention as the governance model.
- Supported endpoint permission levels are `CAN_VIEW`, `CAN_QUERY`, and `CAN_MANAGE`.
- `CAN_QUERY` is the normal permission for SQL callers that need `ai_query`.
- `CAN_MANAGE` is for platform operators that administer the endpoint and its ACLs.
- `CAN_VIEW` is available for endpoint visibility without query permission.
- Duplicate permission tuples are invalid and must fail clearly rather than silently deduplicating.
- Principal identifiers must already exist in the target workspace.
- `databricks_permissions` is authoritative for each managed endpoint. Out-of-band endpoint ACL changes are not preserved.
- External model endpoints cannot be mixed with custom models, UC models, registered models, Databricks-hosted foundation models, or provisioned throughput endpoints.
- Provider and API behavior can make converting an endpoint between external-model and non-external-model shapes impossible without replacement. Phase 1 does not support that conversion.
- If the instance profile is not usable by the workspace endpoint or lacks Bedrock permissions, apply or endpoint readiness can fail outside Terraform validation.
- If the Bedrock model is unavailable in `aws_region`, endpoint creation or invocation can fail.

## `ai_query` Acceptance Path

- Terraform acceptance:
  - create the workspace serving endpoint
  - create authoritative endpoint permissions
  - expose endpoint names, IDs, URLs, and served entity names
- Post-apply smoke test:
  - run from a Databricks SQL warehouse or compatible compute in the same workspace
  - run as a principal that has `CAN_QUERY` on the endpoint
  - wait until the serving endpoint reports `state.ready = READY` and `state.config_update = NOT_UPDATING` before invoking
  - use a simple SQL check such as:

```sql
SELECT ai_query('<endpoint_name>', 'Return a one sentence health check.');
```

- This module does not create the SQL warehouse and does not execute the SQL smoke test.
- `ai_query` is the acceptance criterion for the integrated workspace path, not a Terraform-managed resource.
- Databricks agent serving endpoints can also be queried with `ai_query`, but they are a different workspace serving endpoint shape and are outside Phase 1.

## Validation

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/bedrock_external_model_endpoints init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/bedrock_external_model_endpoints validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/bedrock_external_model_endpoints test`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- Root verification from `infra/aws/dbx/databricks/us-west-1`:
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars`
- Negative-path checks:
  - empty endpoint map when `enabled = true`
  - endpoint with empty `served_entities`
  - more than 10 served entities
  - duplicate endpoint names
  - duplicate served entity names in one endpoint
  - mixed task values in one endpoint
  - unsupported task value
  - malformed `instance_profile_arn`
  - traffic routes not summing to 100
  - traffic percentage outside 0 through 100
  - non-integer traffic percentage
  - empty `permissions`
  - unsupported `principal_type`
  - unsupported endpoint `permission_level`
  - duplicate permission tuples
- Positive-path checks:
  - single Bedrock model at 100 percent traffic
  - multiple Bedrock models with explicit traffic split
  - output maps are empty when `enabled = false`
  - output maps are keyed by caller-defined endpoint keys
