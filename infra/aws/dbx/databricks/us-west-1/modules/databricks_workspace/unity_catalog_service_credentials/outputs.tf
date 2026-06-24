output "service_credentials" {
  description = "Managed Unity Catalog service credentials keyed by stable caller-defined identifiers."
  value = {
    for credential_key, credential in databricks_credential.this :
    credential_key => {
      name                  = credential.name
      id                    = credential.id
      credential_id         = try(credential.credential_id, null)
      full_name             = try(credential.full_name, null)
      external_id           = try(credential.aws_iam_role[0].external_id, null)
      unity_catalog_iam_arn = try(credential.aws_iam_role[0].unity_catalog_iam_arn, null)
    }
  }
}

output "grant_ids" {
  description = "Map of grant resource IDs keyed by service credential key."
  value       = { for credential_key, grant in databricks_grants.credential : credential_key => grant.id }
}

output "workspace_binding_ids" {
  description = "Map of workspace binding IDs keyed by service credential key and workspace ID."
  value       = { for binding_key, binding in databricks_workspace_binding.credential : binding_key => binding.id }
}
