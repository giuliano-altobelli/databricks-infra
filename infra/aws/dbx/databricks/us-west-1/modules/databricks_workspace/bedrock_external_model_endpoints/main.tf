locals {
  enabled_endpoints = var.enabled ? var.bedrock_external_model_endpoints : {}

  normalized_served_entities = {
    for endpoint_key, endpoint in local.enabled_endpoints : endpoint_key => {
      for served_entity_key in sort(keys(endpoint.served_entities)) : served_entity_key => endpoint.served_entities[served_entity_key]
    }
  }

  normalized_permissions = {
    for endpoint_key, endpoint in local.enabled_endpoints : endpoint_key => [
      for grant in endpoint.permissions : {
        principal_type   = grant.principal_type
        principal_name   = grant.principal_name
        permission_level = coalesce(try(grant.permission_level, null), "CAN_QUERY")
      }
    ]
  }

  flattened_permissions = flatten([
    for endpoint_key, permissions in local.normalized_permissions : [
      for grant in permissions : merge(grant, {
        endpoint_key = endpoint_key
      })
    ]
  ])

  permission_key_list = [
    for grant in local.flattened_permissions :
    "${grant.endpoint_key}:${grant.principal_type}:${grant.principal_name}:${grant.permission_level}"
  ]

  duplicate_permission_keys = toset([
    for key in local.permission_key_list : key
    if length([
      for seen in local.permission_key_list : seen if seen == key
    ]) > 1
  ])
}

resource "databricks_model_serving" "this" {
  for_each = local.enabled_endpoints

  name = each.value.name

  config {
    dynamic "served_entities" {
      for_each = local.normalized_served_entities[each.key]

      content {
        name = served_entities.value.name

        external_model {
          name     = served_entities.value.bedrock_model
          provider = "amazon-bedrock"
          task     = served_entities.value.task

          amazon_bedrock_config {
            aws_region           = each.value.aws_region
            bedrock_provider     = served_entities.value.bedrock_provider
            instance_profile_arn = each.value.instance_profile_arn
          }
        }
      }
    }

    traffic_config {
      dynamic "routes" {
        for_each = local.normalized_served_entities[each.key]

        content {
          served_entity_name = routes.value.name
          traffic_percentage = routes.value.traffic_percentage
        }
      }
    }
  }
}

resource "databricks_permissions" "serving_endpoint" {
  for_each = local.enabled_endpoints

  serving_endpoint_id = databricks_model_serving.this[each.key].serving_endpoint_id

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
      error_message = "Duplicate Bedrock external model endpoint permission tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_permission_keys)))}"
    }
  }
}
