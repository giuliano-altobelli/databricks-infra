# Unity Catalog Design (Single Workspace, Option 1)

Date: 2026-03-05

## Objective

Standardize Unity Catalog naming, data boundaries, and access controls for a **single Databricks workspace** while preserving the Option 1 namespace convention:

- Governed (shared) domains: `prod_<source>_<business_area>.<schema>.<object>` when `business_area` is present, otherwise `prod_<source>.<schema>.<object>`
- Personal development: `personal.<user_schema>.<object>`

## Context

We are operating in **one Databricks workspace** today, but we want the namespace layout to remain compatible with a future **multi-workspace** posture (multiple workspaces, one shared Unity Catalog metastore).

In this phase:

- The `prod_` prefix is treated as a **governed namespace** (not necessarily an environment indicator for the workspace runtime).
- Developers build in **private personal schemas**.
- Shareable artifacts land in a per-domain **`uat`** schema (written by CI, not humans).

## Requirements

- **Single workspace** today; **one shared UC metastore** now and in the future.
- Keep Option 1 naming shape; use a single governed prefix (`prod_`) for all shared domain catalogs.
- Add a **`personal`** catalog with **one schema per user**, accessible only to that user by default.
- Add a per-domain **`uat`** schema for shareable, pre-prod artifacts.
- Do **not** focus on CI/CD mechanics in this document; capture only the namespace and grant intent.
- Cover **account-level**, **workspace-level**, and **Unity Catalog** concerns where appropriate.

## Non-goals

- Implementing PR comment automation (e.g. `databricks deploy`) and artifact promotion workflows.
- Defining a full SDLC across dev/qa/prod workspaces (future).

## Namespace Model

### Governed domain catalogs

Catalog naming:

- `prod_<source>_<business_area>` when `business_area` is present
- `prod_<source>` when `business_area` is empty

Schemas in each domain catalog:

- Production layers: `raw`, `base`, `staging`, `final`
- Shareable pre-prod: `uat`

Examples:

- Prod object: `prod_salesforce_revenue.final.customer_dim`
- Prod object without business area: `prod_hubspot.final.company_dim`
- Shareable UAT object: `prod_salesforce_revenue.uat.customer_dim_candidate`

Conventions:

- `<source>` is the upstream system/vendor (10s, <100).
- `<business_area>` is the organizational data domain when present.
- If `business_area` is empty, do not use a sentinel. The catalog name collapses to `prod_<source>`.
- If an object spans multiple business areas, it is acceptable to **duplicate** it across domains (no canonical shared location required initially).

### Personal catalog

Catalog naming:

- `personal`

Schema naming:

- One schema per user: `personal.<user_key>`
- `<user_key>` comes from the stable keys in Terraform `local.identity_users` (example: key `jane_doe` → `personal.jane_doe`)

Examples:

- Personal build artifact: `personal.jane_doe.customer_dim_candidate`

## Identity + Access Control Model

### Account-level (MWS)

Manage users, groups, and service principals at the Databricks account level and assign them to the workspace.

Notes:

- Account principals (groups/SPs) are the canonical identities referenced by Unity Catalog grants.
- This repo already has an identity entrypoint at `infra/aws/dbx/databricks/us-west-1/identify.tf`.

### Workspace-level

Workspace entitlements and compute policies should reinforce Unity Catalog boundaries:

- Interactive compute should not be able to write into governed `prod_*` production layer schemas.
- Only dedicated CI service principals and controlled pipelines should write into governed schemas.

This document does not prescribe the exact cluster policies; it defines the UC boundaries they must support.

### Unity Catalog (authoritative data access)

Principles:

- Unity Catalog grants are the primary enforcement mechanism for data access.
- Humans write in `personal.<user_key>`.
- A dedicated **UAT promotion** service principal is the only writer to `prod_*.<domain>.uat`.
- A dedicated **release** service principal publishes into `prod_*.<domain>.(raw|base|staging|final)`.
- Production layer schemas (`raw/base/staging/final`) are written only by controlled release pipelines/admins (not ad-hoc humans).

#### Domain readers

For each governed domain catalog (`prod_<source>_<business_area>` when `business_area` is present, otherwise `prod_<source>`):

- Readers can read from `raw/base/staging/final` and from `uat`.
- Typical privileges:
  - Catalog: `USE_CATALOG`
  - Schema: `USE_SCHEMA`
  - Data: `SELECT` (and optionally `READ_METADATA`)

#### UAT promotion service principal

One service principal used by CI for PR-driven promotion into domain `uat` schemas.

- Has read/write access to all governed domain `uat` schemas.
- Has **no access** (read or write) to governed domain `raw`, `base`, `staging`, or `final` schemas.
- Typical privileges (on each `uat` schema):
  - `USE_CATALOG`, `USE_SCHEMA`
  - Table/view write privileges as needed by the artifact type (e.g. `CREATE_TABLE`, `MODIFY`, or `ALL_PRIVILEGES` scoped to the `uat` schema)

#### Release service principal

One service principal used by CI for publishing into governed production layer schemas.

- Has full access to all governed domain `raw`, `base`, `staging`, and `final` schemas.
- Publishing is executed via controlled pipelines (not ad-hoc human interactive compute).

#### Personal schemas

For each user `u`:

- Terraform creates `personal.u`.
- `u` is the owner (or is granted `ALL_PRIVILEGES`) on `personal.u`.
- No other principals receive access by default (admins retain break-glass access as needed).

#### Workspace default namespace

- Keep the current workspace default catalog unchanged for now.
- Future recommendation: set the workspace default namespace to `personal` to reduce accidental writes into governed catalogs.

## Terraform Integration (Planned)

Use two provider scopes (already present in this repo):

- `databricks.mws`: account-level identity and workspace assignment
- `databricks.created_workspace`: workspace-level Unity Catalog resources (catalogs/schemas/grants)

Planned declarative inputs:

- Domain catalog matrix: `(source, business_area)` list, where `business_area` may be empty and renders `prod_<source>`
- Domain read principals per domain
- UAT promotion service principal identifier (for `uat` write grants)
- Release service principal identifier (for production layer write grants)
- Personal schema user keys: derived from `keys(local.identity_users)`

Planned resources:

- `databricks_catalog`: create `prod_*` catalogs and the `personal` catalog
- `databricks_schema`: create `raw/base/staging/final/uat` per domain catalog and `personal.<user_key>` per user
- `databricks_grant`: apply read/write privileges as described above

## Future: Multi-workspace (shared metastore)

Assumption: all workspaces share **one** Unity Catalog metastore.

As additional workspaces are introduced:

- Add a `workspace_id` / `workspace_ids` parameter where resources are workspace-scoped (e.g., metastore assignments, workspace bindings).
- Use **workspace bindings** so a workspace can “see” specific domain catalogs.
- Keep UC grants unchanged: principals are account-level; grants apply across any workspace that has visibility to the catalogs/schemas.
