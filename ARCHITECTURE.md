# Architecture

## Unity Catalog (single workspace, Option 1)

This repository currently targets a **single Databricks workspace**. Unity Catalog naming and access control follow an “Option 1” domain model that remains compatible with a future **multi-workspace** posture (multiple workspaces sharing one metastore).

### Namespaces

- **Governed domain catalogs:** `prod_<source>_<business_area>`
  - Schemas: `raw`, `base`, `staging`, `final`, plus `uat`
- **Personal development catalog:** `personal`
  - Schemas: `personal.<user_key>` for each user key in Terraform `local.identity_users` (pre-provisioned)

Examples:

- Prod object: `prod_salesforce_revenue.final.customer_dim`
- Shareable UAT object: `prod_salesforce_revenue.uat.customer_dim_candidate`
- Personal build artifact: `personal.jane_doe.customer_dim_candidate`

### Access model (intent)

- Humans write only in `personal.<user_key>`.
- The **UAT promotion** service principal has read/write access to all `prod_<source>_<business_area>.uat` schemas, but **no access** to `prod_<source>_<business_area>.(raw|base|staging|final)`.
- The **release** service principal has full access to all `prod_<source>_<business_area>.(raw|base|staging|final)` schemas.
- Domain readers can read both:
  - `prod_<source>_<business_area>.(raw|base|staging|final)`
  - `prod_<source>_<business_area>.uat`
- The workspace default namespace remains unchanged for now; future recommendation is to set it to `personal` to reduce accidental writes into governed catalogs.

Detailed design: `docs/design-docs/unity-catalog.md`

## Developer experience flow

```mermaid
flowchart LR
  Dev[Developer] -->|Build / iterate| Personal[personal.<user_key>]
  Dev -->|Open PR| PR[Pull Request]
  PR -->|CI: promote to UAT| UatBot[UAT promotion SP]
  UatBot -->|Promote artifacts| UAT[prod_<source>_<business_area>.uat]
  Readers[Domain readers] -->|Validate / consume| UAT
  PR -->|Approved + "databricks deploy"| ReleaseBot[Release SP]
  ReleaseBot -->|Publish| Prod[prod_<source>_<business_area>.(raw|base|staging|final)]
```

Notes:

- On PR submission, CI automatically promotes shareable artifacts into `prod_<source>_<business_area>.uat` using the **UAT promotion** service principal.
- After approval, a `"databricks deploy"` comment triggers publish into the governed production layer schemas using the **release** service principal.
- In the single-workspace phase, strict Unity Catalog grants and workspace compute controls are required to prevent accidental writes into governed production layer schemas.

## Future: multi-workspace (shared metastore)

Assumption: all workspaces share **one** Unity Catalog metastore.

- Use workspace-scoped `workspace_id` / `workspace_ids` parameters where appropriate (e.g., metastore assignments and workspace bindings).
- Use workspace bindings so additional workspaces can “see” the same governed `prod_*` catalogs.
- Keep the namespace model and UC grants consistent across workspaces.
