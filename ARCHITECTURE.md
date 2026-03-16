# Architecture

## Unity Catalog (single workspace, Option 1)

This repository currently targets a **single Databricks workspace**. Unity Catalog naming and access control follow an “Option 1” domain model that remains compatible with a future **multi-workspace** posture (multiple workspaces sharing one metastore).

### Namespaces

- **Governed domain catalogs:**
  - `prod_<source>_<business_area>` when `business_area` is present
  - `prod_<source>` when `business_area` is empty
  - Standard schemas: `raw`, `base`, `staging`, `final`, plus `uat`
  - Exception: the default catalog `main` may be managed on the governed path with no schemas
- **Personal development catalog:** `personal`
  - Schemas: `personal.<user_key>` for each user present in the workspace-level `okta-databricks-users` group
  - `<user_key>` is derived from the user's normalized email local part (example: `jane.doe@company.com` -> `jane_doe`)

Examples:

- Prod object: `prod_salesforce_revenue.final.customer_dim`
- Prod object without business area: `prod_hubspot.final.company_dim`
- Shareable UAT object: `prod_salesforce_revenue.uat.customer_dim_candidate`
- Default schema-less governed catalog: `main`
- Personal build artifact: `personal.jane_doe.customer_dim_candidate`

### Access model (intent)

- Humans write only in `personal.<user_key>`.
- The **UAT promotion** service principal has read/write access to all governed domain `uat` schemas, but **no access** to governed `raw`, `base`, `staging`, or `final` schemas.
- The **release** service principal has full access to all governed `raw`, `base`, `staging`, and `final` schemas.
- Domain readers can read both:
  - governed `prod_*` production-layer schemas
  - governed `prod_*` `uat` schemas
- The governed-path `main` catalog is catalog-level only in this pattern; it intentionally has no schemas.
- The workspace default namespace remains unchanged for now; future recommendation is to set it to `personal` to reduce accidental writes into governed catalogs.

Detailed design: `docs/design-docs/unity-catalog.md`

## Identity provisioning

User lifecycle is assumed to be managed outside Terraform through Okta SCIM.

```mermaid
flowchart LR
  Okta[Okta group approval] --> Scim[SCIM provisions user in Databricks]
  Scim --> AccountGroup[Add user to okta-databricks-users at account level]
  AccountGroup --> WorkspaceGroup[Add user to okta-databricks-users at workspace level]
  WorkspaceGroup --> OptionalGroup[identify.tf adds optional Databricks groups and assignments]
```

- Approval through the relevant Okta access path provisions the user into Databricks.
- Approved users are automatically added to `okta-databricks-users` at both the Databricks account and workspace levels.
- `infra/aws/dbx/databricks/us-west-1/identify.tf` does not create users. It assigns already provisioned users to additional Terraform-managed Databricks groups when requested.
- Those additional Databricks groups, along with the already provisioned users referenced in `identify.tf`, can carry account roles, workspace permission assignments, and workspace entitlements managed through Terraform.
- The `personal` catalog is expected to create one schema per user based on live membership in the workspace-level `okta-databricks-users` group.
- Automatic membership in `okta-databricks-users` does not, by itself, change Unity Catalog privileges. Unity Catalog access continues to be managed separately through Terraform group definitions and grants.

## Developer experience flow

```mermaid
flowchart LR
  Dev[Developer] -->|Build / iterate| Personal[personal user schema]
  Dev -->|Open PR| PR[Pull Request]
  PR -->|CI: promote to UAT| UatBot[UAT promotion SP]
  UatBot -->|Promote artifacts| UAT[prod domain UAT schema]
  Readers[Domain readers] -->|Validate / consume| UAT
  PR -->|Approved + databricks deploy comment| ReleaseBot[Release SP]
  ReleaseBot -->|Publish| Prod[prod domain raw, base, staging, and final schemas]
```

Notes:

- Before the workflow below starts, the developer must already be provisioned through Okta SCIM and present in `okta-databricks-users` at the account and workspace levels.
- On PR submission, CI automatically promotes shareable artifacts into the target governed domain `uat` schema using the **UAT promotion** service principal (`prod_<source>_<business_area>.uat` when `business_area` is present, otherwise `prod_<source>.uat`).
- After approval, a `"databricks deploy"` comment triggers publish into the governed production layer schemas using the **release** service principal.
- In the single-workspace phase, strict Unity Catalog grants and workspace compute controls are required to prevent accidental writes into governed production layer schemas.

## Future: multi-workspace (shared metastore)

Assumption: all workspaces share **one** Unity Catalog metastore.

- Use workspace-scoped `workspace_id` / `workspace_ids` parameters where appropriate (e.g., metastore assignments and workspace bindings).
- Use workspace bindings so additional workspaces can “see” the same governed `prod_*` catalogs.
- Keep the namespace model and UC grants consistent across workspaces.
