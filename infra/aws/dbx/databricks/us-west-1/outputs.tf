output "workspace_host" {
  value = local.workspace_host
}

output "catalog_name" {
  description = "Compatibility alias for the sandbox personal catalog. Use output.catalogs for the authoritative catalog set."
  value       = local.catalog_name
}

output "catalogs" {
  description = "Managed governed catalogs, including the explicit personal catalog, keyed by stable Terraform identifiers."
  value = {
    for catalog_key, catalog in local.catalogs :
    catalog_key => {
      display_name                             = catalog.display_name
      catalog_kind                             = catalog.catalog_kind
      catalog_name                             = module.governed_catalogs[catalog_key].catalog_name
      catalog_bucket_name                      = module.governed_catalogs[catalog_key].catalog_bucket_name
      storage_credential_name                  = module.governed_catalogs[catalog_key].storage_credential_name
      storage_credential_external_id           = module.governed_catalogs[catalog_key].storage_credential_external_id
      storage_credential_unity_catalog_iam_arn = module.governed_catalogs[catalog_key].storage_credential_unity_catalog_iam_arn
      external_location_name                   = module.governed_catalogs[catalog_key].external_location_name
      iam_role_arn                             = module.governed_catalogs[catalog_key].iam_role_arn
      kms_key_arn                              = module.governed_catalogs[catalog_key].kms_key_arn
    }
  }

  precondition {
    condition     = length(local.invalid_catalog_type_managed_volume_schema_keys) == 0
    error_message = "Catalog type managed volumes must be declared only under schema keys defined in the same catalog type: ${join(", ", local.invalid_catalog_type_managed_volume_schema_keys)}."
  }
}
