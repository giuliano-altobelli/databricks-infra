output "catalog_bucket_name" {
  description = "Catalog bucket name."
  value       = var.enabled ? try(aws_s3_bucket.unity_catalog_bucket[0].bucket, null) : null
}

output "catalog_name" {
  description = "Name of the catalog created"
  value       = var.enabled ? try(databricks_catalog.workspace_catalog[0].name, null) : null
}

output "storage_credential_name" {
  description = "Name of the Databricks storage credential backing the catalog."
  value       = var.enabled ? try(databricks_storage_credential.workspace_catalog_storage_credential[0].name, null) : null
}

output "storage_credential_external_id" {
  description = "External ID emitted by Databricks for the storage credential IAM trust."
  value       = var.enabled ? try(databricks_storage_credential.workspace_catalog_storage_credential[0].aws_iam_role[0].external_id, null) : null
}

output "storage_credential_unity_catalog_iam_arn" {
  description = "Unity Catalog IAM ARN emitted by Databricks for the storage credential."
  value       = var.enabled ? try(databricks_storage_credential.workspace_catalog_storage_credential[0].aws_iam_role[0].unity_catalog_iam_arn, null) : null
}

output "external_location_name" {
  description = "Name of the Databricks external location backing the catalog."
  value       = var.enabled ? try(databricks_external_location.workspace_catalog_external_location[0].name, null) : null
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the storage credential."
  value       = var.enabled ? try(aws_iam_role.unity_catalog[0].arn, null) : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the catalog bucket."
  value       = var.enabled ? try(aws_kms_key.catalog_storage[0].arn, null) : null
}
