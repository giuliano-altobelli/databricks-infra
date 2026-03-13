locals {
  enabled_sql_warehouses = var.enabled ? var.sql_warehouses : {}

  normalized_permissions = {
    for warehouse_key, warehouse in local.enabled_sql_warehouses : warehouse_key => [
      for grant in warehouse.permissions : {
        principal_type   = grant.principal_type
        principal_name   = grant.principal_name
        permission_level = coalesce(try(grant.permission_level, null), "CAN_USE")
      }
    ]
  }

  flattened_permissions = flatten([
    for warehouse_key, permissions in local.normalized_permissions : [
      for grant in permissions : merge(grant, {
        warehouse_key = warehouse_key
      })
    ]
  ])

  permission_key_list = [
    for grant in local.flattened_permissions :
    "${grant.warehouse_key}:${grant.principal_type}:${grant.principal_name}:${grant.permission_level}"
  ]

  duplicate_permission_keys = toset([
    for key in local.permission_key_list : key
    if length([
      for seen in local.permission_key_list : seen if seen == key
    ]) > 1
  ])
}

resource "databricks_sql_endpoint" "this" {
  for_each = local.enabled_sql_warehouses

  name                      = each.value.name
  cluster_size              = each.value.cluster_size
  min_num_clusters          = try(each.value.min_num_clusters, null)
  max_num_clusters          = each.value.max_num_clusters
  auto_stop_mins            = try(each.value.auto_stop_mins, null)
  spot_instance_policy      = try(each.value.spot_instance_policy, null)
  enable_photon             = try(each.value.enable_photon, null)
  warehouse_type            = try(each.value.warehouse_type, null)
  enable_serverless_compute = each.value.enable_serverless_compute
  no_wait                   = try(each.value.no_wait, null)

  dynamic "channel" {
    for_each = try(each.value.channel, null) == null ? [] : [each.value.channel]

    content {
      name = coalesce(try(channel.value.name, null), "CHANNEL_NAME_CURRENT")
    }
  }

  dynamic "tags" {
    for_each = length(try(each.value.tags, {})) == 0 ? [] : [each.value.tags]

    content {
      dynamic "custom_tags" {
        for_each = tags.value

        content {
          key   = custom_tags.key
          value = custom_tags.value
        }
      }
    }
  }
}

resource "databricks_permissions" "sql_endpoint" {
  for_each = local.enabled_sql_warehouses

  sql_endpoint_id = databricks_sql_endpoint.this[each.key].id

  dynamic "access_control" {
    for_each = local.normalized_permissions[each.key]

    content {
      permission_level       = access_control.value.permission_level
      group_name             = access_control.value.principal_type == "group" ? access_control.value.principal_name : null
      user_name              = access_control.value.principal_type == "user" ? access_control.value.principal_name : null
      service_principal_name = access_control.value.principal_type == "service_principal" ? access_control.value.principal_name : null
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_permission_keys) == 0
      error_message = "Duplicate SQL warehouse permission tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_permission_keys)))}"
    }
  }
}
