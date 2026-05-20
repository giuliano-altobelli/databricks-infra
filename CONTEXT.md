# Databricks Infrastructure Access Control

This context defines the domain language for Databricks identity, Unity Catalog access, and ABAC governance in this repository.

## Language

**Workspace Entitlement**:
A Databricks workspace capability assigned to a user, group, or service principal, such as workspace access or SQL access.
_Avoid_: Entitlement table

**Access Mapping Table**:
A governed lookup table that stores fine-grained principal-to-resource access facts, including explicit principal identity, used by ABAC row filters or column masks.
_Avoid_: Entitlement table, permission table

**Source Access Map**:
An access mapping table that stores authored access rules, including durable group principals and explicit user exceptions.
_Avoid_: Separate namespace

**Effective Access Map**:
A materialized access mapping table that expands source rules into effective user-to-resource access facts read by ABAC policy UDFs.
_Avoid_: Separate namespace, dynamic group lookup

**Access Decision Shape**:
The stable business grain and predicate structure of a fine-grained access decision, such as principal-to-Jira-project or principal-to-region.
_Avoid_: One table per resource, one generic table for everything

**Access Level**:
A named positive access decision in an access mapping table, such as read, masked, or admin view.
_Avoid_: Deny row without conflict rules

**Effective-Time Model**:
The access mapping design that determines whether an access decision is currently effective.
_Avoid_: Required lifecycle column names

**Access Workflow**:
A governed approval and change process that is the source of truth for fine-grained access decisions.
_Avoid_: Direct table edits

**Approval Ledger**:
An audit history of requested, approved, denied, expired, and revoked fine-grained access changes.
_Avoid_: Access mapping table

**Source Decision ID**:
A stable identifier linking a hot access mapping row back to the access workflow or approval ledger that authorized it.
_Avoid_: Inline approval history

**Access Mapping Principal**:
A user, stable governance-owned group, or approved service principal named in an access mapping row as the subject of a fine-grained access decision.
_Avoid_: Implicit user

**Durable Access Role**:
A coarse, stable, governance-owned group that represents an approved access role suitable for use as an access mapping principal.
_Avoid_: High-cardinality convenience group

**User Access Exception**:
A user-level access mapping used for explicit exceptions, temporary access, or break-glass cases.
_Avoid_: Default user-only mapping

**Platform Governance Catalog**:
A reserved Unity Catalog namespace for access-control support objects such as policy UDFs, access mapping tables, governance reference data, and audit evidence.
_Avoid_: Domain catalog, source catalog

**Platform Governance Schema**:
A schema inside the platform governance catalog whose name communicates the primary object type or governance concern it contains.
_Avoid_: Generic bucket

**Policy Function Schema**:
The platform governance schema that primarily contains UDFs called by ABAC policies.
_Avoid_: Policy table namespace

**Policy-Supporting UDF**:
A function called by an ABAC policy to evaluate row access or column masking behavior.
_Avoid_: Domain-specific UDF by default

**Access-Control Primitive**:
A reusable platform or security-owned building block that makes ABAC enforcement consistent across domains, such as a governed tag, policy-supporting UDF, or standard access mapping table shape.
_Avoid_: Domain logic

**Application Team**:
A team that owns data production and domain logic inside governed tables.
_Avoid_: Policy owner

**Security/Platform Team**:
A team that owns reusable access-control primitives and the platform shape needed for consistent policy enforcement.
_Avoid_: Data producer

**Static Platform Validation**:
Terraform validation of platform-declared access-control invariants that are known before runtime tables are produced.
_Avoid_: Runtime table conformance

**Runtime Object Validation**:
Flyte validation that produced tables, tags, policies, and grants conform to the ABAC governance contract.
_Avoid_: Terraform table inspection

**Unity Catalog Grant**:
A Unity Catalog privilege assignment that gives a principal baseline access to a catalog, schema, table, or other securable.
_Avoid_: ABAC entitlement

**ABAC Policy**:
A Terraform-owned Unity Catalog policy that applies row filtering or column masking based on governed tags and policy logic, even when attached to a domain securable.
_Avoid_: Table grant

**ABAC Governance Boundary**:
An explicit table-level contract declaring that a table intentionally participates in ABAC governance.
_Avoid_: Accidental policy scope

**Protected Column Tag**:
A column-level governed tag that identifies a data element requiring specific ABAC behavior.
_Avoid_: Table participation marker

**Governed Table Tag**:
A table-level governed tag that declares a table is intentionally inside the ABAC governance boundary.
_Avoid_: Sensitive column marker

**Highest Safe Scope**:
The broadest Unity Catalog policy scope whose rule, governed tag vocabulary, target principals, and exceptions are semantically consistent.
_Avoid_: Broadest possible scope

**Fail-Closed Row Access**:
The rule that a principal with baseline query access sees zero protected rows unless an access mapping row grants current effective access.
_Avoid_: Default allow

**External Unity Catalog Delta Read**:
A read path where a non-Databricks engine uses Unity Catalog to resolve and access governed Delta table data instead of directly targeting cloud storage paths.
_Avoid_: Raw S3 Delta read, SQL result ingestion

**External Reader Principal**:
A user or service principal authorized to read Unity Catalog-governed data from outside Databricks through Unity Catalog external access.
_Avoid_: Shared user token, raw storage credential

## Relationships

- A **Unity Catalog Grant** gives a principal baseline access before an **ABAC Policy** further restricts rows or columns.
- An **ABAC Policy** remains a platform control even when attached to a domain catalog, schema, or table.
- An **ABAC Policy** may consult an **Access Mapping Table** for high-cardinality access decisions.
- An **ABAC Policy** should be defined at the **Highest Safe Scope** and constrained by governed tags.
- A **Governed Table Tag** declares ABAC participation; a **Protected Column Tag** identifies the sensitive data element and policy behavior.
- A table in a catalog with an **ABAC Policy** is not inside the **ABAC Governance Boundary** unless it carries a **Governed Table Tag** or the deployment path is explicitly governed-only.
- **Static Platform Validation** covers declared platform controls; **Runtime Object Validation** covers produced table conformance.
- An **Access Workflow** owns fine-grained access decisions and materializes current effective access into an **Access Mapping Table**.
- An **Approval Ledger** records why access changed; an **Access Mapping Table** answers whether access is currently effective.
- A **Source Decision ID** links an **Access Mapping Table** row to the **Approval Ledger** without copying workflow history into the hot table.
- A **Source Access Map** may contain **Durable Access Roles**; an **Effective Access Map** expands those roles to user-level facts for ABAC policy UDFs.
- An **Access Mapping Table** is scoped by **Access Decision Shape**, not by individual resource and not by every possible access model.
- An **Access Mapping Table** contains one or more **Access Mapping Principals** for each protected business resource.
- A **Durable Access Role** may be an **Access Mapping Principal**; a **User Access Exception** is reserved for explicit exceptions, temporary access, or break-glass cases.
- **Fail-Closed Row Access** applies when a principal has a **Unity Catalog Grant** but no matching **Access Mapping Table** row.
- A **Platform Governance Catalog** contains **Access Mapping Tables** but is not readable through normal domain-reader access.
- Normal data consumers do not directly read `prod_security.access_maps.*`; policy UDFs and controlled workflows use them as policy support data.
- Normal data consumers do not directly read `prod_security.access_audit.*`; sanitized reporting views require a future spec.
- `prod_security.reference.*` visibility is undecided and requires a leadership answer.
- `prod_security.policies` is a **Policy Function Schema**; its main purpose is to hold UDFs/functions used by **ABAC Policies**.
- Reusable **Policy-Supporting UDFs** live in `prod_security.policies`; domain-specific UDFs require a future scoped spec.
- **Security/Platform Teams** own **Access-Control Primitives**; **Application Teams** own data production and domain logic inside governed tables.
- A **Workspace Entitlement** does not grant Unity Catalog data access by itself.
- An **External Unity Catalog Delta Read** still requires the reader principal to have the necessary **Unity Catalog Grants** on the target catalog, schema, and table.
- A production **External Unity Catalog Delta Read** should use a service principal as its **External Reader Principal**; human users are for interactive or development reads.

## Example Dialogue

> **Dev:** "Should Jira project access live in an entitlement table?"
> **Domain expert:** "Call it an **Access Mapping Table** in the **Platform Governance Catalog**. A **Governed Table Tag** declares ABAC participation, while a **Protected Column Tag** identifies the sensitive field used by policy logic."

## Flagged Ambiguities

- "entitlement table" was used to mean ABAC lookup data, but this repo already uses "entitlements" for Databricks workspace capabilities. Resolved: use **Access Mapping Table** for ABAC lookup data and **Workspace Entitlement** for Databricks workspace capabilities.
- `prod_security` looks like a normal `prod_<source>` governed domain catalog but has different access semantics. Resolved: treat it as a **Platform Governance Catalog** and not as a domain/source catalog.
- `prod_security.policies.*` can be misread as policy tables. Resolved: `prod_security.policies` is primarily a **Policy Function Schema** for UDFs/functions called by ABAC policies.
- A protected column tag alone could mean deliberate governance, partial migration, accidental tagging, or missing policy wiring. Resolved: table-level **Governed Table Tags** declare ABAC participation, and **Protected Column Tags** identify protected data elements.
- Group principals are allowed for authored access rules, but ABAC policy UDFs should not routinely resolve group membership dynamically. Resolved: UDFs read **Effective Access Maps** materialized from **Source Access Maps**.
- Source and effective access maps are both **Access Mapping Tables** under `prod_security.access_maps.*`; this direction doc does not standardize a separate suffix or namespace.
- `prod_security.reference.*` may contain broadly useful governance vocabulary or sensitive policy metadata. Unresolved: visibility requires a leadership decision.
- Runtime validation promotion blocking for ABAC-governed tables is unresolved and requires a leadership decision.
- "DuckDB reading Databricks data" can mean either external Delta reads through Unity Catalog or SQL result ingestion through a Databricks SQL warehouse. Resolved for this design: use **External Unity Catalog Delta Read**.
- "Read data via a user or service principal" can imply shared credentials. Resolved: production reads use a service principal, while human-user reads remain interactive or development access under the user's own identity.
