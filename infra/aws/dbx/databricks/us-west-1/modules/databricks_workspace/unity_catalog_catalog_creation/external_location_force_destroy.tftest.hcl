mock_provider "aws" {}
mock_provider "databricks" {}
mock_provider "null" {}
mock_provider "time" {}

run "catalog_external_location_force_destroy_enabled" {
  command = plan

  variables {
    aws_account_id          = "123456789012"
    cmk_admin_arn           = "arn:aws:iam::123456789012:role/kms-admin"
    resource_prefix         = "test"
    workspace_id            = "1234567890123456"
    catalog_name            = "prod_test_catalog"
    catalog_admin_principal = "Platform Admins"
  }

  assert {
    condition     = databricks_external_location.workspace_catalog_external_location[0].force_destroy == true
    error_message = "Catalog bootstrap external locations must enable force_destroy for teardown after managed storage dependents are gone."
  }
}
