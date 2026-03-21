# # =============================================================================
# # Databricks Governed Catalog Type Templates
# # =============================================================================

# locals {
#   catalog_types_config = {
#     # Catalog type keys, nested schema keys, and nested managed-volume keys
#     # become part of the stable Terraform identity for derived governed
#     # resources. Rename with care. A catalog type may intentionally declare
#     # schemas = {} to model a schema-less governed catalog such as the default
#     # "main" catalog. Schema-less catalog types must also keep
#     # managed_volumes = {} because managed volumes must belong to declared
#     # schemas.
#     standard_governed = {
#       schemas = {
#         raw = {
#           comment = "Landing zone for raw source-aligned data."
#           properties = {
#             purpose        = "Landing zone for raw source-aligned data."
#             classification = "restricted"
#           }
#         }
#         base    = {}
#         staging = {}
#         final   = {}
#         uat     = {}
#       }

#       managed_volumes = {}
#     }

#     # shared_ml_assets = {
#     #   schemas = {
#     #     raw     = {}
#     #     base    = {}
#     #     staging = {}
#     #     final   = {}
#     #     uat     = {}
#     #   }
#     #
#     #   managed_volumes = {
#     #     final = {
#     #       model_artifacts = {
#     #         name = "model_artifacts"
#     #       }
#     #     }
#     #     uat = {
#     #       candidate_assets = {
#     #         name = "candidate_assets"
#     #       }
#     #     }
#     #   }
#     # }
#     #
#     # main_empty = {
#     #   schemas         = {}
#     #   managed_volumes = {}
#     # }
#   }
# }
