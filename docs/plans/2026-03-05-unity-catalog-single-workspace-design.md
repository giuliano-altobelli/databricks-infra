# Unity Catalog Single-Workspace Design (Option 1)

Date: 2026-03-05

This document records the accepted Unity Catalog namespace and access-control decisions for the current **single-workspace** phase.

Canonical architecture summary: `ARCHITECTURE.md`

Canonical design doc: `docs/design-docs/unity-catalog.md`

## Decisions

- **Governed domain catalogs:** `prod_<source>_<business_area>`
  - Schemas: `raw`, `base`, `staging`, `final`, plus `uat`
- **Personal development catalog:** `personal`
  - Schemas: `personal.<user_key>` for each user key in Terraform `local.identity_users` (pre-provisioned)
- **Promotion targets (future implementation):**
  - On PR submission, CI promotes shareable artifacts into `prod_<source>_<business_area>.uat`
  - On approval + `"databricks deploy"`, CI publishes into `prod_<source>_<business_area>.(raw|base|staging|final)`
- **Service principals (future implementation):**
  - UAT promotion SP: read/write to all `prod_*.<domain>.uat`, no access to `prod_*.<domain>.(raw|base|staging|final)`
  - Release SP: full access to all `prod_*.<domain>.(raw|base|staging|final)`
- **Reader model:** `uat` is readable by the same “domain readers” principals as prod layers
- **Workspace default namespace:** keep current default for now; recommend switching to `personal` later
- **Future multi-workspace:** assume all workspaces share a single UC metastore; use workspace-scoped `workspace_id(s)` for metastore assignments and workspace bindings
