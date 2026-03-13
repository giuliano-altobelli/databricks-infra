output "warehouse_ids" {
  description = "Map of warehouse keys to Databricks SQL warehouse IDs."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.id }
}

output "warehouse_names" {
  description = "Map of warehouse keys to Databricks SQL warehouse display names."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.name }
}

output "jdbc_urls" {
  description = "Map of warehouse keys to Databricks SQL warehouse JDBC URLs."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.jdbc_url }
}

output "odbc_params" {
  description = "Map of warehouse keys to Databricks SQL warehouse ODBC connection parameters."
  value       = { for warehouse_key, warehouse in databricks_sql_endpoint.this : warehouse_key => warehouse.odbc_params }
}
