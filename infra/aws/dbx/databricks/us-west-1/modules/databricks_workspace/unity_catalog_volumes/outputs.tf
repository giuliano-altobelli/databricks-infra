output "volumes" {
  description = "Managed Unity Catalog volumes keyed by stable caller-defined identifiers."
  value = {
    for volume_key, volume in databricks_volume.this :
    volume_key => {
      name             = volume.name
      catalog_name     = local.enabled_volumes[volume_key].catalog_name
      schema_name      = local.enabled_volumes[volume_key].schema_name
      full_name        = volume.id
      volume_type      = local.enabled_volumes[volume_key].volume_type
      storage_location = local.enabled_volumes[volume_key].volume_type == "EXTERNAL" ? local.enabled_volumes[volume_key].storage_location : null
    }
  }
}
