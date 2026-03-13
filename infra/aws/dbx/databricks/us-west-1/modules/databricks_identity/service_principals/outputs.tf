output "ids" {
  description = "Map of service principal keys to Databricks service principal IDs."
  value       = local.service_principal_ids
}

output "application_ids" {
  description = "Map of service principal keys to Databricks application IDs."
  value       = local.service_principal_application_ids
}

output "display_names" {
  description = "Map of service principal keys to created display names."
  value       = local.service_principal_display_names
}

output "workspace_assignment_ids" {
  description = "Map of workspace assignment IDs keyed by service principal key."
  value       = { for principal_key, assignment in databricks_mws_permission_assignment.workspace : principal_key => assignment.id }
}

output "entitlements_ids" {
  description = "Map of workspace entitlement IDs keyed by service principal key."
  value       = { for principal_key, entitlement in databricks_entitlements.workspace : principal_key => entitlement.id }
}
