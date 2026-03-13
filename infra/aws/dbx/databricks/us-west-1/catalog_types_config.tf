# =============================================================================
# Databricks Governed Catalog Type Templates
# =============================================================================

locals {
  catalog_types_config = {
    # Catalog type keys, nested schema keys, and nested managed-volume keys
    # become part of the stable Terraform identity for derived governed
    # resources. Rename with care.
    standard_governed = {
      schemas = {
        raw = {
          comment = "Landing zone for raw source-aligned data."
          properties = {
            purpose        = "Landing zone for raw source-aligned data."
            classification = "restricted"
          }
        }
        base    = {}
        staging = {}
        final   = {}
        uat     = {}
      }

      managed_volumes = {}
    }

    # shared_ml_assets = {
    #   schemas = {
    #     raw     = {}
    #     base    = {}
    #     staging = {}
    #     final   = {}
    #     uat     = {}
    #   }
    #
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
