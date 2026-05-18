# Databricks ABAC Chat Transcript

## User

You are tasked to do deep research regarding databricks asset based access control at scale with large number of principal permuations. Creating a large number of groups as the databricks workspace scales seems like an anti pattern. Is a entitlement table at the user level recommended to avoid group bloat?

## Assistant

I’ll ground this in Databricks’ current authorization docs and distinguish platform permissions, Unity Catalog grants, and row/column level entitlement patterns, because the right answer changes by layer.

## Assistant

Yes. For fine-grained, high-cardinality access permutations, a Databricks entitlement or mapping table is a recommended pattern. It should not replace groups entirely, but it is the right way to avoid combinatorial group bloat.

Databricks’ current guidance is:

- Use Unity Catalog groups for coarse RBAC: catalog/schema/table access, ownership, admin delegation, workspace access, and broad roles. Databricks explicitly recommends account-level SCIM from your IdP, IdP-managed groups, and avoiding direct user grants where possible. See [Unity Catalog best practices](https://docs.databricks.com/aws/en/data-governance/unity-catalog/best-practices).
- Use ABAC policies with governed tags for scalable centralized row/column controls. Databricks recommends ABAC for centralized access control based on governed tags, with row filters and masks only for per-table logic or when ABAC is not adopted. See [Access control in Unity Catalog](https://docs.databricks.com/aws/en/data-governance/unity-catalog/access-control/).
- Use mapping tables when access depends on many dimensions such as user, region, department, customer/account, clearance, legal entity, project, expiration date, etc. Databricks has a dedicated tutorial titled “Use mapping tables for dynamic access control” that says a single lookup table can drive row filtering and column masking “without managing a large number of groups.” See [Use mapping tables for dynamic access control](https://docs.databricks.com/aws/en/data-governance/unity-catalog/abac/mapping-tables).

The recommended model is hybrid:

```text
IdP groups / Databricks account groups
  -> coarse access: can enter catalog/schema/table, ownership, admin roles

Unity Catalog ABAC + governed tags
  -> central policy scope: which assets/columns/rows are governed

Entitlement mapping table
  -> fine-grained decision data: user/customer/region/product/clearance/expiry
```

A user-level entitlement table is reasonable when the access model is genuinely user-specific or derived from a source system. But avoid turning it into uncontrolled per-user sprawl. Prefer entitlement rows at the lowest stable business grain: user-to-account, user-to-region, user-to-portfolio, user-to-legal-entity, or group/role-to-domain where possible.

Important caveat: mapping-table UDFs have performance cost. Databricks recommends keeping lookup tables small and simple, using SQL UDFs, avoiding complex joins/subqueries, and testing at scale. Their ABAC performance docs note that lookup tables work best when small enough to broadcast, and large lookup tables can fall back to slower shuffle joins. See [Performance considerations for ABAC policies](https://docs.databricks.com/aws/en/data-governance/unity-catalog/abac/performance).

So the short answer: yes, a governed entitlement table is recommended for high-cardinality row/column access patterns. Do not use it as a replacement for IdP groups or Unity Catalog grants; use it behind ABAC row filters/column masks to avoid one group per permutation.

## User

Perfect, use jira as an example where we have jira as a datasource and we need to restrict the "raw_issues" table based on row-level jira project keys. For example, project key `A` can only be consumed by n number of users. Creating a group per project key isn't sustainable if we have 100s or 1000s of project keys. Provide an example how you would solve this using Unity Catalog groups for coarse RBAC on the `prod_jira` catalog and ABAC for the rows.

## Assistant

I’ll make this concrete with a deployable pattern: one coarse Unity Catalog group gates the Jira catalog, and a small entitlement table drives row access by `project_key`.

## Assistant

Below is the pattern I’d use.

**Goal**

- `prod_jira` catalog access is coarse RBAC.
- `prod_jira.raw.raw_issues` is row-filtered by Jira `project_key`.
- You do not create `jira_project_A_readers`, `jira_project_B_readers`, etc.
- Access to project `A` is represented as entitlement rows, not groups.

```text
IdP / Databricks account group:
  prod_jira_consumers

Unity Catalog:
  prod_jira.raw.raw_issues

Entitlement table:
  prod_security.entitlements.jira_project_access

ABAC row filter:
  current_user() + raw_issues.project_key -> entitlement lookup
```

**Coarse RBAC**

```sql
GRANT USE CATALOG ON CATALOG prod_jira TO `prod_jira_consumers`;
GRANT USE SCHEMA ON SCHEMA prod_jira.raw TO `prod_jira_consumers`;
GRANT SELECT ON TABLE prod_jira.raw.raw_issues TO `prod_jira_consumers`;
```

This only says: “these users may query Jira data.” It does not decide which Jira projects they can see.

**Entitlement Table**

Put this in a separate security/governance catalog. Do not grant regular consumers direct access to it.

```sql
CREATE TABLE prod_security.entitlements.jira_project_access (
  user_email STRING NOT NULL,
  project_key STRING NOT NULL,
  can_read BOOLEAN NOT NULL,
  expires_on DATE,
  approved_by STRING,
  source_request_id STRING,
  updated_at TIMESTAMP
);
```

Example: project `A` has `n` users, represented as rows.

```sql
INSERT INTO prod_security.entitlements.jira_project_access VALUES
  ('alice@company.com', 'A', true, DATE '2099-12-31', 'data-owner@company.com', 'JIRA-ACCESS-1001', current_timestamp()),
  ('bob@company.com',   'A', true, DATE '2099-12-31', 'data-owner@company.com', 'JIRA-ACCESS-1002', current_timestamp()),
  ('carol@company.com', 'B', true, DATE '2099-12-31', 'data-owner@company.com', 'JIRA-ACCESS-1003', current_timestamp());
```

**Tag The Row Key**

Create a governed tag such as `jira_project_key`, then tag the `project_key` column:

```sql
ALTER TABLE prod_jira.raw.raw_issues
  ALTER COLUMN project_key SET TAGS ('jira_project_key' = '');
```

**ABAC Row Filter UDF**

```sql
CREATE OR REPLACE FUNCTION prod_security.policies.can_read_jira_project(
  project_key_arg STRING
)
RETURNS BOOLEAN
RETURN EXISTS (
  SELECT 1
  FROM prod_security.entitlements.jira_project_access e
  WHERE e.user_email = current_user()
    AND e.project_key = project_key_arg
    AND e.can_read = true
    AND (e.expires_on IS NULL OR e.expires_on >= current_date())
);
```

**ABAC Policy**

Apply the policy at the schema level so every table with a tagged Jira project column gets the same rule.

```sql
CREATE POLICY jira_project_row_filter
ON SCHEMA prod_jira.raw
ROW FILTER prod_security.policies.can_read_jira_project
TO `prod_jira_consumers`
FOR TABLES
MATCH COLUMNS has_tag('jira_project_key') AS jira_project_key
USING COLUMNS (jira_project_key);
```

Now, if Alice queries:

```sql
SELECT issue_key, project_key, summary, status
FROM prod_jira.raw.raw_issues;
```

she only sees rows where `project_key = 'A'`. Bob also sees `A`. Carol sees `B`. An unlisted user in `prod_jira_consumers` can query the table but receives no rows.

**Operational Notes**

Use groups for stable coarse roles: `prod_jira_consumers`, `prod_jira_admins`, `prod_jira_pipeline_writers`. Use the entitlement table for high-cardinality project access.

Keep the entitlement table narrow, normalized, and managed by an access workflow or pipeline. Avoid runtime joins to Jira APIs or large source tables inside the UDF. Databricks recommends ABAC for scalable tag-driven governance and explicitly documents mapping tables for this exact “too many groups” problem.

Sources: [Unity Catalog access control](https://docs.databricks.com/aws/en/data-governance/unity-catalog/access-control/), [ABAC mapping tables](https://docs.databricks.com/aws/en/data-governance/unity-catalog/abac/mapping-tables), [ABAC performance considerations](https://docs.databricks.com/aws/en/data-governance/unity-catalog/abac/performance).

## User

Perfect example, is it best practice to have n number of access tables in `prod_security.entitlements.*`. Is the goal to keep the tables in `prod_security.entitlements.` narrow and sctrictly scoped?

## Assistant

Yes. The goal is to keep entitlement tables in `prod_security.entitlements` narrow, explicit, and scoped to a coherent access decision.

I would not create one table per Jira project. I would create one table per entitlement domain or policy shape.

Good:

```text
prod_security.entitlements.jira_project_access
prod_security.entitlements.sales_region_access
prod_security.entitlements.customer_account_access
prod_security.entitlements.hr_org_access
prod_security.entitlements.finance_legal_entity_access
```

Bad:

```text
prod_security.entitlements.jira_project_A_access
prod_security.entitlements.jira_project_B_access
prod_security.entitlements.jira_project_C_access
```

For Jira, one table like this is usually enough:

```sql
prod_security.entitlements.jira_project_access (
  principal_type STRING,    -- user, group, service_principal
  principal_name STRING,    -- alice@company.com or group name
  project_key STRING,
  access_level STRING,      -- read, masked, admin_view, etc. if needed
  expires_on DATE,
  is_active BOOLEAN,
  source_system STRING,
  source_request_id STRING,
  updated_at TIMESTAMP
)
```

Keep it narrow because the table may be touched by row-filter UDFs at query time. A good entitlement table is basically an access-control index, not a business object. Avoid wide audit payloads, JSON blobs, descriptive Jira metadata, approval history, comments, and derived business attributes in the hot table. Put those in separate audit/workflow tables if needed.

A practical structure:

```text
prod_security.entitlements.jira_project_access
  -> hot path used by ABAC/UDFs

prod_security.entitlements_audit.jira_project_access_events
  -> approval history, requester, approver, reason, ticket, timestamps

prod_security.reference.jira_projects
  -> project metadata, owners, sensitivity, lifecycle state
```

The entitlement table should answer one question quickly:

```text
Can this principal access this project key right now?
```

For scale, I’d usually standardize on:

- one entitlement table per source/domain when access dimensions differ
- one row per principal-to-resource entitlement
- optional group principals for stable role-based access
- user principals only when access is genuinely user-specific
- expiration and active flags for automatic revocation
- managed writes through a pipeline or access workflow, not manual edits
- no direct read/write access for normal data consumers

So yes: `prod_security.entitlements.*` can contain multiple tables, but each should be narrow and strictly scoped. The anti-pattern is not “multiple entitlement tables”; the anti-pattern is either one giant generic entitlement table with vague semantics, or thousands of tables/groups mirroring every asset permutation.
