# Databricks Subnet IP Monitoring Design

Date: 2026-03-05

## Objective

Provide ongoing monitoring and alerting for IPv4 address consumption (“IPs reserved”) in a **dedicated** AWS VPC used exclusively by a production **enterprise** Databricks workspace.

## Context

In a customer-managed VPC deployment, IP exhaustion in any workspace subnet can prevent new cluster nodes, endpoints, or supporting infrastructure from provisioning. Because the VPC and subnets are dedicated to Databricks, subnet-level IP utilization is a sufficient proxy for “Databricks IPs reserved”.

This repository’s Enterprise isolated path creates:

- **Compute subnets**: `module.vpc[0].private_subnets`
- **PrivateLink / endpoints subnets**: `module.vpc[0].intra_subnets`

## Requirements

- Alert if **any monitored subnet** has **< 100 free IPs**
- Alert if **any monitored subnet** has **> 60% utilization**
- Works for:
  - Enterprise isolated (Terraform-managed VPC in this repo)
  - Enterprise custom (subnet IDs provided as inputs; VPC created elsewhere)
- Low operational overhead; no Databricks API dependencies

## Key Definitions

AWS reports `AvailableIpAddressCount` per subnet. For IPv4, AWS reserves 5 IPs per subnet.

- `usable_ips = 2^(32 - prefix) - 5`
- `free_ips = AvailableIpAddressCount`
- `used_ips = usable_ips - free_ips`
- `utilization_pct = 100 * used_ips / usable_ips`

These values represent **reserved** IP capacity (any ENI allocations), which matches the operational concern: “can Databricks still allocate capacity in this subnet?”

## Selected Approach

Use AWS APIs to read subnet utilization and publish custom CloudWatch metrics, then alarm on those metrics.

### Architecture

1. **EventBridge schedule** (e.g., every 5 minutes) triggers a **Lambda** function.
2. Lambda calls **EC2 `DescribeSubnets`** for the configured subnet ID set.
3. Lambda computes `usable_ips`, `free_ips`, `used_ips`, and `utilization_pct`.
4. Lambda publishes metrics to **CloudWatch** (custom namespace).
5. **CloudWatch alarms** notify an **SNS topic**.

Lambda should run **without VPC attachment** to avoid NAT/VPC-endpoint dependencies for AWS API access.

## Metrics

Namespace: `Databricks/VpcIpMonitoring`

Dimensions:

- `SubnetId` (required)
- `SubnetRole` (`private` | `intra`) (recommended)
- `ResourcePrefix` (recommended when multiple deployments share an AWS account)

Metric names (per dimension set):

- `FreeIpCount` (count)
- `UsableIpCount` (count)
- `UsedIpCount` (count)
- `UtilizationPct` (percent)

## Alarming

Create **two alarms per subnet** (so “any subnet” pages naturally):

1. **Free IP alarm**
   - Condition: `FreeIpCount < 100`
2. **Utilization alarm**
   - Condition: `UtilizationPct > 60`

Recommended defaults:

- `period_seconds = 300`
- `evaluation_periods = 2`
- `datapoints_to_alarm = 2`
- `treat_missing_data = notBreaching` (avoid false positives during deploy/teardown)

Notification target:

- Primary: existing `sns_topic_arn` passed in
- Fallback: create a dedicated SNS topic (subscriptions managed outside this module or via optional inputs)

## Terraform Integration (Planned)

Add a small, AWS-only monitoring component under `infra/aws/dbx/databricks/us-west-1` gated by an enable flag.

Inputs:

- `ip_monitoring_enabled` (bool)
- `ip_monitoring_subnet_ids_private` (list(string), optional override)
- `ip_monitoring_subnet_ids_intra` (list(string), optional override)
- `ip_monitoring_free_ip_threshold` (number, default 100)
- `ip_monitoring_utilization_threshold_pct` (number, default 60)
- `ip_monitoring_period_seconds` (number, default 300)
- `ip_monitoring_sns_topic_arn` (string, optional)

Subnet ID sourcing:

- If Enterprise isolated + VPC created by this repo: use `module.vpc[0].private_subnets` and `module.vpc[0].intra_subnets`.
- If custom mode: require explicit subnet ID lists.

No Databricks provider aliases are needed for this feature (AWS-only resources).

## IAM and Security

Lambda execution role permissions:

- `ec2:DescribeSubnets`
- `cloudwatch:PutMetricData`
- CloudWatch Logs permissions (`logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`)

No secrets are required.

## Failure Modes and Mitigations

- **EC2 API throttling / transient failures**: exponential backoff + log; publish partial results when possible.
- **Subnet set changes**: Terraform-driven subnet lists keep monitoring aligned; alarms are recreated per subnet list.
- **Metric gaps during deploy**: `treat_missing_data = notBreaching`.

## Acceptance Criteria

- CloudWatch shows per-subnet `FreeIpCount` and `UtilizationPct` for all configured subnets.
- Alarms fire when thresholds are crossed (validated by temporarily setting thresholds above current values).
- Alarm notifications identify the specific subnet ID (and role, if included) causing the breach.
