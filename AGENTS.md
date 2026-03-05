# Repository Agent Rules

- For any Databricks identity or access-control change, always ask scope before implementation:
  - Unity Catalog
  - Account-level
  - Workspace-level
  - Or any combination of the above
- Treat this scope question as required even if a request seems obvious.

## Terraform: Databricks Provider Configs

- The repo uses multiple **Databricks provider configurations** (same `databricks/databricks` provider plugin) that differ mainly by `host`/API endpoint:
  - `databricks.mws`: **account-level** (MWS) endpoint; used for account-scoped resources like account users/groups and `databricks_mws_*` resources.
  - `databricks.created_workspace`: **workspace-level** endpoint (a specific workspace URL); used for workspace-scoped resources like UC grants and `databricks_entitlements`.
- Provider configs in `provider.tf` apply to the **root module** only. Child modules do **not** automatically inherit *aliased* providers, so modules must be wired via `module ... { providers = { ... } }` when an alias/workspace provider is required.

## Terraform Command Execution

- Always run `terraform` commands outside the sandbox.
- Do not request permission before running `terraform` commands.

## Terraform Scenario Vars

- Use the scenario var files in `infra/aws/dbx/databricks/us-west-1`:
  - `scenario1.premium-existing.tfvars`: Premium + existing workspace + managed networking (default/recommended).
  - `scenario2.premium-create-managed.tfvars`: Premium + create workspace + managed networking.
  - `scenario3.enterprise-create-isolated.tfvars`: Enterprise + create workspace + isolated networking (full SRA path).
- Use this command pattern for all plan/apply runs:
  - `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 <plan|apply> -var-file=<scenario-file>`
- If the request is to avoid enterprise/SRA deployment, use scenario 1 or 2 only and do not apply scenario 3 plans.
