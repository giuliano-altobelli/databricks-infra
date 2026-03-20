# locals {
#   sandbox_group_display_names = [for group in values(local.identity_groups) : group.display_name]
#   sandbox_group_roles         = flatten([for group in values(local.identity_groups) : try(group.roles, [])])

#   sandbox_enabled_catalog_domains = [
#     for domain in values(local.normalized_governed_catalog_domains) : domain
#     if domain.enabled
#   ]

#   sandbox_service_principal_names = [
#     for principal in values(local.service_principals_identity) : principal.display_name
#   ]

#   sandbox_sql_warehouse_names = [
#     for warehouse in values(local.sql_warehouses) : warehouse.name
#   ]

#   sandbox_cluster_policy_names = [
#     for policy in values(local.cluster_policies) : policy.name
#   ]

#   sandbox_storage_credential_names = [
#     for credential in values(local.uc_storage_credentials) : credential.name
#   ]

#   sandbox_external_location_names = [
#     for location in values(local.uc_external_locations) : location.name
#   ]
# }

# check "sandbox_run_shape" {
#   assert {
#     condition = (
#       var.resource_prefix == "sandbox-infra" &&
#       var.pricing_tier == "PREMIUM" &&
#       var.workspace_source == "create" &&
#       var.network_configuration == "managed" &&
#       var.metastore_exists &&
#       var.existing_workspace_host == null &&
#       var.existing_workspace_id == null
#     )
#     error_message = "Sandbox runs must use sandbox-infra, PREMIUM, workspace_source=create, managed networking, metastore_exists=true, and null existing workspace values."
#   }
# }

# check "sandbox_groups_prefixed" {
#   assert {
#     condition     = alltrue([for name in local.sandbox_group_display_names : startswith(name, "Sandbox ")])
#     error_message = "All Terraform-managed sandbox group display names must start with \"Sandbox \"."
#   }
# }

# check "sandbox_groups_no_account_roles" {
#   assert {
#     condition     = alltrue([for role in local.sandbox_group_roles : role != "account_admin"])
#     error_message = "Sandbox-managed groups must not grant account-wide roles such as account_admin."
#   }
# }

# check "sandbox_catalogs_explicit_and_prefixed" {
#   assert {
#     condition = alltrue([
#       for domain in local.sandbox_enabled_catalog_domains :
#       domain.catalog_name != "" &&
#       startswith(domain.catalog_name, "sandbox_") &&
#       domain.display_name != "" &&
#       startswith(domain.display_name, "Sandbox ")
#     ])
#     error_message = "Enabled sandbox catalogs must set explicit sandbox-prefixed catalog_name and display_name values."
#   }
# }

# check "sandbox_service_principals_prefixed" {
#   assert {
#     condition     = alltrue([for name in local.sandbox_service_principal_names : startswith(name, "Sandbox ")])
#     error_message = "Sandbox service principal display names must start with \"Sandbox \"."
#   }
# }

# check "sandbox_sql_warehouses_prefixed" {
#   assert {
#     condition     = alltrue([for name in local.sandbox_sql_warehouse_names : startswith(name, "Sandbox ")])
#     error_message = "Sandbox SQL warehouse names must start with \"Sandbox \"."
#   }
# }

# check "sandbox_cluster_policies_prefixed" {
#   assert {
#     condition     = alltrue([for name in local.sandbox_cluster_policy_names : startswith(name, "Sandbox ")])
#     error_message = "Sandbox cluster policy names must start with \"Sandbox \"."
#   }
# }

# check "sandbox_storage_credentials_prefixed" {
#   assert {
#     condition     = alltrue([for name in local.sandbox_storage_credential_names : startswith(name, "sandbox-")])
#     error_message = "Sandbox storage credential names must start with \"sandbox-\"."
#   }
# }

# check "sandbox_external_locations_prefixed" {
#   assert {
#     condition     = alltrue([for name in local.sandbox_external_location_names : startswith(name, "sandbox-")])
#     error_message = "Sandbox external location names must start with \"sandbox-\"."
#   }
# }
