# Databricks Infra Plan (UC-first, per-dev schema, CI/CD-enforced structure)

## Summary
Design a 3-workspace (dev/qa/prod) Databricks setup using a single Unity Catalog metastore where:
- **Prod is the source of truth for upstream reads** in dev via **secured (masked/filtered) views**.
- **Each developer can write only to their own single dev schema** (option 3), on shared team compute.
- **QA/Prod enforce the 4-layer structure** (raw/base/staging/final).
- **CI/CD is the only path to QA/Prod writes**, using a service principal and SQLMesh plan-based policy gates.

---

## Scope (confirmed)
- **Unity Catalog + Workspace-level controls**
  - UC = object-level data access (views/tables/schemas).
  - Workspace = compute access/policies (who can use which warehouse/cluster).

---

## Namespace & Object Model

### Workspaces
- 3 workspaces: `dev`, `qa`, `prod`.

### Unity Catalog layout
- Catalogs per business domain / data source:
  - e.g. `peopleops`, `netsuite`, `rippling`, `finops`, ...
- One dedicated writable catalog for dev outputs:
  - `sandbox`

### QA/Prod: enforce 4 layers as schemas (per domain/source catalog)
For each domain/source catalog (e.g., `peopleops`):
- Prod physical schemas: `prod_raw`, `prod_base`, `prod_staging`, `prod_final`
- QA physical schemas: `qa_raw`, `qa_base`, `qa_staging`, `qa_final`

### Dev: single schema per developer (option 3)
- In `sandbox`: schema per developer: `dev_<user_slug>`
- Rule: developers can create **any objects** (tables/views/functions) **only** inside their own `sandbox.dev_<user_slug>` schema.

### Secured upstream surface for prod-in-dev reads
- Requirement: **dev reads prod only through secured views** (no direct prod table access).
- Create a dedicated secure catalog per domain/source containing **views only**, e.g.:
  - physical: `peopleops`
  - secure: `peopleops_secure`
- In each `<domain>_secure` catalog, create schemas mirroring the prod layers, e.g.:
  - `prod_raw`, `prod_base`, `prod_staging`, `prod_final`
- If different users need different secured objects, split by entitlement tier, e.g.:
  - `prod_final_standard`, `prod_final_sensitive`
- Populate these schemas with views that apply:
  - column masking (PII)
  - row filters (if needed)
  - any denormalized “developer-friendly” shaping if useful

---

## Identity, Groups, and Permissions

### Group model (team + role)
Per domain/product team `domain_product`, create role-scoped groups per environment:
- Dev:
  - `team_<domain_product>_ae_dev`
  - `team_<domain_product>_de_dev`
- QA/Prod (at minimum read groups; write controlled by CI/CD SPN):
  - `team_<domain_product>_ae_qa_ro`, `team_<domain_product>_de_qa_ro`
  - `team_<domain_product>_ae_prod_ro`, `team_<domain_product>_de_prod_ro`

### Data entitlement groups (fine-grained secure view access)
Use separate entitlement groups to manage access to `<domain>_secure` catalogs/schemas, independent of compute/team groups. Example:
- `ent_<domain>_standard_ro`
- `ent_<domain>_sensitive_ro`

### Dev write permissions (confirmed)
- **AE**: can write only in `sandbox.dev_<their_user_slug>` (any objects).
- **DE**: also can write only in `sandbox.dev_<their_user_slug>` (any objects).
- Both roles:
  - `USAGE` on catalog `sandbox`
  - `USAGE` on their own schema `sandbox.dev_<user_slug>`
  - `CREATE`, `MODIFY`, etc. only on their own schema

### Prod read permissions in dev (confirmed intent)
- Grant dev groups read access to the **secured view** surface only (per domain/source):
  - `USAGE` on `<domain>_secure` catalog(s) they need (e.g. `peopleops_secure`, `netsuite_secure`, ...)
  - `USAGE` on the schemas they are entitled to (e.g., `prod_raw/prod_base/prod_staging/prod_final`, or tiered variants like `prod_final_standard` / `prod_final_sensitive`)
  - `SELECT` on views in those schemas
- Explicitly do **not** grant `SELECT` on base tables in the physical prod schemas (`prod_raw/prod_base/prod_staging/prod_final`).
  - Prefer: do not grant `USAGE` on the physical `<domain>` catalog(s) to dev users at all.

### “Private-only” policy stance (confirmed)
- Acknowledge: since devs can create any objects in their schema, **true non-shareability can’t be perfectly enforced** (owners can often grant).
- Enforcement approach:
  - policy + review + audit + alerts (see “Auditing”)
  - no technical guarantee of secrecy within dev beyond least-privilege defaults

---

## Compute Model (Workspaces)

### Team-based dev SQL warehouses (shared by AE+DE)
- For each domain/product `domain_product`, provision one dev SQL warehouse: `wh_team_<domain_product>_dev`
- Grant `CAN_USE` on `wh_team_<domain_product>_dev` to both:
  - `team_<domain_product>_ae_dev`
  - `team_<domain_product>_de_dev`
- Rationale: UC enforces per-user/group data access even on shared compute; separate warehouses reduce operational blast radius (performance/cost/availability) between teams.

### Non-SQL compute (clusters/jobs)
- Assign cluster/job compute access via the same team role groups (or additional compute-only groups if preferred), without changing UC permissions.
- Ensure warehouse/cluster identities do not collapse to a single over-privileged run-as identity that would bypass UC per-user enforcement.

---

## SQLMesh Workflow (core question: upstream reflects prod)

### Environment mapping (confirmed)
- One SQLMesh environment per developer: `dev_<user>`
- Materialization target for dev:
  - all SQLMesh-managed outputs go to `sandbox.dev_<user_slug>`
- Upstream resolution:
  - all prod upstream references point to the secured view surface:
    - `<domain>_secure.prod_*.<object>`
- Outcome: when prod data changes, dev upstream reads immediately reflect prod (subject to view semantics), while dev writes remain isolated.

### CI/CD promotion model (enforced structure)
- Only CI/CD service principal can apply to QA/Prod physical schemas in domain catalogs (`qa_*` and `prod_*`).
- Developers never get write privileges to QA/Prod schemas.

---

## CI/CD Policy Gates (SQLMesh-aware)

### Inputs
- PR/merge pipeline runs `sqlmesh plan` (and any static checks) for relevant envs.

### Required checks before allowing merge/promotion
1. **Target safety**
   - Fail if any model targets schemas outside:
     - dev: `sandbox.dev_<user_slug>` for dev PR checks
     - qa: `<domain>.qa_raw/qa_base/qa_staging/qa_final`
     - prod: `<domain>.prod_raw/prod_base/prod_staging/prod_final`
2. **Upstream safety**
   - Fail if models reference prod physical tables directly (`<domain>.prod_raw/prod_base/prod_staging/prod_final`) instead of `<domain>_secure.prod_*` views.
3. **Metadata requirements**
   - Require model metadata: owner/team/domain + data classification tags (at least for anything that would reach QA/Prod).
4. **Breaking change controls**
   - Detect drop/rename/backfill-impacting diffs; require explicit approval signal (label/flag) before apply.
5. **No cross-env writes**
   - Prevent accidental writes into physical prod schemas (`<domain>.prod_*`) from dev/qa pipelines/jobs by checking configuration and the plan diff.

### Apply steps (after approval)
- CI/CD uses a service principal to:
  - `sqlmesh apply` to `qa` on merge to main (or release branch)
  - `sqlmesh apply` to `prod` on release approval

---

## Auditing & Guardrails
- Audit logs/alerts for:
  - direct grants issued by users from `sandbox.dev_<user_slug>` objects to broader principals (policy enforcement)
  - attempted direct reads from physical prod schemas (`<domain>.prod_*`) (should fail; alert on repeated attempts)
  - dev warehouse cost spikes / long-running queries (operational blast radius)

---

## Future Consideration — Asset-Based Access Control (ABAC) via Entitlement Table
If entitlement tiers/groups become too granular to manage, consider shifting fine-grained access from “many groups/schemas” to an **entitlement table** that drives security at query time:
- Keep `<domain>_secure` catalogs as the coarse-grained boundary (devs never get `USAGE` on physical `<domain>` catalogs).
- Store entitlements in a governed table (e.g., `security.entitlements`) mapping principals (user and/or group) to assets (views/tables) and, if needed, row/column policies.
- Enforce via:
  - secured views that consult the entitlement table (and optionally `current_user()` / group membership), and/or
  - UC row filters + column masks that consult the entitlement table.
- Automate entitlement updates from a source of truth (IAM/HR/ticketing) and audit all changes.
- Prefer stable principal identifiers (avoid coupling entitlements to mutable usernames/emails).

---

## Test Cases / Acceptance Scenarios
1. **Dev isolation**
   - User A can create/read/write objects in `sandbox.dev_userA`; cannot write to `sandbox.dev_userB`.
2. **Prod-in-dev upstream**
   - User A can `SELECT` from `<domain>_secure.prod_final.*`; cannot `SELECT` from `<domain>.prod_final.*` tables.
3. **Shared compute, per-user permissions**
   - Two users on same team warehouse: each sees only what UC allows; no privilege escalation via warehouse.
4. **CI/CD enforcement**
   - PR fails if a SQLMesh model targets QA/Prod physical schemas (`<domain>.qa_*` / `<domain>.prod_*`) directly from dev.
   - PR fails if upstream references `<domain>.prod_final.table` instead of `<domain>_secure.prod_final.view`.
5. **QA/Prod layering**
   - Objects end up only in `<domain>.qa_raw/qa_base/qa_staging/qa_final` and `<domain>.prod_raw/prod_base/prod_staging/prod_final` after apply.

---

## Feedback Checkpoints (to keep this collaborative)
- Confirm naming conventions you prefer for:
  - catalogs/schemas (`<domain>_secure.prod_final` vs other)
  - per-dev schemas (`sandbox.dev_<user_slug>` formatting constraints)
- Confirm which secured layer(s) must exist first (start with `<domain>_secure.prod_final` only vs all prod layers).
- Confirm whether batch ingestion outputs (autoloader) are treated as `raw/base` and owned/deployed only via CI/CD SPN in QA/Prod.

---

## Assumptions (explicit)
- One UC metastore shared across dev/qa/prod workspaces.
- Developers accept “private-only” as a policy/audit construct, not a hard technical guarantee.
- Team-based shared dev SQL warehouse is acceptable; operational guardrails handle cost/perf contention.

---

## Appendix A — Naming Conventions (Decision Defaults)

### Catalogs
- Domain/data source catalogs:
  - e.g. `peopleops`, `netsuite`, `rippling`, `finops`, ...
- Domain/data source secure catalogs:
  - e.g. `peopleops_secure`, `netsuite_secure`, `rippling_secure`, `finops_secure`, ...
- Dev writable catalog:
  - `sandbox`

### QA/Prod layer schemas (per domain/data source catalog)
- Prod physical schemas: `prod_raw`, `prod_base`, `prod_staging`, `prod_final`
- QA physical schemas: `qa_raw`, `qa_base`, `qa_staging`, `qa_final`

### Secured prod read surface (dev must use these)
- Secured view schemas (per `<domain>_secure` catalog):
  - `prod_raw`, `prod_base`, `prod_staging`, `prod_final`
- Optional entitlement tiers:
  - `prod_final_standard`, `prod_final_sensitive` (pattern applies to other layers if needed)
- Convention: secured objects are **views only**; no base tables in `<domain>_secure` catalogs.

### Per-developer dev schema
- Dev writable schema: `sandbox.dev_<user_slug>`

`<user_slug>` normalization (default):
- Start from SCIM username (or Databricks username/email)
- Lowercase
- Replace any non `[a-z0-9]` with `_`
- Collapse multiple `_`
- Trim leading/trailing `_`

Examples:
- `Jane.Doe@databricks.com` → `sandbox.dev_jane_doe_databricks_com`
- `john_smith` → `sandbox.dev_john_smith`

Note: `user_slug` may change if a user’s SCIM username/email changes.

### Group taxonomy (team + role + env)
Dev (compute + dev schema access):
- `team_<domain_product>_ae_dev`
- `team_<domain_product>_de_dev`

Data entitlement groups (secure view access):
- `ent_<domain>_standard_ro`
- `ent_<domain>_sensitive_ro`

QA/Prod read-only (secured views and/or curated reads):
- `team_<domain_product>_ae_qa_ro`, `team_<domain_product>_de_qa_ro`
- `team_<domain_product>_ae_prod_ro`, `team_<domain_product>_de_prod_ro`

CI/CD service principal (write-only via automation):
- Principal: `spn_sqlmesh_cicd`
- Privileges: write to `<domain>.qa_*` and `<domain>.prod_*` layer schemas, ownership where required

### SQL warehouses (dev)
- One warehouse per domain/product: `wh_team_<domain_product>_dev`
- Grants:
  - `CAN_USE` to both `team_<domain_product>_ae_dev` and `team_<domain_product>_de_dev`
- Data access remains enforced by UC per user/group.
