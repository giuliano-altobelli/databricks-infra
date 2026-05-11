output "tables" {
  description = "Managed Unity Catalog table grant targets keyed by stable caller-defined identifiers."
  value = {
    for table_key, table in databricks_grants.table :
    table_key => {
      catalog_name = local.enabled_tables[table_key].catalog_name
      schema_name  = local.enabled_tables[table_key].schema_name
      table_name   = local.enabled_tables[table_key].table_name
      full_name    = local.table_full_names[table_key]
    }
  }
}
