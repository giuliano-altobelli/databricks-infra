locals {
  enabled_storage_credentials = var.enabled ? var.storage_credentials : {}
  enabled_external_locations  = var.enabled ? var.external_locations : {}

  storage_credential_grant_tuples = flatten([
    for credential_key, credential in local.enabled_storage_credentials : [
      for grant in credential.grants : [
        for privilege in grant.privileges : {
          securable_key = credential_key
          principal     = grant.principal
          privilege     = privilege
        }
      ]
    ]
  ])

  storage_credential_grant_tuple_keys = [
    for tuple in local.storage_credential_grant_tuples :
    "${tuple.securable_key}:${tuple.principal}:${tuple.privilege}"
  ]

  duplicate_storage_credential_grant_tuple_keys = toset([
    for key in local.storage_credential_grant_tuple_keys : key
    if length([
      for seen in local.storage_credential_grant_tuple_keys : seen if seen == key
    ]) > 1
  ])

  external_location_grant_tuples = flatten([
    for external_location_key, external_location in local.enabled_external_locations : [
      for grant in external_location.grants : [
        for privilege in grant.privileges : {
          securable_key = external_location_key
          principal     = grant.principal
          privilege     = privilege
        }
      ]
    ]
  ])

  external_location_grant_tuple_keys = [
    for tuple in local.external_location_grant_tuples :
    "${tuple.securable_key}:${tuple.principal}:${tuple.privilege}"
  ]

  duplicate_external_location_grant_tuple_keys = toset([
    for key in local.external_location_grant_tuple_keys : key
    if length([
      for seen in local.external_location_grant_tuple_keys : seen if seen == key
    ]) > 1
  ])

  storage_credential_grants_by_principal = {
    for credential_key, credential in local.enabled_storage_credentials : credential_key => {
      for principal in sort(distinct([
        for grant in credential.grants : grant.principal
        ])) : principal => sort(distinct(flatten([
          for grant in credential.grants : grant.principal == principal ? grant.privileges : []
      ])))
    }
  }

  external_location_grants_by_principal = {
    for external_location_key, external_location in local.enabled_external_locations : external_location_key => {
      for principal in sort(distinct([
        for grant in external_location.grants : grant.principal
        ])) : principal => sort(distinct(flatten([
          for grant in external_location.grants : grant.principal == principal ? grant.privileges : []
      ])))
    }
  }

  raw_storage_credential_binding_tuples = flatten([
    for credential_key, credential in local.enabled_storage_credentials : [
      for workspace_id in credential.workspace_access_mode == "ISOLATION_MODE_ISOLATED" ? concat([var.current_workspace_id], credential.workspace_ids) : [] : {
        binding_key    = "${credential_key}:${workspace_id}"
        credential_key = credential_key
        workspace_id   = workspace_id
      }
    ]
  ])

  raw_storage_credential_binding_keys = [
    for binding in local.raw_storage_credential_binding_tuples : binding.binding_key
  ]

  duplicate_storage_credential_binding_keys = toset([
    for key in local.raw_storage_credential_binding_keys : key
    if length([
      for seen in local.raw_storage_credential_binding_keys : seen if seen == key
    ]) > 1
  ])

  storage_credential_bindings = {
    for binding in flatten([
      for credential_key, credential in local.enabled_storage_credentials : [
        for workspace_id in credential.workspace_access_mode == "ISOLATION_MODE_ISOLATED" ? distinct(concat([var.current_workspace_id], credential.workspace_ids)) : [] : {
          binding_key    = "${credential_key}:${workspace_id}"
          credential_key = credential_key
          workspace_id   = workspace_id
        }
      ]
    ]) : binding.binding_key => binding
  }

  raw_external_location_binding_tuples = flatten([
    for external_location_key, external_location in local.enabled_external_locations : [
      for workspace_id in external_location.workspace_access_mode == "ISOLATION_MODE_ISOLATED" ? concat([var.current_workspace_id], external_location.workspace_ids) : [] : {
        binding_key           = "${external_location_key}:${workspace_id}"
        external_location_key = external_location_key
        workspace_id          = workspace_id
      }
    ]
  ])

  raw_external_location_binding_keys = [
    for binding in local.raw_external_location_binding_tuples : binding.binding_key
  ]

  duplicate_external_location_binding_keys = toset([
    for key in local.raw_external_location_binding_keys : key
    if length([
      for seen in local.raw_external_location_binding_keys : seen if seen == key
    ]) > 1
  ])

  external_location_bindings = {
    for binding in flatten([
      for external_location_key, external_location in local.enabled_external_locations : [
        for workspace_id in external_location.workspace_access_mode == "ISOLATION_MODE_ISOLATED" ? distinct(concat([var.current_workspace_id], external_location.workspace_ids)) : [] : {
          binding_key           = "${external_location_key}:${workspace_id}"
          external_location_key = external_location_key
          workspace_id          = workspace_id
        }
      ]
    ]) : binding.binding_key => binding
  }
}

resource "databricks_storage_credential" "this" {
  for_each = local.enabled_storage_credentials

  name            = each.value.name
  owner           = try(each.value.owner, null)
  comment         = try(each.value.comment, null)
  read_only       = each.value.read_only
  skip_validation = each.value.skip_validation
  force_destroy   = each.value.force_destroy
  force_update    = each.value.force_update
  isolation_mode  = each.value.workspace_access_mode

  aws_iam_role {
    role_arn = each.value.role_arn
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_storage_credential_grant_tuple_keys) == 0
      error_message = "Duplicate storage credential grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_storage_credential_grant_tuple_keys)))}"
    }

    precondition {
      condition     = length(local.duplicate_storage_credential_binding_keys) == 0
      error_message = "Duplicate storage credential workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_storage_credential_binding_keys)))}"
    }
  }
}

resource "databricks_grants" "storage_credential" {
  for_each = {
    for credential_key, credential in local.enabled_storage_credentials :
    credential_key => credential
    if length(credential.grants) > 0
  }

  storage_credential = databricks_storage_credential.this[each.key].name

  dynamic "grant" {
    for_each = local.storage_credential_grants_by_principal[each.key]

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_storage_credential_grant_tuple_keys) == 0
      error_message = "Duplicate storage credential grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_storage_credential_grant_tuple_keys)))}"
    }
  }
}

resource "databricks_workspace_binding" "storage_credential" {
  for_each = local.storage_credential_bindings

  securable_type = "storage_credential"
  securable_name = databricks_storage_credential.this[each.value.credential_key].name
  workspace_id   = tonumber(each.value.workspace_id)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_storage_credential_binding_keys) == 0
      error_message = "Duplicate storage credential workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_storage_credential_binding_keys)))}"
    }
  }
}

resource "databricks_external_location" "this" {
  for_each = local.enabled_external_locations

  name            = each.value.name
  url             = each.value.url
  credential_name = databricks_storage_credential.this[each.value.credential_key].name
  owner           = try(each.value.owner, null)
  comment         = try(each.value.comment, null)
  read_only       = each.value.read_only
  skip_validation = each.value.skip_validation
  fallback        = each.value.fallback
  isolation_mode  = each.value.workspace_access_mode

  dynamic "encryption_details" {
    for_each = try(each.value.encryption_details, null) == null ? [] : [each.value.encryption_details]

    content {
      sse_encryption_details {
        algorithm       = encryption_details.value.sse_encryption_details.algorithm
        aws_kms_key_arn = try(encryption_details.value.sse_encryption_details.aws_kms_key_arn, null)
      }
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_external_location_grant_tuple_keys) == 0
      error_message = "Duplicate external location grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_external_location_grant_tuple_keys)))}"
    }

    precondition {
      condition     = length(local.duplicate_external_location_binding_keys) == 0
      error_message = "Duplicate external location workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_external_location_binding_keys)))}"
    }
  }
}

resource "databricks_grants" "external_location" {
  for_each = {
    for external_location_key, external_location in local.enabled_external_locations :
    external_location_key => external_location
    if length(external_location.grants) > 0
  }

  external_location = databricks_external_location.this[each.key].name

  dynamic "grant" {
    for_each = local.external_location_grants_by_principal[each.key]

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_external_location_grant_tuple_keys) == 0
      error_message = "Duplicate external location grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_external_location_grant_tuple_keys)))}"
    }
  }
}

resource "databricks_workspace_binding" "external_location" {
  for_each = local.external_location_bindings

  securable_type = "external_location"
  securable_name = databricks_external_location.this[each.value.external_location_key].name
  workspace_id   = tonumber(each.value.workspace_id)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_external_location_binding_keys) == 0
      error_message = "Duplicate external location workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_external_location_binding_keys)))}"
    }
  }
}
