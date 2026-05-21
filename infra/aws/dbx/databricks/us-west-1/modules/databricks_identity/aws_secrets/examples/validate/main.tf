module "under_test" {
  source = "../.."

  providers = {
    aws = aws.us_west_1
  }

  region      = "us-west-1"
  name_prefix = "databricks/service-principals"
  service_principals = {
    uat_promotion = {
      display_name = "UAT Promotion SP"
    }
  }
}
