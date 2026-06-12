output "endpoint_ids" {
  description = "Map of endpoint keys to Databricks serving endpoint IDs."
  value       = { for endpoint_key, endpoint in databricks_model_serving.this : endpoint_key => endpoint.serving_endpoint_id }
}

output "endpoint_names" {
  description = "Map of endpoint keys to Databricks serving endpoint names."
  value       = { for endpoint_key, endpoint in databricks_model_serving.this : endpoint_key => endpoint.name }
}

output "endpoint_urls" {
  description = "Map of endpoint keys to Databricks serving endpoint URLs."
  value       = { for endpoint_key, endpoint in databricks_model_serving.this : endpoint_key => endpoint.endpoint_url }
}

output "served_entity_names" {
  description = "Nested map of endpoint keys and served entity keys to Databricks served entity names."
  value = {
    for endpoint_key, served_entities in local.normalized_served_entities : endpoint_key => {
      for served_entity_key, served_entity in served_entities : served_entity_key => served_entity.name
    }
  }
}
