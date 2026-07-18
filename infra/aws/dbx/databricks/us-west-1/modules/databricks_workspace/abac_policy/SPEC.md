# Module Spec

## Summary

- **Module name**: `databricks_workspace/abac_policy`
- **One-liner**: Create catalog- or schema-scoped Unity Catalog ABAC row-filter policies with plan-time governed-tag and function validation.

## Scope

- In scope:
  - one `databricks_policy_info` row-filter resource per policy entry
  - catalog and schema policy scopes
  - table targets
  - one required and two optional ordered column-tag selectors
  - one optional table-tag selector
  - governed-tag key validation
  - governed-tag allowed-value validation only for selectors that reference a value
  - exact Unity Catalog function existence validation
- Out of scope:
  - column-mask policies
  - table policy scope
  - validation of function return type, definition, parameters, or behavior
  - inline functions
  - custom tag expressions
  - constant function arguments
  - governed-tag or function creation
  - root-module wiring

## Interfaces

- Optional inputs:
  - `enabled` (`bool`, default `true`)
  - `policies` (`map(object)`, default `{}`), keyed by policy name
  - `policies[*].scope.catalog` (`string`)
  - `policies[*].scope.schema` (`optional(string)`)
  - `policies[*].principals.include` (`set(string)`)
  - `policies[*].principals.exclude` (`optional(set(string))`)
  - `policies[*].table` (`optional(object)` with `key` and optional `value`)
  - `policies[*].columns.first` (required selector with `key`, optional `value`, and `alias`)
  - `policies[*].columns.second` (optional selector)
  - `policies[*].columns.third` (optional selector)
  - `policies[*].function` (three-part Unity Catalog function name)
  - `policies[*].comment` (`optional(string)`)
- Outputs:
  - `policies`: managed policy metadata keyed by policy name

## Behavior

- A null schema derives `on_securable_type = "CATALOG"` and uses the catalog as `on_securable_fullname`.
- A present schema derives `on_securable_type = "SCHEMA"` and joins catalog and schema for `on_securable_fullname`.
- Every resource uses `policy_type = "POLICY_TYPE_ROW_FILTER"` and `for_securable_type = "TABLE"`.
- A null table selector omits `when_condition`.
- A selector without a value renders `has_tag`.
- A selector with a value renders `has_tag_value`.
- Column aliases are rendered as `match_columns` and passed to `row_filter.using` in first, second, third order.
- Governed-tag and function data sources are read during planning.
- Validation completes before policy creation through an explicit dependency on the internal validation component.

## Constraints and Failure Modes

- Policy names, scope components, principals, tag keys, tag values, and aliases must be non-empty where present.
- Policy names and column aliases must be unique after trimming and lowercasing within their respective scopes.
- At least one included principal is required.
- `columns.first` is required; no more than three column selectors are representable.
- Function names must contain exactly three non-empty dot-delimited components.
- A missing governed-tag key fails while reading the tag data source or during validation if the returned key differs.
- A referenced value missing from the governed tag's allowed values fails validation.
- Key-only selectors do not inspect allowed values.
- A function absent from its catalog/schema function listing fails validation.
- Function metadata other than `full_name` does not participate in validation.
- Provider authorization or metadata visibility failures surface during planning.

## Validation

The deterministic plan suite partitions behavior across:

- catalog and schema scope
- absent and present table selectors
- one and three column selectors
- key-only and key/value selectors
- existing and missing governed-tag keys
- existing and missing allowed values
- existing and missing functions
- enabled and disabled module state

Verification commands:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/abac_policy init -backend=false`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/abac_policy validate`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1/modules/databricks_workspace/abac_policy test`
- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
