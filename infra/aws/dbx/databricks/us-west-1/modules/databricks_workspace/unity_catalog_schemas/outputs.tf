output "schemas" {
  description = "Managed Unity Catalog schemas keyed by stable caller-defined identifiers."
  value = {
    for schema_key, schema in databricks_schema.this :
    schema_key => {
      catalog_name = local.enabled_schemas[schema_key].catalog_name
      schema_name  = local.enabled_schemas[schema_key].schema_name
      full_name    = schema.id
    }
  }
}
