# databricks-infra

## Getting started

1. Request Databricks access through Okta.
2. An admin approves the request.
3. The approved Okta group provisions the user into Databricks and adds the user to `okta-databricks-users` at the Databricks account and workspace levels. The approved Okta group maps to the target workspace.
4. After baseline access is in place, the user opens a pull request to be added to the appropriate Databricks group in `infra/aws/dbx/databricks/us-west-1/identify.tf`.

## Access model

- Databricks groups are the unit used for access assignment in Terraform.
- Unity Catalog allows groups to be assigned permissions to catalogs, schemas, and objects.

## Current scope

This is the current onboarding and access process. We stop here for now and iterate as requirements become clearer.
