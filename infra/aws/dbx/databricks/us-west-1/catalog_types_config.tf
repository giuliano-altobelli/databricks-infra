# =============================================================================
# Databricks Governed Catalog Type Templates
# =============================================================================

locals {
  catalog_types_config = {
    # Catalog type keys and nested managed-volume keys become part of the
    # stable Terraform identity for derived managed volumes. Rename with care.
    standard_governed = {
      managed_volumes = {}
    }

    # shared_ml_assets = {
    #   managed_volumes = {
    #     final = {
    #       model_artifacts = {
    #         name = "model_artifacts"
    #       }
    #     }
    #     uat = {
    #       candidate_assets = {
    #         name = "candidate_assets"
    #       }
    #     }
    #   }
    # }
  }
}
