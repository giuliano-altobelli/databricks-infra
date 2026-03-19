# =============================================================================
# Databricks Workspace Cluster Policies
# =============================================================================

locals {
  cluster_policies = {
    bundle_dlt_job = {
      name        = "Sandbox Bundle DLT Job Policy"
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
          principal_name   = local.identity_groups.platform_admins.display_name
          permission_level = "CAN_USE"
        }
        # Future principal-user grant placeholder.
        # {
        #   principal_type   = "user"
        #   principal_name   = "<future-principal-user@example.com>"
        #   permission_level = "CAN_USE"
        # }
        # Future service-principal grant placeholder.
        # {
        #   principal_type   = "service_principal"
        #   principal_name   = "<future-service-principal-application-id>"
        #   permission_level = "CAN_USE"
        # }
      ]
    }

    # Future developer-scoped DLT job policy placeholder.
    # bundle_dlt_job_dev = {
    #   name        = "Sandbox Bundle DLT Job Dev Policy"
    #   description = "Future lower-cost DLT job policy for developer bundle deployments."
    #   definition = jsonencode({
    #     cluster_type = {
    #       type   = "fixed"
    #       value  = "dlt"
    #       hidden = true
    #     }
    #     num_workers = {
    #       type         = "range"
    #       defaultValue = 1
    #       maxValue     = 2
    #       isOptional   = true
    #     }
    #     node_type_id = {
    #       type   = "fixed"
    #       value  = "i3.xlarge"
    #       hidden = true
    #     }
    #     spark_version = {
    #       type   = "unlimited"
    #       hidden = true
    #     }
    #   })
    #   permissions = [
    #     {
    #       principal_type   = "group"
    #       principal_name   = "<future-developer-group>"
    #       permission_level = "CAN_USE"
    #     }
    #   ]
    # }
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
