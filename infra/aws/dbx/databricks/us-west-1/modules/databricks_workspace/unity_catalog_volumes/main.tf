locals {
  enabled_volumes = var.enabled ? var.volumes : {}

  volume_identity_keys = [
    for volume_key, volume in local.enabled_volumes :
    format(
      "%s.%s.%s",
      lower(trimspace(volume.catalog_name)),
      lower(trimspace(volume.schema_name)),
      lower(trimspace(volume.name))
    )
  ]

  duplicate_volume_identity_keys = toset([
    for key in local.volume_identity_keys : key
    if length([
      for seen in local.volume_identity_keys : seen if seen == key
    ]) > 1
  ])

  volume_grant_tuples = flatten([
    for volume_key, volume in local.enabled_volumes : [
      for grant in volume.grants : [
        for privilege in grant.privileges : {
          volume_key = volume_key
          principal  = grant.principal
          privilege  = privilege
        }
      ]
    ]
  ])

  volume_grant_tuple_keys = [
    for tuple in local.volume_grant_tuples :
    "${tuple.volume_key}:${tuple.principal}:${tuple.privilege}"
  ]

  duplicate_volume_grant_tuple_keys = toset([
    for key in local.volume_grant_tuple_keys : key
    if length([
      for seen in local.volume_grant_tuple_keys : seen if seen == key
    ]) > 1
  ])

  volume_grants_by_principal = {
    for volume_key, volume in local.enabled_volumes : volume_key => {
      for principal in sort(distinct([
        for grant in volume.grants : grant.principal
        ])) : principal => sort(distinct(flatten([
          for grant in volume.grants : grant.principal == principal ? grant.privileges : []
      ])))
    }
  }
}

resource "databricks_volume" "this" {
  for_each = local.enabled_volumes

  name         = each.value.name
  catalog_name = each.value.catalog_name
  schema_name  = each.value.schema_name
  volume_type  = each.value.volume_type
  comment      = try(each.value.comment, null)
  owner        = try(each.value.owner, null)

  storage_location = each.value.volume_type == "EXTERNAL" ? each.value.storage_location : null

  lifecycle {
    precondition {
      condition     = length(local.duplicate_volume_identity_keys) == 0
      error_message = "Duplicate volume identities are not allowed: ${join(", ", sort(tolist(local.duplicate_volume_identity_keys)))}"
    }
  }
}

resource "databricks_grants" "volume" {
  for_each = {
    for volume_key, volume in local.enabled_volumes :
    volume_key => volume
    if length(volume.grants) > 0
  }

  volume = databricks_volume.this[each.key].id

  dynamic "grant" {
    for_each = local.volume_grants_by_principal[each.key]

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_volume_grant_tuple_keys) == 0
      error_message = "Duplicate volume grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_volume_grant_tuple_keys)))}"
    }
  }
}
