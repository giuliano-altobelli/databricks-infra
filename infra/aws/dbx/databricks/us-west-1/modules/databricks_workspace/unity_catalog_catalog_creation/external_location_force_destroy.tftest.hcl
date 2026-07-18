mock_provider "aws" {}
mock_provider "databricks" {}
mock_provider "null" {}
mock_provider "time" {}

override_resource {
  target          = aws_kms_key.catalog_storage
  override_during = plan
  values = {
    arn = "arn:aws:kms:us-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  }
}

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
    additional_catalog_grants = [{
      principal  = "00000000-0000-0000-0000-000000000001"
      privileges = ["CREATE_SCHEMA", "USE_CATALOG"]
    }]
  }

  assert {
    condition     = databricks_external_location.workspace_catalog_external_location[0].force_destroy == true
    error_message = "Catalog bootstrap external locations must enable force_destroy for teardown after managed storage dependents are gone."
  }

  assert {
    condition     = try(time_sleep.wait_60_seconds[0].triggers.iam_role_name, null) == "test-prod-test-catalog-1234567890123456"
    error_message = "The IAM propagation wait must rerun when the derived catalog IAM role name changes."
  }

  assert {
    condition = (
      try(databricks_external_location.workspace_catalog_external_location[0].encryption_details[0].sse_encryption_details[0].algorithm, null) == "AWS_SSE_KMS" &&
      try(databricks_external_location.workspace_catalog_external_location[0].encryption_details[0].sse_encryption_details[0].aws_kms_key_arn, null) == aws_kms_key.catalog_storage[0].arn
    )
    error_message = "Catalog bootstrap external locations must use AWS_SSE_KMS with the catalog storage key ARN."
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


  assert {
    condition = length([
      for grant in databricks_grants.workspace_catalog[0].grant : grant
      if grant.principal == "00000000-0000-0000-0000-000000000001"
      ]) == 1 && toset([
      for grant in databricks_grants.workspace_catalog[0].grant : grant.privileges
      if grant.principal == "00000000-0000-0000-0000-000000000001"
    ][0]) == toset(["CREATE_SCHEMA", "USE_CATALOG"])
    error_message = "Additional catalog grants must preserve their exact principal privilege list."
  }
}
