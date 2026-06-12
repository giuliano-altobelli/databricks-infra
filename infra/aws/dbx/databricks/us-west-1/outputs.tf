output "workspace_host" {
  value = local.workspace_host
}

output "workspace_id" {
  value = local.workspace_id
}

output "bedrock_external_model_endpoint_ids" {
  description = "Map of Bedrock external model endpoint keys to Databricks serving endpoint IDs."
  value       = module.bedrock_external_model_endpoints.endpoint_ids
}

output "bedrock_external_model_endpoint_names" {
  description = "Map of Bedrock external model endpoint keys to Databricks serving endpoint names."
  value       = module.bedrock_external_model_endpoints.endpoint_names
}

output "bedrock_external_model_endpoint_urls" {
  description = "Map of Bedrock external model endpoint keys to Databricks serving endpoint URLs."
  value       = module.bedrock_external_model_endpoints.endpoint_urls
}

output "bedrock_external_model_served_entity_names" {
  description = "Nested map of Bedrock external model endpoint keys and served entity keys to Databricks served entity names."
  value       = module.bedrock_external_model_endpoints.served_entity_names
}
