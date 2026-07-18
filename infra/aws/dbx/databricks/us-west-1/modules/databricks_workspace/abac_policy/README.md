# ABAC Policy Module

This workspace-scoped module creates Unity Catalog ABAC row-filter policies on catalogs or schemas. Every policy targets tables, requires one column-tag selector, supports two additional column-tag selectors, and may include one table-tag selector.

## Usage

```hcl
module "abac_policy" {
  source = "./modules/databricks_workspace/abac_policy"

  providers = {
    databricks = databricks.created_workspace
  }

  policies = {
    restrict_tenant = {
      scope = {
        catalog = "governed"
        schema  = "protected"
      }
      principals = {
        include = ["account users"]
        exclude = ["platform administrators"]
      }
      table = {
        key   = "sensitivity"
        value = "restricted"
      }
      columns = {
        first = {
          key   = "tenant"
          value = "identifier"
          alias = "tenant"
        }
        second = {
          key   = "region"
          alias = "region"
        }
      }
      function = "governed.security.filter_tenant"
      comment  = "Restrict protected tenant rows."
    }
  }
}
```

Omit `scope.schema` for catalog scope. Omit `table` to apply the policy to every table in scope. `columns.first` is required; `columns.second` and `columns.third` are optional. Column aliases are passed to the row-filter function in first, second, third order.

## Plan-Time Validation

The module reads every referenced governed tag with `databricks_tag_policy` and lists functions in every referenced Unity Catalog schema with `databricks_functions` during planning.

- A selector without `value` renders `has_tag('key')` and validates only the returned tag key.
- A selector with `value` renders `has_tag_value('key', 'value')` and validates both the returned tag key and allowed value.
- The row-filter function must appear by exact three-part name in the referenced schema.
- Function return type, body, parameters, and return behavior are intentionally not validated.

A missing tag data source, missing allowed value, or absent function fails the plan before the policy resource can be created. The deployment identity therefore needs enough Unity Catalog metadata access to read the referenced governed tags and functions.

## Scope

Phase 1 supports only `POLICY_TYPE_ROW_FILTER` policies targeting tables from catalog or schema scope. Table-scoped policies, custom boolean tag expressions, constant function arguments, inline functions, and column-mask policies are out of scope. The selector and validation layers are separate from resource construction so column masking can be added without weakening the shared tag and function checks.

## Outputs

`policies` is keyed by policy name. Each value contains the provider ID, policy name and type, table target, and scope type/name. When `enabled = false`, no data sources or resources are evaluated and the output is empty.

## Verification

```shell
terraform init -backend=false
terraform validate
terraform test
```
