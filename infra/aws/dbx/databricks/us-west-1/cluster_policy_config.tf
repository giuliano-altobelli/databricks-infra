# =============================================================================
# Databricks Workspace Cluster Policies
# =============================================================================

locals {
  cluster_policies = {
    bundle_dlt_job = {
      name        = "Bundle DLT Job Policy"
      description = "Used by Databricks Asset Bundles for DLT job clusters."
      definition = jsonencode({
        cluster_type = {
          type   = "fixed"
          value  = "dlt"
          hidden = true
        }
        num_workers = {
          type         = "unlimited"
          defaultValue = 3
          isOptional   = true
        }
        node_type_id = {
          type       = "unlimited"
          isOptional = true
        }
        spark_version = {
          type   = "unlimited"
          hidden = true
        }
      })
      permissions = [
        {
          principal_type   = "group"
          principal_name   = "Platform Admins"
          permission_level = "CAN_USE"
        }
      ]
    }
  }
}

module "cluster_policy" {
  source = "./modules/databricks_workspace/cluster_policy"

  providers = {
    databricks = databricks.created_workspace
  }

  cluster_policies = local.cluster_policies

  depends_on = [module.users_groups]
}
