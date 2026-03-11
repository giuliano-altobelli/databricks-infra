# Facts Ledger (Docs → Durable Facts)

Use this file to keep retrieved documentation out of chat context.

Rules:

- Record only the minimum durable facts needed to implement the module.
- Prefer 1–2 lines per fact; do not paste large doc blocks.
- Always include a source pointer you can re-fetch later.
  - Terraform Registry: provider/resource docs page
  - Context7: library id + query topic (so it can be re-run)

## Facts

| Area | Item | Fact (short) | Source | Notes |
| --- | --- | --- | --- | --- |
| resource | `databricks_cluster_policy` | Supports `name` and `definition`; optional args include `description`, `max_clusters_per_user`, `policy_family_id`, and `policy_family_definition_overrides`. | context7: `/databricks/terraform-provider-databricks` query `databricks_cluster_policy arguments` | `description` is supported in the provider docs used by this repo. |
| resource | `databricks_permissions` | `cluster_policy_id` is a supported target for managing cluster policy ACLs with `CAN_USE`. | context7: `/databricks/terraform-provider-databricks` query `databricks_permissions cluster_policy_id` | Workspace-scoped provider only. |
| argument | `databricks_permissions.access_control` | Principal identifiers are provider-specific fields: `group_name` for groups, `user_name` for users, and `service_principal_name` for service principals. | context7: `/databricks/terraform-provider-databricks` query `access_control fields for groups users service principals` | Service principal identifier is the application ID in provider examples. |
| databricks docs | Lakeflow Declarative Pipelines starter policy | Minimal documented starter JSON for DLT/Lakeflow uses fixed `cluster_type = dlt`, `num_workers` unlimited with default 3, optional `node_type_id`, and hidden unlimited `spark_version`. | docs.databricks.com: `Configure compute for Lakeflow Declarative Pipelines` | Used as caller-owned JSON in the root catalog, not embedded in the module. |

## Decisions

- Decision: Keep policy JSON caller-owned in the root catalog and keep the module generic.
- Rationale: The design requires reusable workspace policy management without embedding DLT-specific behavior in the module.
- Consequences: The first rollout still uses the documented DLT starter JSON, but it lives in `cluster_policy_config.tf`, not inside the module.

- Decision: Treat `databricks_permissions` as authoritative per managed policy by using one permissions resource per policy.
- Rationale: The design calls for Terraform-owned full ACL management rather than additive grants.
- Consequences: Out-of-band grants on managed policies are not preserved.

## Open Questions

- Question: Will the Databricks provider reject malformed policy-definition structure during plan or only during apply for the target workspace?
- Why it matters: The implementation can validate JSON syntax locally, but provider behavior determines whether malformed Databricks policy rules fail pre-apply or remain apply-time only.
