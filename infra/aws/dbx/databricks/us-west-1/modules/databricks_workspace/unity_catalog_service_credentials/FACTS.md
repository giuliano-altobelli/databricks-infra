# Facts Ledger (Docs -> Durable Facts)

Use this file to keep retrieved documentation out of chat context.

Rules:

- Record only the minimum durable facts needed to implement the module.
- Prefer 1-2 lines per fact; do not paste large doc blocks.
- Always include a source pointer you can re-fetch later.

## Facts

| Area | Item | Fact (short) | Source | Notes |
| --- | --- | --- | --- | --- |
| resource | `databricks_credential` | Service credentials are managed by `databricks_credential` with `purpose = "SERVICE"`, not by a separate `databricks_service_credential` resource. | Context7 query for `/databricks/terraform-provider-databricks`; provider docs `docs/resources/credential.md` | Module name can use the domain term `service_credentials`, but implementation uses `databricks_credential`. |
| cloud | AWS | AWS service credentials use an `aws_iam_role` block with `role_arn`. | Provider docs `docs/resources/credential.md` | Phase 1 accepts caller-supplied role ARNs only. |
| grants | `databricks_grants` | Service credential grants use `credential = databricks_credential.<name>.id`; `ACCESS` lets principals use the service credential. | Provider docs `docs/resources/grants.md`; Context7 query | Phase 1 restricts module grants to `ACCESS`. |
| provider | workspace scope | Unity Catalog credential resources, grants, and workspace bindings use a workspace-scoped Databricks provider in this repo. | Local provider pattern in `unity_catalog_storage_locations`; root `provider.tf` | Caller wires `databricks = databricks.created_workspace`. |
| bindings | workspace restriction | Workspace restriction uses credential `isolation_mode` plus `databricks_workspace_binding` resources for isolated mode. | Provider docs `workspace_binding.md`; storage-location module precedent | Phase 1 mirrors the storage-location module binding pattern. |
| AWS trust | generated fields | AWS IAM trust orchestration can need Databricks-generated `external_id` and `unity_catalog_iam_arn`. | Provider credential schema and storage-location module precedent | Module exposes these outputs, but does not patch IAM. |

## Decisions

- Decision: Place the module under `databricks_workspace/unity_catalog_service_credentials`.
- Rationale: This repo groups Unity Catalog securables managed through workspace-scoped provider APIs under `databricks_workspace`.
- Consequences: The module takes only the default `databricks` provider alias from callers, wired to `databricks.created_workspace`.

- Decision: Accept Databricks-native principal strings in the child module.
- Rationale: Root config owns repo-specific identity-key resolution.
- Consequences: The child module stays generic and reusable.

- Decision: Restrict grants to `ACCESS` in phase 1.
- Rationale: The phase-1 goal is to let approved principals use credentials, not administer them or create federation connections.
- Consequences: `MANAGE`, `CREATE_CONNECTION`, and `ALL_PRIVILEGES` are future work.

## Open Questions

- Which future root consumer should enable this path first: Bedrock service credentials, Lakehouse Federation, or another external service?
- Should a companion AWS module eventually patch role trust from the emitted Databricks trust outputs?
