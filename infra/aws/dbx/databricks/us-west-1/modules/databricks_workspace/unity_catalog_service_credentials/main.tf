locals {
  enabled_service_credentials = var.enabled ? var.service_credentials : {}

  credential_grant_tuples = flatten([
    for credential_key, credential in local.enabled_service_credentials : [
      for grant in credential.grants : [
        for privilege in grant.privileges : {
          securable_key = credential_key
          principal     = grant.principal
          privilege     = privilege
        }
      ]
    ]
  ])

  credential_grant_tuple_keys = [
    for tuple in local.credential_grant_tuples :
    "${tuple.securable_key}:${tuple.principal}:${tuple.privilege}"
  ]

  duplicate_credential_grant_tuple_keys = toset([
    for key in local.credential_grant_tuple_keys : key
    if length([
      for seen in local.credential_grant_tuple_keys : seen if seen == key
    ]) > 1
  ])

  credential_grants_by_principal = {
    for credential_key, credential in local.enabled_service_credentials : credential_key => {
      for principal in sort(distinct([
        for grant in credential.grants : grant.principal
        ])) : principal => sort(distinct(flatten([
          for grant in credential.grants : grant.principal == principal ? grant.privileges : []
      ])))
    }
  }

  raw_credential_binding_tuples = flatten([
    for credential_key, credential in local.enabled_service_credentials : [
      for workspace_id in credential.workspace_access_mode == "ISOLATION_MODE_ISOLATED" ? concat([var.current_workspace_id], credential.workspace_ids) : [] : {
        binding_key    = "${credential_key}:${workspace_id}"
        credential_key = credential_key
        workspace_id   = workspace_id
      }
    ]
  ])

  raw_credential_binding_keys = [
    for binding in local.raw_credential_binding_tuples : binding.binding_key
  ]

  duplicate_credential_binding_keys = toset([
    for key in local.raw_credential_binding_keys : key
    if length([
      for seen in local.raw_credential_binding_keys : seen if seen == key
    ]) > 1
  ])

  credential_bindings = {
    for binding in flatten([
      for credential_key, credential in local.enabled_service_credentials : [
        for workspace_id in credential.workspace_access_mode == "ISOLATION_MODE_ISOLATED" ? distinct(concat([var.current_workspace_id], credential.workspace_ids)) : [] : {
          binding_key    = "${credential_key}:${workspace_id}"
          credential_key = credential_key
          workspace_id   = workspace_id
        }
      ]
    ]) : binding.binding_key => binding
  }
}

resource "databricks_credential" "this" {
  for_each = local.enabled_service_credentials

  name            = each.value.name
  purpose         = "SERVICE"
  comment         = try(each.value.comment, null)
  owner           = try(each.value.owner, null)
  skip_validation = each.value.skip_validation
  force_destroy   = each.value.force_destroy
  force_update    = each.value.force_update
  isolation_mode  = each.value.workspace_access_mode

  aws_iam_role {
    role_arn = each.value.aws.role_arn
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_credential_grant_tuple_keys) == 0
      error_message = "Duplicate service credential grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_credential_grant_tuple_keys)))}"
    }

    precondition {
      condition     = length(local.duplicate_credential_binding_keys) == 0
      error_message = "Duplicate service credential workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_credential_binding_keys)))}"
    }
  }
}

resource "databricks_grants" "credential" {
  for_each = {
    for credential_key, credential in local.enabled_service_credentials :
    credential_key => credential
    if length(credential.grants) > 0
  }

  credential = databricks_credential.this[each.key].id

  dynamic "grant" {
    for_each = local.credential_grants_by_principal[each.key]

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.duplicate_credential_grant_tuple_keys) == 0
      error_message = "Duplicate service credential grant tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_credential_grant_tuple_keys)))}"
    }
  }
}

resource "databricks_workspace_binding" "credential" {
  for_each = local.credential_bindings

  securable_type = "credential"
  securable_name = databricks_credential.this[each.value.credential_key].name
  workspace_id   = tonumber(each.value.workspace_id)

  lifecycle {
    precondition {
      condition     = length(local.duplicate_credential_binding_keys) == 0
      error_message = "Duplicate service credential workspace binding tuples are not allowed: ${join(", ", sort(tolist(local.duplicate_credential_binding_keys)))}"
    }
  }
}
