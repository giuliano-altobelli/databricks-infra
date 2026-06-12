# Facts Ledger (Docs -> Durable Facts)

Use this file to keep retrieved documentation out of chat context.

Rules:

- Record only the minimum durable facts needed to implement the module.
- Prefer 1-2 lines per fact; do not paste large doc blocks.
- Always include a source pointer you can re-fetch later.
  - Terraform Registry / raw provider docs
  - Databricks docs pages
  - Provider source when docs and generated schema differ

## Facts

| Area | Item | Fact (short) | Source | Notes |
| --- | --- | --- | --- | --- |
| resource | `databricks_model_serving` | The resource manages Databricks Model Serving endpoints and can only be used with a workspace-level provider. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/model_serving.md` | Caller must wire `databricks.created_workspace`. |
| resource | `config.served_entities` | A serving endpoint can have up to 10 served entities; `served_models` is deprecated in favor of `served_entities`. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/model_serving.md` | Phase 1 should use `served_entities` only. |
| resource | external models | Provider docs expose `external_model.provider`, `external_model.name`, `external_model.task`, and provider-specific config blocks. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/model_serving.md` | Phase 1 fixes `provider = "amazon-bedrock"`. |
| argument | `amazon_bedrock_config` | Bedrock config supports `aws_region`, `bedrock_provider`, access-key fields, and `instance_profile_arn`; the current root stack provider generation used for this path does not expose `uc_service_credential_name` here. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/model_serving.md`; raw: `internal/service/serving_tf/model.go`; local root lock: `infra/aws/dbx/databricks/us-west-1/.terraform.lock.hcl` | Use `instance_profile_arn` in Phase 1; do not use access keys. |
| resource | external model cardinality | Generated provider comments state all external models within an endpoint must have the same task type. | raw: `terraform-provider-databricks/v1.109.0/internal/service/serving_tf/model.go` | This supports module validation for one task per endpoint. |
| docs gap | external model cardinality | Provider markdown says an external model served entity list can only have one object, but generated provider model and product docs support multiple external models with the same task. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/model_serving.md`; raw: `internal/service/serving_tf/model.go`; docs.databricks.com: `machine-learning/model-serving/serve-multiple-models-to-serving-endpoint` | Implementation should include a positive Terraform test for multiple Bedrock served entities. |
| argument | `traffic_config.routes` | Each route targets a served entity and sets an integer traffic percentage from 0 to 100. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/model_serving.md` | Module validation should require one route per served entity and total 100. |
| permissions | `databricks_permissions` | The resource is authoritative and can overwrite existing permissions on the managed object. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/permissions.md` | Out-of-band endpoint ACLs are not preserved. |
| permissions | serving endpoints | Valid permission levels for `databricks_model_serving` are `CAN_VIEW`, `CAN_QUERY`, and `CAN_MANAGE`. | raw: `terraform-provider-databricks/v1.109.0/docs/resources/permissions.md`; raw: `permissions/permission_definitions.go` | `CAN_QUERY` is needed by SQL callers; `CAN_MANAGE` is for operators. |
| Databricks docs | external models auth | Databricks external Bedrock model auth supports UC service credential, instance profile, or AWS access keys. | docs.databricks.com: `generative-ai/external-models` | Long-term preference is UC service credential; Phase 1 uses instance profile due provider gap. |
| Databricks docs | service credentials | A service credential is a Unity Catalog object for governing Databricks access to external cloud services. | docs.databricks.com: `connect/unity-catalog/cloud-services/service-credentials` | Future Bedrock auth should live at the shared metastore, with workspace bindings if isolation is required. |
| Databricks docs | multi-model endpoints | Multiple external models can be configured in one serving endpoint when they use the same task type and unique served entity names; external and non-external models cannot be mixed. | docs.databricks.com: `machine-learning/model-serving/serve-multiple-models-to-serving-endpoint` | Phase 1 constrains each endpoint to Bedrock external models only. |
| Databricks SQL | `ai_query` | `ai_query` invokes an existing Model Serving endpoint in the same workspace and the definer must have `CAN QUERY`; SQL Classic is not supported. | docs.databricks.com: `sql/language-manual/functions/ai_query` | Acceptance is a post-apply smoke test, not a Terraform action. |
| Databricks SQL | agents with `ai_query` | Databricks documents `ai_query` as able to query an AI agent deployed on a Model Serving endpoint. | docs.databricks.com: `sql/language-manual/functions/ai_query` | Agent serving endpoints are a separate workspace serving shape and remain outside Phase 1. |

## Decisions

- Decision: Phase 1 creates only workspace serving endpoints and endpoint permissions.
- Rationale: The current root stack provider path for Bedrock external models cannot consume `uc_service_credential_name` yet, so creating service credentials now would create a partially unused control surface.
- Consequences: The caller must pass `instance_profile_arn`; future migration to UC service credentials will be a deliberate module change.

- Decision: Keep `instance_profile_arn` and `aws_region` endpoint-level.
- Rationale: They define the operational auth and Bedrock region boundary for the endpoint.
- Consequences: If different models need different auth or regions, use separate endpoints for now.

- Decision: Support multi-model endpoints in the first interface.
- Rationale: Databricks supports multiple external models in an endpoint when they share task type, and the caller wants the first endpoint instance to support multi-model routing.
- Consequences: The module must validate unique served entity names, one task per endpoint, and traffic percentages that sum to 100.

- Decision: Manage endpoint permissions authoritatively with `databricks_permissions`.
- Rationale: `ai_query` requires workspace endpoint query permission, and endpoint ACLs are workspace-scoped.
- Consequences: Existing out-of-band endpoint ACL changes on managed endpoints are reset by Terraform.

## Open Questions

- None.
