output "storage_credentials" {
  description = "Managed storage credentials keyed by stable caller-defined identifiers."
  value = {
    for credential_key, credential in databricks_storage_credential.this :
    credential_key => {
      name                  = credential.name
      databricks_id         = credential.storage_credential_id
      external_id           = try(credential.aws_iam_role[0].external_id, null)
      unity_catalog_iam_arn = try(credential.aws_iam_role[0].unity_catalog_iam_arn, null)
    }
  }
}

output "external_locations" {
  description = "Managed external locations keyed by stable caller-defined identifiers."
  value = {
    for external_location_key, external_location in databricks_external_location.this :
    external_location_key => {
      name            = external_location.name
      url             = external_location.url
      credential_name = databricks_storage_credential.this[local.enabled_external_locations[external_location_key].credential_key].name
    }
  }
}
