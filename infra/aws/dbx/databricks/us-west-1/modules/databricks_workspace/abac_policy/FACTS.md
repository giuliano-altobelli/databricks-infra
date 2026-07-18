# Facts

| Area | Fact | Source | Module consequence |
|---|---|---|---|
| ABAC policy | `databricks_policy_info` supports catalog, schema, and table attachment, row-filter and column-mask policy types, table targets, tag conditions, matched columns, and function arguments. | Terraform Registry: `databricks_policy_info` | Phase 1 constrains attachment to catalog/schema and policy type to row filter. |
| Governed tags | ABAC row-filter and column-mask policies use governed tags. | Databricks: `data-governance/unity-catalog/abac/requirements` | Every referenced tag is read through `databricks_tag_policy` during planning. |
| Tag conditions | `has_tag('tag_name')` checks a key; `has_tag_value('tag_name', 'tag_value')` checks a key/value pair. | Databricks: `data-governance/unity-catalog/abac/policies` | Allowed values are validated only when the selector includes `value`. |
| Match columns | A policy can contain at most three `MATCH COLUMNS` expressions. | Databricks: `data-governance/unity-catalog/abac/policies` | The input exposes required `first` and optional `second`/`third` selectors. |
| Functions | `databricks_functions` lists Unity Catalog functions and returns `full_name` plus function metadata. | Terraform Registry: `databricks_functions` | Validation compares only exact `full_name`; return metadata is ignored. |
| Provider | ABAC policy, tag-policy data, and function-list interfaces are available in Databricks provider 1.121.0. | Terraform Registry release 1.121.0 | The module requires `>= 1.121.0, < 2.0.0`. |
