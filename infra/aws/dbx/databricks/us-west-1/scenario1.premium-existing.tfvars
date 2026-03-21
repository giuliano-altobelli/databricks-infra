# Retirement-only historical input for the legacy personal-infra workspace.
# Do not use this file for new workspace creation.
# Active steady-state work uses scenario2.sandbox-create-managed.tfvars.
aws_account_id        = "441735166692"
region                = "us-west-2"
admin_user            = "giulianoaltobelli@gmail.com"
databricks_account_id = "535f803e-200e-4ff7-985a-7673a0f53375"
resource_prefix       = "personal-infra"

pricing_tier          = "PREMIUM"
network_configuration = "managed"
metastore_exists      = true

enable_audit_log_delivery          = false
audit_log_delivery_exists          = false
enable_example_cluster             = false
enable_security_analysis_tool      = false
enable_compliance_security_profile = false
compliance_standards               = ["Standard_A", "Standard_B"]

deployment_name      = null
databricks_gov_shard = null
