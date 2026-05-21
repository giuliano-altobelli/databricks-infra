# Role Based Access Control Table Permissions
You are tasked with creating a databricks workspace module to support role based access controls on databricks managed tables.

# Examples
For example, the catalog `finance` and schema `raw` provision group A and group B read permissions, but only group B as read permissions to a set of tables (`foo`, `bar`).
The goal is to limit read permissions to group B only for tables `foo` and `bar`.

# Scope
1. It is important to limit permissions to be `READ` only.

# Resolved Decisions
1. Catalog/schema read means namespace access only: `USE_CATALOG` and `USE_SCHEMA`.
2. Table data access is managed separately through table-level `SELECT`.
3. The module manages grants only for existing Unity Catalog managed tables; it does not create tables.
4. Grants are authoritative for each listed table.
5. Start with tables only; views are out of scope.
6. The module interface exposes `reader_principals`, and the module hard-codes `SELECT`.
7. Catalog and schema prerequisite grants are handled by the existing catalog/schema grant modules.
8. A listed table must have at least one reader principal.
9. Duplicate table identities are rejected case-insensitively across stable keys.
10. Duplicate reader principals are rejected per table after trimming.
11. Blank reader principals are rejected after trimming.
12. Table entries are keyed by arbitrary stable caller-defined Terraform keys; object identity validation is handled separately from key names.
13. The module outputs a `tables` map keyed by the same stable caller-defined keys.
14. Implement a separate workspace module, `databricks_workspace/unity_catalog_table_permissions`, instead of extending schema creation.
15. The module uses only the workspace-scoped Databricks provider, wired by callers to `databricks.created_workspace`.
16. Root wiring depends on metastore assignment, identity groups, governed catalogs, and governed schemas; it does not depend on volumes.
17. Root table allowlists live in a new config file, e.g. `table_permissions_config.tf`, separate from catalog and schema topology.
18. Root table permission declarations reference `catalog_key`, `schema_name`, and `table_name`; the root resolves `catalog_name` from `module.governed_catalogs[catalog_key].catalog_name`.
19. Root table permission declarations reference identity group keys; the root resolves `reader_principals` from `local.identity_groups[group_key].display_name` and validates unknown group keys early.
20. The reusable module accepts resolved catalog names and principal names only; root-specific catalog keys and group keys stay in root locals.
21. Root validation rejects table permission entries that reference unknown or disabled catalog keys.
22. Root validation rejects table permission entries whose `schema_name` is not defined for the referenced catalog in the effective governed schema configuration.
23. Root validation rejects unknown identity group keys in table `reader_group_keys`.
24. Table `reader_group_keys` must not include catalog admin groups; administrative access is handled by the existing admin grant path.
25. Table `reader_group_keys` must be a subset of the referenced catalog's `reader_group` list.
26. Table permissions may target any effective governed schema for the catalog, including `uat`.
27. Preserve caller-provided casing in provider arguments and outputs; use lowercased trimmed identities only for validation and duplicate detection.
28. Do not use table data-source lookups. The module applies grants directly and lets `databricks_grants` fail if a table is missing.
29. Manage one authoritative `databricks_grants` resource per listed table, with one dynamic grant block per reader principal and `privileges = ["SELECT"]`.
30. Use the `databricks_grants` `table` argument with the fully qualified table name: `catalog_name.schema_name.table_name`.
31. Include `enabled` with default `true`; when `enabled = false`, create no resources and return `tables = {}`.
32. Create `modules/databricks_workspace/unity_catalog_table_permissions/SPEC.md` as the local implementation contract; keep this file as the higher-level decision log/design plan.
33. Add a module README with a minimal usage example and explicit notes that the module does not create tables or grant `USE_CATALOG`/`USE_SCHEMA`.
34. Add focused `terraform test` coverage for module validation failures, at minimum duplicate table identities and empty `reader_principals`.
35. Check in root `table_permissions_config.tf` with an empty default map plus commented examples, not live sample table grants.
36. Keep the root `unity_catalog_table_permissions` module call commented out until the governed catalog/schema root path is active.
37. Document that adopting a table into this module may remove out-of-band table grants because `databricks_grants` is authoritative; operators should inspect current grants and include every intended reader principal before adding a real table entry.
38. The reusable module allows any resolved principal name in `reader_principals`, including groups, users, and service principals.
39. The repo-specific root `table_permissions_config.tf` scaffold supports `reader_group_keys` only for now; direct user/service-principal exceptions can call the reusable module directly or be added later deliberately.
40. The module grants only `SELECT` for every principal type; ownership, write, manage, or admin privileges are out of scope.
41. `SELECT` is hard-coded with no variable override.
42. The module follows the existing layout: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `SPEC.md`, `README.md`, plus focused `.tftest.hcl` coverage.
43. Root verification uses the current repo command pattern with `terraform.tfvars` and `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 ...`.

# Verification
1. `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_table_permissions init -backend=false`
2. `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_table_permissions validate`
3. `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/unity_catalog_table_permissions test`
4. `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
5. `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
6. `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=terraform.tfvars`

# Constraints and Failure Modes
1. Tables must already exist before apply; missing tables are provider/runtime failures from `databricks_grants`.
2. Because grants are authoritative, adopting an existing table into this module can remove out-of-band table grants that are not represented in `reader_principals`.

# Root Validation
1. Reject unknown or disabled `catalog_key` values.
2. Reject `schema_name` values that are not part of the effective governed schema configuration for the referenced `catalog_key`.
3. Reject unknown identity group keys in `reader_group_keys`.
4. Reject table `reader_group_keys` entries that include the referenced catalog's admin group key.
5. Reject table `reader_group_keys` entries that are not included in the referenced catalog's `reader_group` list.

# Module Interface
1. `enabled = bool`, default `true`.
2. `tables = map(object({ catalog_name = string, schema_name = string, table_name = string, reader_principals = list(string) }))`.
3. `reader_principals` are resolved Databricks principal names and may represent groups, users, or service principals.

# Root Dependency Contract
1. `depends_on` should include `module.unity_catalog_metastore_assignment`, `module.users_groups`, `module.governed_catalogs`, and `module.unity_catalog_schemas`.

# Output Contract
1. `tables` includes `catalog_name`, `schema_name`, `table_name`, and `full_name` for each managed table grant target.

# Validation
1. Reject blank `catalog_name`, `schema_name`, or `table_name`.
2. Reject empty `reader_principals`.
3. Reject duplicate fully qualified table identities after trimming and lowercasing `catalog_name`, `schema_name`, and `table_name`.
4. Reject duplicate reader principals per table after trimming.
5. Reject blank reader principals after trimming.
6. Add `.tftest.hcl` coverage for duplicate table identities and empty `reader_principals`.
