# =============================================================================
# Databricks Workspace Bedrock External Model Endpoints
# =============================================================================

module "bedrock_external_model_endpoints" {
  source = "./modules/databricks_workspace/bedrock_external_model_endpoints"

  providers = {
    databricks = databricks.created_workspace
  }

  enabled                          = var.bedrock_external_model_endpoints_enabled
  bedrock_external_model_endpoints = var.bedrock_external_model_endpoints

  depends_on = [module.databricks_mws_workspace]
}
