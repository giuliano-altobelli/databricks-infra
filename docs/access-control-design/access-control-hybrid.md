# Access Control Hybrid (Unity Catalog RBAC + ABAC) — Design

Date: 2026-03-03

## Objective

Document a practical **hybrid** access-control process for Databricks where:

- Unity Catalog privileges (RBAC) control **which objects** a principal can query.
- Unity Catalog ABAC (governed tags + policies) enforces **row filtering** and **column masking** inside those objects.
- Workspace-level permissions ensure the user can log into the workspace and execute queries.

## Scope (required by repo rules)

In scope:

- Unity Catalog
- Workspace-level

Out of scope:

- Account-level identity provisioning (users/groups/SCIM)
- Comparing RBAC vs ABAC as competing models (doc focuses on hybrid only)

## Confirmed context

- Catalogs: `prod_marketing_googleads`, `prod_marketing_salesforce`
- Schemas: `<layer>` = `raw|base|staging|final`
- Scenario: `userA` reads all of Googleads across layers, but only a small allowlist in Salesforce (optionally can discover Salesforce metadata without being able to query data).

## Selected design

### Access pattern

- **Googleads**: grant broad read at catalog+schema levels (layer schemas), avoiding per-table churn.
- **Salesforce**: grant `BROWSE` broadly (optional) for discoverability, but `SELECT` only on an explicit allowlist of tables/views.
- **ABAC**: apply both:
  - **Column masking** using governed tags (for example `pii=email|ssn|...`)
  - **Row filtering** using governed tags to identify the “region” column (for example `geo_region=true`)

### Policy mechanics

- Policies are created at the highest sensible scope (catalog or schema) and match columns by tags.
- UDFs used by policies are designed to be reusable; identity checks belong in the policy (principals), not in the UDF.

### Deliverables

- Update `access_control.md` to be a step-by-step hybrid playbook including:
  - Mermaid overview flowchart
  - Concrete “userA” walkthrough (Googleads broad + Salesforce allowlist)
  - Terraform management matrix (pseudocode)

