locals {
  enabled = var.enabled ? var.policies : {}

  columns = {
    for name, policy in local.enabled : name => [
      for column in [policy.columns.first, policy.columns.second, policy.columns.third] : {
        key   = trimspace(column.key)
        value = column.value == null ? null : trimspace(column.value)
        alias = trimspace(column.alias)
      }
      if column != null
    ]
  }

  tags = flatten([
    for name, policy in local.enabled : concat(
      policy.table == null ? [] : [{
        policy = name
        key    = trimspace(policy.table.key)
        value  = policy.table.value == null ? null : trimspace(policy.table.value)
      }],
      [
        for column in local.columns[name] : {
          policy = name
          key    = column.key
          value  = column.value
        }
      ]
    )
  ])

  functions = {
    for name, policy in local.enabled : name => {
      name    = join(".", [for part in split(".", trimspace(policy.function)) : trimspace(part)])
      catalog = trimspace(split(".", policy.function)[0])
      schema  = trimspace(split(".", policy.function)[1])
      parent  = join(".", [for part in slice(split(".", trimspace(policy.function)), 0, 2) : trimspace(part)])
    }
  }

  schemas = {
    for parent in toset([
      for function in values(local.functions) : function.parent
      ]) : parent => {
      catalog = split(".", parent)[0]
      schema  = split(".", parent)[1]
    }
  }
}

data "databricks_tag_policy" "tag" {
  for_each = toset([for tag in local.tags : tag.key])

  tag_key = each.key
}

data "databricks_functions" "function" {
  for_each = local.schemas

  catalog_name   = each.value.catalog
  schema_name    = each.value.schema
  include_browse = true
}

module "validation" {
  source = "./validation"

  policies = {
    for name in keys(local.enabled) : name => {
      tags = [
        for tag in local.tags : {
          key     = tag.key
          actual  = data.databricks_tag_policy.tag[tag.key].tag_key
          value   = tag.value
          allowed = tag.value == null ? toset([]) : toset([for value in data.databricks_tag_policy.tag[tag.key].values : value.name])
        }
        if tag.policy == name
      ]
      function = {
        name = local.functions[name].name
        available = toset([
          for function in data.databricks_functions.function[local.functions[name].parent].functions : function.full_name
        ])
      }
    }
  }
}

resource "databricks_policy_info" "policy" {
  for_each = local.enabled

  name                  = trimspace(each.key)
  on_securable_type     = each.value.scope.schema == null ? "CATALOG" : "SCHEMA"
  on_securable_fullname = each.value.scope.schema == null ? trimspace(each.value.scope.catalog) : "${trimspace(each.value.scope.catalog)}.${trimspace(each.value.scope.schema)}"
  policy_type           = "POLICY_TYPE_ROW_FILTER"
  for_securable_type    = "TABLE"
  to_principals         = sort([for principal in each.value.principals.include : trimspace(principal)])
  except_principals     = sort([for principal in each.value.principals.exclude : trimspace(principal)])
  comment               = each.value.comment == null ? null : trimspace(each.value.comment)
  when_condition = each.value.table == null ? null : (
    each.value.table.value == null ?
    "has_tag('${replace(trimspace(each.value.table.key), "'", "''")}')" :
    "has_tag_value('${replace(trimspace(each.value.table.key), "'", "''")}', '${replace(trimspace(each.value.table.value), "'", "''")}')"
  )

  match_columns = [
    for column in local.columns[each.key] : {
      alias = column.alias
      condition = (
        column.value == null ?
        "has_tag('${replace(column.key, "'", "''")}')" :
        "has_tag_value('${replace(column.key, "'", "''")}', '${replace(column.value, "'", "''")}')"
      )
    }
  ]

  row_filter = {
    function_name = local.functions[each.key].name
    using = [
      for column in local.columns[each.key] : {
        alias = column.alias
      }
    ]
  }

  depends_on = [module.validation]
}
