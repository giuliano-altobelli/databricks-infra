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
    catalog_reader_principals = [
      "Revenue Readers",
    ]
  }

  assert {
    condition     = databricks_external_location.workspace_catalog_external_location[0].force_destroy == true
    error_message = "Catalog bootstrap external locations must enable force_destroy for teardown after managed storage dependents are gone."
  }

  assert {
    condition = alltrue([
      for grant in databricks_grants.workspace_catalog[0].grant :
      contains(grant.privileges, "USE_CATALOG") &&
      contains(grant.privileges, "EXTERNAL USE SCHEMA")
      if grant.principal == "Revenue Readers"
    ])
    error_message = "Catalog reader principals must receive both USE_CATALOG and EXTERNAL USE SCHEMA."
  }
}
