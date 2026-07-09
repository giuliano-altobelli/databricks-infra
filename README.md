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

## Terraform workspace configs

The shared regional Terraform root is `infra/aws/dbx/databricks/us-west-1`.
Workspace-specific local backend and variable files live under `workspace/<workspace-name>` inside that root:

- `workspace/sandbox-infra`
- `workspace/prod-infra`

The workspace var file controls the workspace name, Terraform state path, Databricks group display label, platform security catalog name, and whether direct per-user workspace entitlements are managed. Sandbox uses `dev_security`; prod uses `prod_security` and relies on group entitlements during bootstrap.

Always select the workspace explicitly:

```bash
ROOT=infra/aws/dbx/databricks/us-west-1
ENV=prod-infra

DATABRICKS_AUTH_TYPE=oauth-m2m \
TF_DATA_DIR="$PWD/$ROOT/workspace/$ENV/.terraform" \
direnv exec "$ROOT" terraform -chdir="$ROOT" init -reconfigure \
  -backend-config="workspace/$ENV/local.tfbackend"

DATABRICKS_AUTH_TYPE=oauth-m2m \
TF_DATA_DIR="$PWD/$ROOT/workspace/$ENV/.terraform" \
direnv exec "$ROOT" terraform -chdir="$ROOT" plan \
  -var-file="workspace/$ENV/terraform.tfvars"
```
