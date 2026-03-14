# Security Reference Architectures (SRA) - Terraform Templates

## Premium Trial Quickstart (Existing Workspace)

This module now defaults to a Premium-trial-friendly workflow that targets an existing Databricks workspace and existing Unity Catalog metastore.

1. Copy `template.tfvars.example` to a working `*.tfvars` file.
2. Fill in required values: `aws_account_id`, `databricks_account_id`, `admin_user`, `region`, `resource_prefix`, `existing_workspace_host`, and `existing_workspace_id`.
3. Keep the trial defaults:
   - `pricing_tier = "PREMIUM"`
   - `workspace_source = "existing"`
   - `network_configuration = "managed"`
   - `uc_catalog_mode = "existing"`
   - `metastore_exists = true` (recommended unless you set `metastore_storage_root` to create a metastore)
4. Run Terraform from `infra/aws/dbx/databricks/us-west-1`.

## Existing Workspace Identity Rollout

This rollout is verified only against the existing workspace and existing metastore path in `scenario1.premium-existing.tfvars`.

- Human users must already exist through Okta SCIM before Terraform runs.
- `identify.tf` manages only additional Databricks groups, memberships, workspace assignments, and entitlements for those existing users.
- Existing Unity Catalog objects are not treated as the Terraform-managed target state during this rollout.
- Phase 1 excludes Unity Catalog grants from `identify.tf`.
- Phase 2 adds fresh Terraform-managed catalogs and schemas later rather than reusing existing Unity Catalog objects as the target state.

If you previously applied the older existing-catalog flow, remove the legacy Unity Catalog resources from Terraform state before re-verifying Phase 1 so Terraform stops managing them without deleting the live workspace settings:

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 state rm \
  'databricks_default_namespace_setting.existing_catalog_default_namespace[0]' \
  'databricks_grant.existing_catalog_admin_grant[0]'
```

## Service Principal Identity Catalog

`service_principals.tf` is the root catalog for Terraform-managed Databricks service principals.

- The checked-in example demonstrates one account-scoped principal (`uat_promotion`) and one workspace-scoped principal (`workspace_agent`).
- The file is intentionally disabled by default on `main` with `local.service_principals_enabled = false`.
- Replace the example display names with real service principal names before setting `service_principals_enabled = true`.
- This layer manages only service principal creation, optional workspace assignment, and workspace entitlements.
- To leave an entitlement untouched, omit that field; to request a clear, set it explicitly to `false` (for example, `entitlements = { workspace_access = false }`).
- Credentials, Unity Catalog grants, warehouse permissions, group membership, and account roles remain outside this file.

## SQL Warehouses

`sql_warehouses.tf` is the root catalog for Terraform-managed Databricks SQL warehouses.

- The checked-in example demonstrates one workspace-scoped warehouse keyed as `analytics_ci`.
- The file is intentionally disabled by default on `main` with `local.sql_warehouses_enabled = false`.
- Stable map keys are Terraform addresses and downstream lookup keys for `module.sql_warehouses` outputs.
- Warehouse ACLs are authoritative because the module manages one `databricks_permissions` resource per warehouse.
- Groups, users, and service principals referenced in `permissions` must resolve in the target workspace by the time Terraform reaches the SQL warehouse resources, whether they already existed or were created earlier in the same graph through explicit dependencies.
- The checked-in service-principal ACL example activates only when `local.service_principals_enabled = true`; replace the example warehouse definition before enabling live compute.
- This layer manages only SQL warehouse creation plus warehouse ACLs.
- Identity creation, entitlements, workspace assignments, Unity Catalog grants, jobs, dashboards, and queries remain outside this file.

## Governed Catalog Creation

The preferred entrypoint for new governed catalog work is `catalogs_config.tf`.

- The governed catalog map includes the explicit `personal` catalog by default.
- Add additional governed domain entries alongside `personal` in `local.governed_catalog_domains`.
- Reusable governed schema and managed-volume patterns now live in `catalog_types_config.tf` as `local.catalog_types_config`.
- Each governed catalog entry can now declare `enabled`, `display_name`, `catalog_type`, `catalog_admin_group`, `reader_group`, and `managed_volume_overrides` in addition to the existing naming and `workspace_ids` fields.
- `catalog_admin_group` and `reader_group` use keys from `local.identity_groups` in `identify.tf`, not raw Databricks display names.
- `catalog_type` must reference a key in `local.catalog_types_config`. Governed catalogs default to `catalog_type = "standard_governed"`.
- `managed_volume_overrides` is optional and can add or replace managed-volume definitions from the referenced catalog type without duplicating the whole template.
- When an override matches an existing template-managed volume, the override replaces only the attributes it sets. If it sets `grants`, that override replaces the template grant list for that volume.
- Defaults preserve the prior behavior: `enabled = true`, `display_name = catalog_name`, `catalog_admin_group = "platform_admins"`, `reader_group = []`, and no managed volumes.
- Disabled catalogs create no resources and are omitted from the root `output.catalogs` map.
- Governed catalog grants remain catalog-level only in this rollout: admins receive `ALL_PRIVILEGES`, and reader groups receive `USE_CATALOG`.
- The governed path is intended for new catalog rollouts. The existing isolated path in `main.tf` still coexists for backward compatibility with the legacy single-catalog workflow.
- The legacy isolated path is planned for future archival after the governed `catalogs_config.tf` path is proven and adopted.
- To exercise the governed fan-out in verification, populate a minimal additional non-`personal` `local.governed_catalog_domains` example in a scratch copy or temporary local edit.

## Unity Catalog Storage Credentials And External Locations

Workspace-scoped Unity Catalog S3 storage credentials and external locations are configured in `storage_credential_config.tf`.

- The root locals `local.uc_storage_credentials` and `local.uc_external_locations` default to `{}` and include a fully commented example showing multiple credentials, multiple external locations, optional grants, and optional extra `workspace_ids`.
- Both securable types default to `workspace_access_mode = "ISOLATION_MODE_ISOLATED"`. In that default mode, Terraform always binds the securable to the current workspace and can bind additional workspaces on the same shared metastore through `workspace_ids`.
- Set `workspace_access_mode = "ISOLATION_MODE_OPEN"` only when the securable should be visible to all workspaces on the metastore. Open mode must not declare `workspace_ids`.
- Cross-workspace sharing is implemented through explicit `databricks_workspace_binding` resources, not by introducing additional Databricks provider aliases in this rollout.
- Grants are optional. When declared, Terraform manages them authoritatively through `databricks_grants`, so out-of-band grants on the managed storage credential or external location are not preserved.
- In the example patterns, storage credentials grant `CREATE_EXTERNAL_LOCATION`. External locations grant `CREATE_EXTERNAL_TABLE`, `CREATE_EXTERNAL_VOLUME`, or `CREATE_MANAGED_STORAGE` depending on the use case. Add `READ_FILES` or `WRITE_FILES` only when direct raw file access is intentional.
- This module is Databricks-only. AWS IAM roles and S3 prefixes stay outside Terraform here; the Databricks module accepts pre-existing `role_arn` and `s3://...` URLs and emits the generated `external_id` and `unity_catalog_iam_arn` for companion AWS automation.

### AWS Bootstrap Nuance

If the AWS IAM trust policy has not yet been patched with the Databricks-generated `external_id`, create the storage credential first with `skip_validation = true`.

After the credential exists:

1. Read the emitted `external_id` and `unity_catalog_iam_arn` from the module outputs.
2. Update the IAM trust policy outside this Terraform stack.
3. Set `skip_validation = false`.
4. Only then rely on that credential for external locations.

## Governed Unity Catalog Schemas And Managed Volumes

Governed Unity Catalog schemas and optional governed managed volumes are derived in `schema_config.tf` from `catalogs_config.tf`, `catalog_schema_config.tf`, and `catalog_types_config.tf`.

- Reusable governed schema templates now live under `schemas` inside `local.catalog_types_config`.
- The checked-in `standard_governed` catalog type resolves to `raw`, `base`, `staging`, `final`, and `uat`.
- This rollout creates governed schemas only. It does not create `personal.<user_key>` schemas.
- Template schema entries can currently declare optional `comment` and `properties`.
- Default schema grants are derived from `catalogs_config.tf`: catalog admins receive `ALL_PRIVILEGES`, and catalog readers receive `USE_SCHEMA`.
- `catalog_schema_config.tf` resolves the reusable schema template for each governed catalog from its `catalog_type`.
- `schema_config.tf` remains the source of truth for created governed schemas and is where catalog-specific schema additions, property overrides, or schema-level grant replacements belong.
- Optional reusable managed volumes are declared under `managed_volumes` inside `local.catalog_types_config`.
- Catalog-specific managed-volume additions or replacements are declared under `managed_volume_overrides` on each governed catalog entry in `catalogs_config.tf`.
- Governed managed volumes are flattened into the existing `unity_catalog_volumes` module as `MANAGED` volumes.
- Catalog type keys plus managed-volume map keys are part of the stable Terraform identity for derived managed volumes. Renaming them changes Terraform addresses even if the Databricks volume name stays the same.
- Omitted managed-volume `grants` inherit admin `ALL_PRIVILEGES` and reader `READ_VOLUME`.
- Explicit managed-volume `grants` replace the derived defaults rather than merging with them. The same replacement behavior applies when a catalog override sets `grants` for a template-defined volume.
- The checked-in governed `volume_config.tf` entrypoint was intentionally removed so governed schema and managed-volume policy live in one place.

## Create Workspace Later

When you are ready for Terraform-managed workspace creation, switch:

- `workspace_source = "create"`
- `network_configuration = "managed"` (Premium-safe default)
- Leave `uc_catalog_mode = null` for inferred behavior, or set it explicitly.

This enables workspace creation while still avoiding enterprise-only networking and CMK paths when `pricing_tier = "PREMIUM"`.

## Upgrade to Enterprise SRA

For full SRA behavior (customer-managed network controls, PrivateLink pathing, CMKs, restrictive AWS policies), use:

- `pricing_tier = "ENTERPRISE"`
- `workspace_source = "create"`
- `network_configuration = "isolated"` (or `custom` if pre-existing networking is managed elsewhere)
- `uc_catalog_mode = "isolated"`

If you need the previous full-enterprise sample without modification, use `template.enterprise_sra.tfvars.example`.

## Read Before Deploying

SRA is a purpose-built deployment pattern designed for highly secure and regulated customers. The default entrypoint is now Premium-trial-first, while enterprise SRA capabilities remain available through input flags.

This architecture includes specific functionalities that may affect certain use cases, as outlined below.

- **No outbound internet traffic**: There is no outbound internet access from the classic compute plane or serverless compute plane.
    - To add packages to classic compute or serverless compute, set up a private repository for scanned packages.
    - Consider using a modern firewall solution to connect to public API endpoints if public internet connectivity is required.

- **Restrictive AWS Resource Policies**: Restrictive endpoint policies have been implemented for the workspace root storage bucket, S3 gateway endpoint, STS interface endpoint, and Kinesis endpoint. These restrictions are continuously refined as the product evolves.
    - Policies can be adjusted to allow access to additional AWS resources, such as other S3 buckets.
    - If you encounter unexpected product behavior due to a policy in this repository, please raise a GitHub issue.

- **Isolated Unity Catalog Securables**: Unity Catalog securables like catalogs, Storage Credentials, and External Locations are isolated to individual workspaces.
    - To share securables between workspaces, update the resources using the [databricks_workspace_binding](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) resource.

## Customizations

Terraform customizations are available to support the baseline deployment of the Security Reference Architecture (SRA). These customizations are organized by provider:

- **Workspace**: Databricks workspace provider.

These extensions can be found in the top-level customization folder.

## SRA Component Breakdown and Description

In this section, we break down the core components included in this Security Reference Architecture.

Various `.tf` scripts contain direct links to the Databricks Terraform documentation. You can find the [official documentation here](https://registry.terraform.io/providers/databricks/databricks/latest/docs).

### Network Configuration

Choose from three network configurations for your workspaces: **managed**, **isolated**, or **custom**.

- **Managed (Default)**: Databricks-managed networking for trial and quickstart scenarios.

- **Isolated**: Opting for 'isolated' prevents any traffic to the public internet, limiting traffic to AWS private endpoints for AWS services or the Databricks control plane.
   - **NOTE**: A Unity Catalog-only configuration is required for any clusters running without access to the public internet. Please see the official documentation [here](https://docs.databricks.com/aws/en/data-governance/unity-catalog/disable-hms).

- **Custom**: Selecting 'custom' allows you to specify your own VPC ID, subnet IDs, security group IDs, and PrivateLink endpoint IDs. This mode is recommended when networking assets are created in different pipelines or pre-assigned by a centralized infrastructure team.

### Core AWS Components

- **Customer-managed VPC**: A [customer-managed VPC](https://docs.databricks.com/administration-guide/cloud-configurations/aws/customer-managed-vpc.html) allows Databricks customers to exercise more control over network configurations to comply with specific cloud security and governance standards required by their organization.

- **S3 Buckets**: Three S3 buckets are created to support the following functionalities:
    - [Workspace Root Bucket](https://docs.databricks.com/en/admin/account-settings-e2/storage.html)
    - [Unity Catalog - Workspace Catalog](https://docs.databricks.com/en/catalogs/create-catalog.html)
    - [Audit Log Delivery Bucket](https://docs.databricks.com/aws/en/admin/account-settings-e2/audit-aws-storage)

- **IAM Roles**: Three IAM roles are created to support the following functionalities:
    - [Classic Compute (EC2) Provisioning](https://docs.databricks.com/en/admin/account-settings-e2/credentials.html)
    - [Data Access for Unity Catalog - Workspace Catalog](https://docs.databricks.com/en/connect/unity-catalog/cloud-storage/storage-credentials.html#step-1-create-an-iam-role)
    - [Audit Log Delivery IAM Role](https://docs.databricks.com/aws/en/admin/account-settings-e2/audit-aws-credentials)

- **AWS VPC Endpoints for S3, STS, and Kinesis**: Using AWS PrivateLink, a VPC endpoint connects a customer's VPC to AWS services without traversing public IP addresses. [S3, STS, and Kinesis endpoints](https://docs.databricks.com/administration-guide/cloud-configurations/aws/privatelink.html#step-5-add-vpc-endpoints-for-other-aws-services-recommended-but-optional) are best practices for enterprise Databricks deployments. Additional endpoints can be configured based on your use case (e.g., Amazon DynamoDB and AWS Glue).
    - **NOTE**: Restrictive VPC endpoint policies have been implemented for S3, STS, and Kinesis. To access additional S3, STS, or Kinesis resources via the classic compute plane, please update these resources accordingly.
    - **NOTE**: These VPC endpoint policies are purpose-built for the bare minimum Databricks classic compute plane connectivity. For additional buckets, please update the S3 endpoint policy. For other resources, please update each endpoint as required.

- **Back-end AWS PrivateLink Connectivity**: AWS PrivateLink provides a private network route from one AWS environment to another. [Back-end PrivateLink](https://docs.databricks.com/administration-guide/cloud-configurations/aws/privatelink.html#overview) is configured so that communication between the customer's classic compute plane and the Databricks control plane does not traverse public IP addresses. This is accomplished through Databricks-specific interface VPC endpoints. Front-end PrivateLink is also available for customers to keep user traffic over the AWS backbone, though front-end PrivateLink is not included in this Terraform template.

- **Scoped-down IAM Policy for the Databricks cross-account role**: A [cross-account role](https://docs.databricks.com/administration-guide/account-api/iam-role.html) is needed for users, jobs, and other third-party tools to spin up Databricks clusters within the customer's classic compute plane. This role can be scoped down to function only within the classic compute plane's VPC, subnets, and security group.

- **AWS KMS Keys**: Three AWS KMS keys are created to support the following functionalities:
    - [Workspace Storage](https://docs.databricks.com/en/security/keys/customer-managed-keys.html#customer-managed-keys-for-workspace-storage)
    - [Managed Services](https://docs.databricks.com/en/security/keys/customer-managed-keys.html#customer-managed-keys-for-managed-services)
    - [Unity Catalog - Workspace Catalog](https://docs.databricks.com/en/connect/unity-catalog/cloud-storage/manage-external-locations.html#configure-an-encryption-algorithm-on-an-external-location)

### Core Databricks Components

- **Unity Catalog**: [Unity Catalog](https://docs.databricks.com/data-governance/unity-catalog/index.html) is a unified governance solution for data and AI assets, including files, tables, and machine learning models. It provides granular access controls with centralized policy, auditing, and lineage tracking—all integrated into the Databricks workflow.

- **System Tables Schemas**: [System Tables](https://docs.databricks.com/en/admin/system-tables/index.html) provide visibility into access, compute, Lakeflow, query, serving, and storage logs. These tables can be found within the system catalog in Unity Catalog.

- **Cluster Example**: An example cluster and cluster policy. **NOTE:** This will create a cluster within your Databricks workspace, including the underlying EC2 instance.

- **Audit Log Delivery**: Low-latency delivery of Databricks logs to an S3 bucket in your AWS account. [Audit logs](https://docs.databricks.com/aws/en/admin/account-settings/audit-log-delivery) contain two levels of events: workspace-level audit logs with workspace-level events, and account-level audit logs with account-level events. Additionally, you can generate more detailed events by enabling verbose audit logs. 
   - **NOTE**: Audit log delivery can only be configured twice for a single account. It's recommended that once it is configured, you set *audit_log_delivery_exists* = *true* for subsequent runs.

- **Restrictive Network Policy**: [Network policies](https://docs.databricks.com/aws/en/security/network/serverless-network-security/manage-network-policies) provide egress controls for serverless compute. A restrictive network policy is implemented on the workspace, allowing outbound traffic only to required data buckets.

---

## Critical Next Steps

- **Implement a Front-End Mitigation Strategy**:
    - [IP Access Lists](https://docs.databricks.com/en/security/network/front-end/ip-access-list.html): The Terraform code for enabling IP access lists can be found in the customization folder.
    - [Front-End PrivateLink](https://docs.databricks.com/en/security/network/classic/privatelink.html#step-5-configure-internal-dns-to-redirect-user-requests-to-the-web-application-front-end).

- **Implement Single Sign-On, Multi-Factor Authentication, and SCIM Provisioning**: Most enterprise deployments enable [Single Sign-On (SSO)](https://docs.databricks.com/administration-guide/users-groups/single-sign-on/index.html) and multi-factor authentication (MFA). For user management, we recommend integrating [SCIM (System for Cross-domain Identity Management)](https://docs.databricks.com/dev-tools/api/latest/scim/index.html) with your account console.

---

## Govcloud Deployments

- **Region**: `region` must be set as `us-gov-west-1`.
- **Govcloud Shard**: `databricks_gov_shard` must be either `civilian` or `dod`. For all non-govcloud deployments (commercial regions) `databricks_gov_shard` should remain null.
    - **NOTE**: `dod` is only available to customers with a .mil email address.

---

## Additional Security Recommendations

This section provides additional security recommendations to help maintain a strong security posture. These cannot always be configured in this Terraform script or may be specific to individual customers (e.g., SCIM, SSO, Front-End PrivateLink, etc.).

- **Segment Workspaces for Data Separation**: This approach is particularly useful when teams such as security and marketing require distinct data access.
- **Avoid Storing Production Datasets in Databricks File Store**: The DBFS root is accessible to all users in a workspace. Specify a location on external storage when creating databases in the Hive metastore.
- **Back Up Assets from the Databricks Control Plane**: Use tools such as the Databricks [migration tool](https://github.com/databrickslabs/migrate) or [Terraform exporter](https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/experimental-exporter).
- **Regularly Restart Databricks Clusters**: Restart clusters periodically to ensure the latest compute resource images are used.
- **Evaluate Your Workflow for Git Repos or CI/CD Needs**: Integrate CI/CD for code scanning, permission control, and sensitive data detection.

---

## Getting Started

1. Clone this repository.
2. Install [Terraform](https://developer.hashicorp.com/terraform/downloads).
3. In `infra/aws/dbx/databricks/us-west-1`, copy `template.tfvars.example` to a new `*.tfvars` file and fill in your values.
4. If needed, start from `template.enterprise_sra.tfvars.example` for a full-enterprise baseline.
5. Decide your operation mode (`workspace_source` and `pricing_tier`) and Unity Catalog mode (`uc_catalog_mode`).
6. Configure the [AWS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration) and [Databricks](https://registry.terraform.io/providers/databricks/databricks/latest/docs#authentication) provider authentication.
7. Change directory into `infra/aws/dbx/databricks/us-west-1`.
8. Run `terraform init`.
9. Run `terraform validate`.
10. Run `terraform plan -var-file <your-file>.tfvars`.
11. Run `terraform apply -var-file <your-file>.tfvars`.

---

## Network Diagram

![Architecture Diagram](https://github.com/databricks/terraform-databricks-sra/blob/main/aws/img/Isolated%20-%20Network%20Topology.png)
