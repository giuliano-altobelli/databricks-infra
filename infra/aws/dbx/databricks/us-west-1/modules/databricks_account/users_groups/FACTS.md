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
| resource | `databricks_user` | `user_name` is required; `display_name` and `active` are optional; account-level users support `disable_as_user_deletion` default `true` when deleting. | registry: `databricks/databricks` `user` resource docs | Module uses `user_name`, `display_name`, `active`. |
| resource | `databricks_group` | `display_name` is required; `external_id` and `force` optional. | registry: `databricks/databricks` `group` resource docs | Module uses `display_name`. |
| resource | `databricks_group_member` | Requires `group_id` and `member_id`; resource ID/import format is `<group_id>|<member_id>`. | registry: `databricks/databricks` `group_member` resource docs | Membership key shape in module is `user:<user_key>:<group_key>`. |
| resource | `databricks_user_role` | Requires `user_id` and `role`; resource ID format is `<user_id>|<role>`; import is not supported. | registry: `databricks/databricks` `user_role` resource docs | Supports role names (e.g., `account_admin`) or instance profile identifiers. |
| resource | `databricks_group_role` | Requires `group_id` and `role`; resource ID format is `<group_id>|<role>`; import is not supported. | registry: `databricks/databricks` `group_role` resource docs | Supports role names (e.g., `account_admin`) or instance profile identifiers. |
| resource | `databricks_mws_permission_assignment` | Assigns users, groups, or service principals to workspace; requires `workspace_id`, `principal_id`, `permissions`; permissions allowed values are `USER` or `ADMIN`; import format is `<workspace_id>|<principal_id>`. | registry: `databricks/databricks` `mws_permission_assignment` resource docs | Must use account-level (`mws`) provider. |
| resource | `databricks_entitlements` | Must be used with workspace-level provider; exactly one of `user_id`, `group_id`, `service_principal_id`; entitlement fields default false. | registry: `databricks/databricks` `entitlements` resource docs | Module sets all entitlement fields when object is provided (authoritative). |
| context7 | `databricks provider checks` | `workspace_consume` cannot be used with `workspace_access` or `databricks_sql_access`. | context7: `/databricks/terraform-provider-databricks`, query topic `databricks_entitlements arguments and constraints` | Enforced in variable validation for users/groups entitlements. |
| context7 | `permission assignment values` | Confirmed workspace assignment permissions are `USER` and `ADMIN`. | context7: `/databricks/terraform-provider-databricks`, query topic `databricks_mws_permission_assignment arguments and allowed values` | Enforced in variable validation for workspace_permissions. |

## Decisions

- Decision: `prevent_destroy` defaults to `false` and applies only to users/groups.
- Rationale: Aligns with locked behavior in module plan; avoid blocking normal cleanup on derived resources.
- Consequences: Memberships/roles/assignments/entitlements remain fully managed and removable.

- Decision: Empty `groups = {}` is allowed by default (`allow_empty_groups = true`), with strict opt-in failure mode.
- Rationale: Preserve flexible module reuse while supporting stricter controls when requested.
- Consequences: Module hard-fails only when enabled and `allow_empty_groups = false`.

- Decision: Workspace scope is exactly one workspace per module invocation.
- Rationale: `databricks_mws_permission_assignment` and workspace provider alias imply a single workspace target.
- Consequences: Multi-workspace management requires multiple module instances.

## Open Questions

- Question: None.
- Why it matters: N/A.
