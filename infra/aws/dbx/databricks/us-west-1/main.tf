# =============================================================================
# Databricks Account Modules
# =============================================================================

# Create Unity Catalog Metastore
module "unity_catalog_metastore_creation" {
  source = "./modules/databricks_account/unity_catalog_metastore_creation"
  providers = {
    databricks = databricks.mws
  }

  region                 = var.region
  metastore_exists       = var.metastore_exists
  metastore_storage_root = var.metastore_storage_root
}

# Create Network Connectivity Connection Object
module "network_connectivity_configuration" {
  count  = local.enable_network_connectivity_configuration ? 1 : 0
  source = "./modules/databricks_account/network_connectivity_configuration"
  providers = {
    databricks = databricks.mws
  }

  region          = var.region
  resource_prefix = var.resource_prefix
}

# Create a Network Policy
module "network_policy" {
  count  = local.enable_network_policy ? 1 : 0
  source = "./modules/databricks_account/network_policy"
  providers = {
    databricks = databricks.mws
  }

  databricks_account_id = var.databricks_account_id
  resource_prefix       = var.resource_prefix
}

# Create Databricks Workspace
module "databricks_mws_workspace" {
  count  = local.create_workspace ? 1 : 0
  source = "./modules/databricks_account/workspace"

  providers = {
    databricks = databricks.mws
  }

  # Basic Configuration
  databricks_account_id = var.databricks_account_id
  resource_prefix       = var.resource_prefix
  region                = var.region
  deployment_name       = var.deployment_name
  pricing_tier          = var.pricing_tier

  # Feature Gating
  enable_customer_managed_network  = local.enable_customer_managed_network
  enable_customer_managed_keys     = local.enable_customer_managed_keys
  enable_private_access_settings   = local.enable_enterprise_infra
  enable_network_policy_attachment = local.enable_network_policy
  enable_ncc_binding               = local.enable_network_connectivity_configuration

  # Network Configuration
  vpc_id = local.enable_customer_managed_network ? (
    var.custom_vpc_id != null ? var.custom_vpc_id : module.vpc[0].vpc_id
  ) : null
  subnet_ids = local.enable_customer_managed_network ? (
    var.custom_private_subnet_ids != null ? var.custom_private_subnet_ids : module.vpc[0].private_subnets
  ) : null
  security_group_ids = local.enable_customer_managed_network ? (
    var.custom_sg_id != null ? [var.custom_sg_id] : [aws_security_group.sg[0].id]
  ) : null
  backend_rest = local.enable_customer_managed_network ? (
    var.custom_workspace_vpce_id != null ? var.custom_workspace_vpce_id : aws_vpc_endpoint.backend_rest[0].id
  ) : null
  backend_relay = local.enable_customer_managed_network ? (
    var.custom_relay_vpce_id != null ? var.custom_relay_vpce_id : aws_vpc_endpoint.backend_relay[0].id
  ) : null

  # Cross-Account Role
  cross_account_role_arn = aws_iam_role.cross_account_role[0].arn

  # Root Storage Bucket
  bucket_name = aws_s3_bucket.root_storage_bucket[0].id

  # KMS Keys
  managed_services_key        = local.enable_customer_managed_keys ? aws_kms_key.managed_services[0].arn : null
  workspace_storage_key       = local.enable_customer_managed_keys ? aws_kms_key.workspace_storage[0].arn : null
  managed_services_key_alias  = local.enable_customer_managed_keys ? aws_kms_alias.managed_services_key_alias[0].name : null
  workspace_storage_key_alias = local.enable_customer_managed_keys ? aws_kms_alias.workspace_storage_key_alias[0].name : null

  # Network Connectivity Configuration and Network Policy
  network_connectivity_configuration_id = local.enable_network_connectivity_configuration ? module.network_connectivity_configuration[0].ncc_id : null
  network_policy_id                     = local.enable_network_policy ? module.network_policy[0].network_policy_id : null

  depends_on = [module.unity_catalog_metastore_creation]
}

# Unity Catalog Assignment
module "unity_catalog_metastore_assignment" {
  source = "./modules/databricks_account/unity_catalog_metastore_assignment"
  providers = {
    databricks = databricks.mws
  }

  metastore_id = module.unity_catalog_metastore_creation.metastore_id
  workspace_id = local.workspace_id

  depends_on = [module.unity_catalog_metastore_creation]
}

# User Workspace Assignment (Admin)
module "user_assignment" {
  source = "./modules/databricks_account/user_assignment"
  providers = {
    databricks = databricks.mws
  }

  workspace_id     = local.workspace_id
  workspace_access = var.admin_user

  depends_on = [module.unity_catalog_metastore_assignment]
}

# Audit Log Delivery
module "log_delivery" {
  count  = var.enable_audit_log_delivery && !var.audit_log_delivery_exists ? 1 : 0
  source = "./modules/databricks_account/audit_log_delivery"
  providers = {
    databricks = databricks.mws
  }

  databricks_account_id = var.databricks_account_id
  resource_prefix       = var.resource_prefix
  aws_assume_partition  = local.assume_role_partition
}

# =============================================================================
# Databricks Workspace Modules
# =============================================================================

# Creates a Workspace Isolated Catalog
module "unity_catalog_catalog_creation" {
  count  = local.effective_uc_catalog_mode == "isolated" ? 1 : 0
  source = "./modules/databricks_workspace/unity_catalog_catalog_creation"
  providers = {
    databricks = databricks.created_workspace
  }

  aws_account_id               = var.aws_account_id
  aws_iam_partition            = local.computed_aws_partition
  aws_assume_partition         = local.assume_role_partition
  unity_catalog_iam_arn        = local.unity_catalog_iam_arn
  resource_prefix              = var.resource_prefix
  uc_catalog_name              = "${var.resource_prefix}-catalog-${local.workspace_id}"
  cmk_admin_arn                = var.cmk_admin_arn == null ? "arn:${local.computed_aws_partition}:iam::${var.aws_account_id}:root" : var.cmk_admin_arn
  workspace_id                 = local.workspace_id
  user_workspace_catalog_admin = var.admin_user

  depends_on = [module.unity_catalog_metastore_assignment]
}

# Restrictive Root Bucket Policy
module "restrictive_root_bucket" {
  count  = local.enable_restrictive_root_bucket ? 1 : 0
  source = "./modules/databricks_workspace/restrictive_root_bucket"
  providers = {
    aws = aws
  }

  databricks_account_id = var.databricks_account_id
  aws_partition         = local.computed_aws_partition
  databricks_gov_shard  = var.databricks_gov_shard
  workspace_id          = local.workspace_id
  region_name           = var.databricks_gov_shard == "dod" ? var.region_name_config[var.region].secondary_name : var.region_name_config[var.region].primary_name
  root_s3_bucket        = "${var.resource_prefix}-workspace-root-storage"
}

# Disable legacy settings like Hive Metastore, Disables Databricks Runtime prior to 13.3 LTS, DBFS, DBFS Mounts,etc.
module "disable_legacy_settings" {
  count  = local.enable_disable_legacy_settings ? 1 : 0
  source = "./modules/databricks_workspace/disable_legacy_settings"
  providers = {
    databricks = databricks.created_workspace
  }
}

# Enable Compliance Security Profile (CSP) on the Databricks Workspace.
module "compliance_security_profile" {
  count  = var.enable_compliance_security_profile ? 1 : 0
  source = "./modules/databricks_workspace/compliance_security_profile"

  providers = {
    databricks = databricks.created_workspace
  }

  compliance_standards = var.compliance_standards
}

# Create Cluster
module "cluster_configuration" {
  count  = var.enable_example_cluster ? 1 : 0
  source = "./modules/databricks_workspace/classic_cluster"
  providers = {
    databricks = databricks.created_workspace
  }

  enable_compliance_security_profile = var.enable_compliance_security_profile
  resource_prefix                    = var.resource_prefix
  region                             = var.region

  depends_on = [module.unity_catalog_metastore_assignment]
}

# =============================================================================
# Security Analysis Tool  - PyPI must be enabled in network policy resource to function.
# =============================================================================

module "security_analysis_tool" {
  count  = var.enable_security_analysis_tool && var.region != "us-gov-west-1" ? 1 : 0
  source = "./modules/security_analysis_tool"

  providers = {
    databricks = databricks.created_workspace
  }

  # Authentication Variables
  databricks_account_id = var.databricks_account_id
  client_id             = null # Provide Workspace Admin ID
  client_secret         = null # Provide Workspace Admin Secret

  use_sp_auth = true

  # Databricks Variables
  analysis_schema_name = replace("${local.catalog_name}.SAT", "-", "_")
  workspace_id         = local.workspace_id

  # Configuration Variables
  proxies           = {}
  run_on_serverless = true

  depends_on = [module.unity_catalog_catalog_creation]
}
