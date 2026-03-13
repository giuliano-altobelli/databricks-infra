locals {
  enabled_schemas = var.enabled ? var.schemas : {}

  schema_identity_keys = [
    for schema_key, schema in local.enabled_schemas :
    format(
      "%s.%s",
      lower(trimspace(schema.catalog_name)),
      lower(trimspace(schema.schema_name))
    )
  ]

  duplicate_schema_identity_keys = toset([
    for key in local.schema_identity_keys : key
    if length([
      for seen in local.schema_identity_keys : seen if seen == key
    ]) > 1
  ])

  schema_grant_tuples = flatten([
    for schema_key, schema in local.enabled_schemas : [
      for grant in schema.grants : [
        for privilege in grant.privileges : {
          schema_key = schema_key
          principal  = grant.principal
          privilege  = privilege
        }
      ]
    ]
  ])

  schema_grant_tuple_keys = [
    for tuple in local.schema_grant_tuples :
    "${tuple.schema_key}:${tuple.principal}:${tuple.privilege}"
  ]

  duplicate_schema_grant_tuple_keys = toset([
    for key in local.schema_grant_tuple_keys : key
    if length([
      for seen in local.schema_grant_tuple_keys : seen if seen == key
    ]) > 1
  ])

  schema_grants_by_principal = {
    for schema_key, schema in local.enabled_schemas : schema_key => {
      for principal in sort(distinct([
        for grant in schema.grants : grant.principal
        ])) : principal => sort(distinct(flatten([
          for grant in schema.grants : grant.principal == principal ? grant.privileges : []
      ])))
    }
  }
}

resource "databricks_schema" "this" {
  for_each = local.enabled_schemas

  catalog_name = each.value.catalog_name
  name         = each.value.schema_name
  comment      = try(each.value.comment, null)
  properties   = try(each.value.properties, null)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_schema_identity_keys) == 0
      error_message = "Duplicate schema identities are not allowed: ${join(", ", sort(tolist(local.duplicate_schema_identity_keys)))}"
    }
  }
}

resource "databricks_grants" "schema" {
  for_each = {
    for schema_key, schema in local.enabled_schemas :
    schema_key => schema
    if length(schema.grants) > 0
  }

  schema = databricks_schema.this[each.key].id

  dynamic "grant" {
    for_each = local.schema_grants_by_principal[each.key]

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_schema_grant_tuple_keys) == 0
      error_message = "Duplicate schema grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_schema_grant_tuple_keys)))}"
    }
  }
}
