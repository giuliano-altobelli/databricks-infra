# Databricks RBAC and ABAC Ownership Strategy

Date: 2026-05-01

### Problem Context

This repository is moving toward a hybrid Databricks access-control model. Unity Catalog privileges, workspace assignments, entitlements, and compute controls define baseline access. ABAC policies then add dynamic row filters and column masks after base access has been granted.

The current architecture already treats Terraform as the source of truth for Databricks identity, workspace access, and Unity Catalog grants. The open design question is how to add governed tags and ABAC policy operations without creating unclear ownership between Terraform, sqlmesh, and Flyte.

This document is a direction and knowledge artifact. It is not an implementation plan, does not queue live Terraform resources, and should not be read as approval to add ABAC infrastructure without a scoped spec or follow-up design.

The relevant operating assumptions are:

- sqlmesh owns Databricks transform definitions and can declare model, table, and column metadata near the objects it creates.
- Flyte orchestrates sqlmesh and can run post-run validation or reconciliation steps.
- Terraform remains the auditable platform-control layer for stable account, workspace, Unity Catalog, and governance configuration.
- ABAC depends on governed tags being correct, so tag assignment is part of the security boundary and must be validated, not treated as best-effort metadata.

### North Star

Databricks access control is layered, auditable, and deterministic:

- Terraform defines stable platform controls.
- sqlmesh declares the data classification intent beside the model code.
- Flyte reconciles actual Databricks metadata to declared intent and publishes evidence.
- Unity Catalog enforces both baseline privileges and ABAC row or column restrictions at query time.

In the target state, a reader can answer three questions from versioned artifacts and run evidence:

1. Who has baseline access to this object?
2. Which governed tags should this table or column have?
3. Which ABAC policies apply because of those tags?

### High-Level Plan

#### Ownership Boundary

Terraform owns stable platform controls:

- governed tag definitions
- allowed tag values
- governed tag assignment permissions
- Databricks groups, users, service principals, roles, workspace assignments, and entitlements
- Unity Catalog catalogs, schemas, storage objects, workspace bindings, and grants
- access mapping table definitions or deployment hooks, but not high-cardinality access mapping rows
- stable ABAC policy definitions that represent reusable governance rules
- stable governance UDF references and prerequisite permissions required by those policies

Application teams own data production and domain logic inside governed tables:

- source ingestion and transformation logic
- business columns and row semantics, such as Jira project keys
- model-local data contracts and table shape, within the constraints of the platform controls

Security/platform teams own reusable access-control primitives:

- standard access mapping table shapes
- reusable policy-supporting UDFs
- standard governed tag vocabulary and enforcement patterns
- policy validation expectations and evidence requirements

Access workflows own fine-grained access decisions:

- Jira/project-owner approval and revocation rules
- current effective principal-to-resource access facts
- materialization of narrow access mapping rows used by ABAC policies
- approval and revocation history in separate audit/workflow tables

Access mapping tables are enforcement indexes, not approval ledgers. They should stay narrow enough for query-time policy checks and should not carry approval comments, full workflow history, Jira metadata, or other wide audit payloads.

When a principal has coarse Unity Catalog access but no matching access mapping row for a protected resource, ABAC row access fails closed to zero rows. Coarse RBAC grants the ability to query the domain object; access mappings grant effective visibility into protected rows.

sqlmesh owns model-local tag intent:

- expected table tags for sqlmesh-owned objects
- expected column tags for sqlmesh-owned objects
- optional direct application of table and column tags when sqlmesh can do so reliably
- model artifacts that Flyte can read after a run

Flyte owns orchestration, reconciliation, and evidence:

- runs sqlmesh
- reads sqlmesh artifacts after the run
- compares expected tags with actual Databricks tags
- applies missing or removal tag changes only when sqlmesh cannot
- validates governed tag conformance before promotion is considered successful
- publishes audit and drift evidence for each run

Flyte is not the access-control authority. It is a reconciler that works from declared desired state.

#### Policy Definition Rule

ABAC policy definitions should default to Terraform ownership when they are stable platform controls.

ABAC policies remain platform controls even when they attach to domain catalogs, schemas, or tables. Attachment location does not imply domain-team ownership.

Examples:

- Mask columns tagged `pii=ssn` for reader groups.
- Hide rows tagged with restricted regions from non-approved analyst groups.
- Restrict unclassified data until reviewed.
- Exempt trusted release or ETL service principals where Databricks runtime behavior requires unfiltered access.

Flyte may own ABAC policy reconciliation only when the policy is genuinely generated or derived from runtime metadata, sqlmesh artifacts, or domain-specific deployment state.

Examples:

- Generate one domain-specific row policy per sqlmesh domain.
- Generate policies from model contracts that change with deployment metadata.
- Create temporary or environment-specific policies during promotion.

Even in those cases, Flyte must handle policies as desired state:

- use stable policy names
- list current policies before applying changes
- diff desired and actual state
- update idempotently
- delete only policies it explicitly owns
- validate the effective result
- publish audit evidence

#### Policy Scope Guide

Define ABAC policies at the highest safe Unity Catalog scope.

Use catalog-level policies when the rule, governed tag vocabulary, target principals, and exceptions are consistent across the whole catalog.

Use schema-level policies when the rule is tied to a bounded layer or area, such as `raw`, `final`, or a domain-specific schema.

Use table-level policies only for exceptional, non-reusable, migration, or one-off cases.

Broad-scope policies must be constrained by governed tags through `WHEN` and `MATCH COLUMNS` conditions so catalog or schema scope does not become accidental overreach.

ABAC policies attach to governed domain securables. Reusable policy-supporting UDFs live in `prod_security.policies`.

Domain-specific UDFs are rare edge cases. They can exist only when a future scoped spec shows the rule is genuinely domain-specific and defines ownership, validation, and lifecycle.

Default to centralized reusable UDFs to avoid divergent policy behavior.

#### ABAC Participation Contract

A catalog or schema can contain both ABAC-governed and ordinary tables. Creating an untagged table inside a catalog or schema that has ABAC policies should not fail solely because the broader namespace has policies.

Every table intended to participate in ABAC must have an explicit table-level governed tag. Protected columns on that table must have the appropriate column-level protected tags.

The table-level governed tag answers: "Is this table intentionally inside the governed ABAC surface?"

The column-level protected tag answers: "Which data element requires specific policy behavior?"

This distinction is part of the platform contract. ABAC protection involves tags, policies, grants, deployment order, ownership, and validation; it is not only a column attribute.

Validation should fail when the governance contract is inconsistent, for example:

- a column has a protected column tag but the table lacks the table-level governed tag
- the table has the governed tag but required ABAC policy or grant wiring is missing
- the table claims to be governed but its protected column tags are incomplete or invalid
- a deployment path explicitly says the catalog or schema only accepts governed tables and an ungoverned table is created there

Terraform validates platform-declared invariants it can know statically, such as governed tag definitions, allowed values, catalog and schema configuration, policy definitions, and expected grants.

Flyte validates runtime object conformance after application teams produce tables, such as actual table tags, actual column tags, policy applicability, and fail-closed behavior.

Terraform should not validate tags on tables it does not create or own.

Open leadership decision: define when runtime validation evidence must block production promotion for tables inside the ABAC governance boundary.

#### Platform Governance Catalog Schemas

`prod_security` is a platform governance catalog. Its child namespaces are Unity Catalog schemas, and each schema can contain tables, views, functions, volumes, or other supported object types.

The conceptual schema layout is:

| Namespace | Mostly Contains | Meaning |
| --- | --- | --- |
| `prod_security.access_maps.*` | tables | Current effective access facts: who can access what |
| `prod_security.access_audit.*` | tables | Approval ledgers, revocations, and change history |
| `prod_security.reference.*` | tables | Reference data that explains the governance model |
| `prod_security.policies.*` | functions/UDFs | Policy-supporting functions used by ABAC policies |

`prod_security.policies` is primarily a function namespace. It may contain metadata tables if a future design needs them, but that is optional and secondary. Its main purpose is to hold UDFs called by ABAC policies.

Normal data consumers should not receive direct read access to `prod_security.access_maps.*`. Access maps are policy support data, not consumer-facing datasets. Policy UDFs and controlled security/platform workflows need the required access; consumer-facing audit or reporting should use safe views only if a future spec defines them.

Normal data consumers should not receive direct read access to `prod_security.access_audit.*`. Approval ledgers and access history can expose sensitive governance information. Default access is security/platform only, with optional sanitized reporting views later if a future spec defines them.

Open leadership decision: visibility for `prod_security.reference.*` is undecided. Some governance reference data, such as classification vocabulary, may be broadly readable, while owner mappings or policy metadata may be restricted. A future decision should classify reference tables by intended audience before access rules are standardized.

Examples:

- `prod_security.access_maps.user_region_access` as an access mapping table
- `prod_security.access_audit.approval_decisions` as an approval ledger table
- `prod_security.reference.data_classifications` as a governance reference table
- `prod_security.policies.can_access_region(...)` as a policy-supporting function
- `prod_security.policies.mask_email_for_user(...)` as a policy-supporting function

#### Access Mapping Table Grain

Access mapping tables should be scoped by access decision shape.

Use one table for a coherent predicate such as principal-to-Jira-project, principal-to-region, or principal-to-customer-account.

Avoid one giant generic access table that tries to represent every domain and predicate shape. It becomes semantically vague and hard to validate.

Avoid one table per individual resource, such as one table per Jira project key. That recreates the same resource-permutation sprawl the ABAC pattern is meant to avoid.

The preferred grain is:

- `prod_security.access_maps.jira_project_access`
- `prod_security.access_maps.user_region_access`
- `prod_security.access_maps.customer_account_access`

Each table should stay narrow, explicit, and optimized for query-time policy checks.

#### Access Mapping Principals

Access mapping tables may use group principals when the group represents a durable, governance-owned access role.

Do not make access mappings user-only by default. A user-only model can create duplicated rows, operational churn, drift, and harder reviews when many users receive the same access through an approved role.

The rule is:

```text
Group principals are allowed when the group represents a durable access role.
User principals are allowed for explicit exceptions, temporary access, or break-glass cases.
```

Good group-principal use:

```text
finance_us_analysts -> US data
finance_eu_analysts -> EU data
```

Bad group-principal use:

```text
jira_project_ABC_readers -> Jira project ABC
jira_project_DEF_readers -> Jira project DEF
```

Group principals keep the access map explicit about the authorization rule, while the identity system remains explicit about membership. For example, the access map states that `finance_us_analysts` can access US data, and the identity system states that `alice@company.com` is a member of `finance_us_analysts`.

User-level mappings are reserved for exceptions and should carry enough linkage for stronger governance, such as expiration and an approval or workflow reference.

ABAC policy UDFs should read materialized effective user access from `access_maps.*`. They should not routinely resolve group membership dynamically at query time.

The model has two conceptual layers:

- source access maps store authored access rules, including durable group principals and explicit user exceptions
- effective access maps materialize those rules into user-to-resource access facts used by ABAC policy UDFs

Both layers remain access mapping tables under `prod_security.access_maps.*`. This direction document does not standardize separate suffixes, table names, or namespaces for source and effective access maps; physical layout belongs in a future scoped spec.

The physical access-map design is intentionally deferred. A future spec may choose one table, multiple tables, views, materialized tables, or another shape, as long as the implementation preserves the agreed principles: authored rules can use durable group principals, ABAC policy UDFs read materialized effective user access, and access mapping objects remain under `prod_security.access_maps.*`.

Dynamic group resolution in UDFs is reserved for simple built-in checks or exceptional cases where performance, auditability, and reproducibility trade-offs are explicitly accepted.

Access mapping tables should expose conceptual minimum fields, without standardizing exact DDL in this direction document:

- principal identity for authored rules or effective user identity for runtime policy checks
- protected resource key
- access level or decision
- active or effective-time state
- source decision ID linking back to the access workflow or approval ledger

`access_level` is part of the conceptual model, but the default policy pattern is allow-only. Future specs may use access levels such as `read`, `masked`, or `admin_view`.

Avoid deny rows unless a future spec defines a clear conflict-resolution model for overlapping mappings.

Access mappings need an effective-time model, not a prescribed set of lifecycle columns. Future specs may use `is_active`, `valid_from`, `expires_at`, SCD records, event-derived materialization, or another design. The policy check must be able to determine whether access is currently effective.

The hot `access_maps.*` row should contain only query-time and linkage fields, such as:

- principal type
- principal name
- protected resource key
- access level
- active or effective-time state
- source decision ID

Detailed approval metadata belongs in `access_audit.*`, including approver, reason, request history, revocation history, and full audit trail.

#### Example: Jira Project Row Access

Jira project row access is an example of the general ABAC pattern, not a special implementation target.

In this scenario, coarse Unity Catalog grants let a principal query the `prod_jira` domain. Fine-grained row visibility is controlled by a narrow access mapping table in the platform governance catalog, for example `prod_security.access_maps.jira_project_access`.

The access mapping table stores current effective principal-to-project facts, such as:

- principal type
- principal name
- Jira project key
- active or expiry state

It does not store approval comments, workflow history, or Jira project metadata. Those belong in approval ledger or reference tables.

The Jira table participates in ABAC only when it carries a table-level governed tag declaring that it is inside the ABAC governance boundary. The Jira project key column carries a protected column tag identifying the data element used by the row policy.

A broad policy can be defined at catalog or schema scope if Jira row semantics are consistent at that scope. The policy must still use governed tag conditions so it applies only to intentionally governed Jira tables and the protected project-key column.

If a principal has coarse `prod_jira` access but no matching access mapping row for a Jira project key, row access fails closed to zero rows.

#### Data Flow

1. Terraform provisions governed tags, allowed values, tag permissions, RBAC, grants, and stable ABAC policies.
2. sqlmesh declares expected table and column tags near model definitions.
3. Flyte runs sqlmesh and captures the generated artifacts.
4. Flyte extracts expected tag state from the sqlmesh artifacts.
5. Flyte reads actual Databricks table and column tags.
6. Flyte reconciles missing or stale tag assignments only within its declared ownership scope.
7. Flyte validates that governed production objects have required tags before promotion succeeds.
8. Flyte publishes drift and audit evidence showing expected state, actual state, changes applied, and any failures.

#### Deployment Ordering

ABAC depends on multiple Unity Catalog and governance objects, so deployment order matters conceptually even though this document is not an implementation plan.

The intended order is:

1. Platform governance catalog and schemas exist.
2. Governed tags and allowed values exist.
3. Policy-supporting UDFs exist in `prod_security.policies`.
4. Access mapping table contracts exist under `prod_security.access_maps`.
5. Domain tables are produced and tagged.
6. ABAC policies are attached to the highest safe domain securable.
7. Runtime validation checks tags, policy applicability, and access-map behavior.

Partial deployment can create confusing or unsafe states, such as protected column tags without table-level ABAC participation tags, policies without supporting UDFs, or governed tables whose access mapping behavior cannot be validated.

#### Dual-Writer Rule

Avoid hidden dual writers.

If sqlmesh can apply tags, Flyte may still validate them, but Flyte should only reconcile from sqlmesh-declared desired state. Flyte must not invent tag intent or apply ad hoc governance rules outside versioned configuration.

If Terraform owns an ABAC policy, Flyte may validate that policy exists and behaves as expected, but Flyte must not mutate it.

If Flyte owns generated policies, Terraform should own only the prerequisites for those policies, such as governed tags, allowed values, permissions, UDF deployment dependencies, and service principals.

#### Failure Behavior

Governed production paths should fail closed.

Flyte should fail the run before promotion is considered valid when:

- required governed tags are missing
- declared tag values are not allowed by Terraform-managed tag policies
- a tag assignment API call fails
- actual tags drift from sqlmesh-declared desired state and cannot be reconciled
- a generated ABAC policy diff cannot be applied safely
- validation cannot prove the expected tags or policies are present

Failures should produce enough evidence for an operator to see the object, expected state, actual state, and blocking reason.

### Success Measurement

The direction is working when:

- Every governed tag key and allowed value is defined through Terraform.
- Every principal that can assign governed tags is granted that ability intentionally.
- Every sqlmesh-owned production table has versioned expected table and column tag intent.
- Flyte publishes an audit artifact for every governed sqlmesh run.
- Drift reports show zero unmanaged tag changes on governed production objects.
- Production promotion fails when required governed tags are missing or invalid.
- Stable ABAC policies are reviewable in Terraform plans.
- Any Flyte-generated ABAC policy has a stable owner marker, deterministic name, idempotent reconciliation, and audit evidence.

### Appendix

#### Preferred Boundary

```text
Terraform:
  - governed tag policies
  - allowed values
  - tag assignment permissions
  - RBAC, workspace entitlements, and Unity Catalog grants
  - stable ABAC policy definitions

sqlmesh:
  - model, table, and column tag intent
  - optional tag application for sqlmesh-created objects

Flyte:
  - sqlmesh orchestration
  - tag reconciliation from sqlmesh artifacts
  - ABAC validation
  - audit and drift evidence
  - generated ABAC policy reconciliation only for dynamic or derived policies
```

#### Example

sqlmesh declares what the data is:

```yaml
model: prod_salesforce_revenue.final.customer_dim
table_tags:
  sensitivity: high
columns:
  ssn:
    tags:
      pii: ssn
  country:
    tags:
      geo_region: country
```

Terraform defines the stable policy for how tagged data is protected:

```sql
CREATE POLICY mask_ssn
ON SCHEMA prod_salesforce_revenue.final
COLUMN MASK governance.mask_ssn
TO `domain_readers`
EXCEPT `platform_admins`, `release_sp`
FOR TABLES
WHEN has_tag_value('sensitivity', 'high')
MATCH COLUMNS has_tag_value('pii', 'ssn') AS ssn
ON COLUMN ssn;
```

Flyte verifies or reconciles reality:

```text
Expected:
  prod_salesforce_revenue.final.customer_dim has sensitivity=high
  prod_salesforce_revenue.final.customer_dim.ssn has pii=ssn

Actual:
  read from Databricks table and column tag APIs or information schema

Action:
  apply missing/removal tag changes only if within Flyte ownership scope
  fail closed if governed production tags cannot be proven correct
  publish audit evidence
```

#### Source Notes

- `ARCHITECTURE.md`: current Unity Catalog namespace and access model.
- `docs/adr/0001-platform-governance-catalog.md`: decision record for `prod_security` and centralized policy-supporting UDFs.
- `access_control.md`: discovery notes for evaluating a hybrid RBAC and ABAC architecture.
- Databricks Unity Catalog access control docs: https://docs.databricks.com/aws/en/data-governance/unity-catalog/access-control/
- Databricks ABAC docs: https://docs.databricks.com/aws/en/data-governance/unity-catalog/abac/
- Databricks ABAC policy docs: https://docs.databricks.com/aws/en/data-governance/unity-catalog/abac/policies
- Databricks governed tag docs: https://docs.databricks.com/aws/en/admin/governed-tags/
