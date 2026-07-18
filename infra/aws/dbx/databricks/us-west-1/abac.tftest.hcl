mock_provider "aws" {}
mock_provider "aws" {
  alias = "us_west_1"
}
mock_provider "databricks" {}
mock_provider "databricks" {
  alias = "mws"
}
mock_provider "databricks" {
  alias = "created_workspace"
}

variables {
  admin_user            = "administrator@example.com"
  aws_account_id        = "111111111111"
  compliance_standards  = []
  databricks_account_id = "11111111-1111-1111-1111-111111111111"
  metastore_exists      = true
  region                = "us-west-2"
  resource_prefix       = "test"

  enable_abac_demo_catalog = true
  security_catalog_name    = "configured_security"
  abac_demo_catalog_name   = "dev_abac_demo"
  abac = {
    name    = "configured_policy"
    comment = "Configured policy."
    table = {
      key   = "boundary"
      value = "general"
    }
    column = {
      key   = "protected"
      value = "groups"
      alias = "groups"
    }
    function = {
      schema = "configured_schema"
      name   = "configured_function"
    }
    principals = {
      include = ["users"]
      exclude = ["administrator@example.com"]
    }
  }
}

run "function" {
  command = plan

  plan_options {
    target = [databricks_grant.abac]
  }

  override_data {
    target = data.databricks_current_user.deployment
    values = {
      user_name = "deployment"
    }
  }

  override_data {
    target = data.databricks_aws_assume_role_policy.this
    values = {
      json = "{}"
    }
  }

  override_data {
    target = data.databricks_aws_crossaccount_policy.this
    values = {
      json = "{}"
    }
  }

  override_module {
    target = module.databricks_mws_workspace
    outputs = {
      workspace_id  = "1111111111111111"
      workspace_url = "https://example.cloud.databricks.com"
    }
  }

  assert {
    condition     = databricks_grant.abac[0].function == "configured_security.configured_schema.configured_function"
    error_message = "The ABAC function grant must use the configured function name."
  }

  assert {
    condition     = one(values(local.abac)).function == databricks_grant.abac[0].function
    error_message = "The ABAC policy and function grant must use the same configured function name."
  }
}
