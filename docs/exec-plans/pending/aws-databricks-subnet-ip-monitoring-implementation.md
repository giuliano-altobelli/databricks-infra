# Databricks Subnet IP Monitoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add AWS-only monitoring that publishes per-subnet “free/used IPs” metrics and alerts when any dedicated Databricks subnet has `< 100` free IPs or `> 60%` utilization.

**Architecture:** EventBridge triggers a Lambda on a fixed schedule. Lambda calls EC2 `DescribeSubnets`, computes usable/free/used/utilization, and publishes custom CloudWatch metrics. Terraform provisions Lambda, IAM, EventBridge schedule, CloudWatch alarms (two per subnet), and SNS notification target.

**Tech Stack:** Terraform (AWS provider), AWS Lambda (Python), EventBridge, CloudWatch (custom metrics + alarms), SNS.

---

## Prereqs / Notes

- Canonical design doc: `docs/aws/monitoring/design/databricks-subnet-ip-monitoring-design.md`
- This repository’s isolated enterprise path sources subnets from:
  - `module.vpc[0].private_subnets` (compute)
  - `module.vpc[0].intra_subnets` (PrivateLink/endpoints)
- Terraform plan/apply commands must follow repo conventions (see `AGENTS.md`).

### Task 1: Create an isolated worktree

**Files:** none

**Step 1: Create a feature branch + worktree**

Run:

```bash
git worktree add -b feat/databricks-subnet-ip-monitoring ../databricks-infra-subnet-ip-monitoring
cd ../databricks-infra-subnet-ip-monitoring
```

Expected: working tree created with the repo checked out.

**Step 2: Confirm status**

Run: `git status`
Expected: clean working tree.

### Task 2: Add monitoring variables

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/variables.tf`

**Step 1: Add variables**

Add inputs (names match the design doc):

```hcl
variable "ip_monitoring_enabled" {
  description = "Enable subnet IP monitoring (CloudWatch custom metrics + alarms)."
  type        = bool
  default     = false
}

variable "ip_monitoring_subnet_ids_private" {
  description = "Optional override: private/compute subnet IDs to monitor."
  type        = list(string)
  default     = null
}

variable "ip_monitoring_subnet_ids_intra" {
  description = "Optional override: intra/endpoint subnet IDs to monitor."
  type        = list(string)
  default     = null
}

variable "ip_monitoring_free_ip_threshold" {
  description = "Alarm threshold for FreeIpCount."
  type        = number
  default     = 100
}

variable "ip_monitoring_utilization_threshold_pct" {
  description = "Alarm threshold for UtilizationPct."
  type        = number
  default     = 60
}

variable "ip_monitoring_period_seconds" {
  description = "CloudWatch metric/alarm period and Lambda schedule (seconds)."
  type        = number
  default     = 300
}

variable "ip_monitoring_sns_topic_arn" {
  description = "Optional existing SNS topic ARN for alarm notifications."
  type        = string
  default     = null
}
```

**Step 2: Format**

Run: `terraform fmt infra/aws/dbx/databricks/us-west-1/variables.tf`

Expected: no diffs (or only formatting diffs).

### Task 3: Add a unit-tested IP calculation library (pure Python)

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src/ip_math.py`
- Create: `infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/tests/test_ip_math.py`

**Step 1: Write the failing test**

Create `infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/tests/test_ip_math.py`:

```python
import unittest

from ip_math import usable_ipv4_ips, utilization_pct


class TestIpMath(unittest.TestCase):
    def test_usable_ipv4_ips(self):
        # AWS reserves 5 IPs per subnet.
        self.assertEqual(usable_ipv4_ips(24), 251)
        self.assertEqual(usable_ipv4_ips(26), 59)

    def test_utilization_pct(self):
        self.assertAlmostEqual(utilization_pct(usable=251, free=251), 0.0)
        self.assertAlmostEqual(utilization_pct(usable=251, free=0), 100.0)


if __name__ == "__main__":
    unittest.main()
```

**Step 2: Run the test to verify it fails**

Run:

```bash
python3 -m unittest infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/tests/test_ip_math.py -v
```

Expected: FAIL due to missing `ip_math` module/functions.

**Step 3: Write minimal implementation**

Create `infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src/ip_math.py`:

```python
def usable_ipv4_ips(prefix_len: int) -> int:
    host_bits = 32 - int(prefix_len)
    total = 1 << host_bits
    return max(total - 5, 0)


def utilization_pct(*, usable: int, free: int) -> float:
    usable = max(int(usable), 0)
    free = max(int(free), 0)
    if usable == 0:
        return 0.0
    used = max(usable - free, 0)
    return (used * 100.0) / usable
```

**Step 4: Run tests to verify they pass**

Run:

```bash
PYTHONPATH=infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src \
  python3 -m unittest infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/tests/test_ip_math.py -v
```

Expected: PASS.

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src/ip_math.py \
  infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/tests/test_ip_math.py
git commit -m "feat(monitoring): add subnet IP math helpers"
```

### Task 4: Implement the Lambda publisher

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src/handler.py`

**Step 1: Write minimal handler (no AWS calls yet)**

Create `infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src/handler.py` with:

```python
import json
import os
from datetime import datetime, timezone

from ip_math import usable_ipv4_ips, utilization_pct


def _load_subnets():
    raw = os.environ["SUBNETS_JSON"]
    return json.loads(raw)


def _dimensions(*, subnet_id: str, subnet_role: str, resource_prefix: str):
    return [
        {"Name": "SubnetId", "Value": subnet_id},
        {"Name": "SubnetRole", "Value": subnet_role},
        {"Name": "ResourcePrefix", "Value": resource_prefix},
    ]


def lambda_handler(event, context):
    # Implementation fills in AWS calls + PutMetricData in next steps.
    now = datetime.now(tz=timezone.utc)
    _ = now, _load_subnets()
    return {"ok": True}
```

**Step 2: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src/handler.py
git commit -m "feat(monitoring): add subnet IP monitor lambda scaffold"
```

**Step 3: Add EC2 + CloudWatch calls**

Update `lambda_handler` to:

- Build `SubnetIds` from `SUBNETS_JSON`
- `ec2.describe_subnets(SubnetIds=[...])`
- For each subnet:
  - parse prefix from `CidrBlock` (`.../24`)
  - compute `usable/free/used/utilization`
  - `cloudwatch.put_metric_data` to publish:
    - `FreeIpCount`, `UsableIpCount`, `UsedIpCount`, `UtilizationPct`
- Use chunking of at most 20 metric data points per PutMetricData call.

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/monitoring/subnet_ip_monitor/src/handler.py
git commit -m "feat(monitoring): publish subnet IP metrics to CloudWatch"
```

### Task 5: Terraform packaging + Lambda + schedule

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/monitoring_ip.tf`

**Step 1: Package the Lambda**

In `infra/aws/dbx/databricks/us-west-1/monitoring_ip.tf`, add:

```hcl
locals {
  ip_monitor_subnets_private = var.ip_monitoring_subnet_ids_private != null ? var.ip_monitoring_subnet_ids_private : (
    local.enable_privatelink ? module.vpc[0].private_subnets : []
  )
  ip_monitor_subnets_intra = var.ip_monitoring_subnet_ids_intra != null ? var.ip_monitoring_subnet_ids_intra : (
    local.enable_privatelink ? module.vpc[0].intra_subnets : []
  )

  ip_monitor_subnets = concat(
    [for id in local.ip_monitor_subnets_private : { id = id, role = "private" }],
    [for id in local.ip_monitor_subnets_intra : { id = id, role = "intra" }],
  )
}

data "archive_file" "subnet_ip_monitor_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/monitoring/subnet_ip_monitor/src"
  output_path = "${path.module}/.terraform-artifacts/subnet-ip-monitor.zip"
}
```

**Step 2: Add IAM role + Lambda function**

Provision:

- `aws_iam_role` (assume role `lambda.amazonaws.com`)
- `aws_iam_role_policy` allowing:
  - `ec2:DescribeSubnets`
  - `cloudwatch:PutMetricData`
  - logs permissions
- `aws_cloudwatch_log_group` for the function
- `aws_lambda_function` with env vars:
  - `SUBNETS_JSON = jsonencode(local.ip_monitor_subnets)`
  - `RESOURCE_PREFIX = var.resource_prefix`
  - `CW_NAMESPACE = "Databricks/VpcIpMonitoring"`

**Step 3: Add EventBridge schedule**

Provision:

- `aws_cloudwatch_event_rule` (rate or cron using `var.ip_monitoring_period_seconds`)
- `aws_cloudwatch_event_target`
- `aws_lambda_permission` for EventBridge invoke

**Step 4: Validate**

Run (outside sandbox):

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 \
  terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: success.

**Step 5: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/monitoring_ip.tf
git commit -m "feat(monitoring): add subnet IP metrics publisher (lambda + schedule)"
```

### Task 6: Terraform SNS + per-subnet alarms

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/monitoring_ip.tf`
- Modify: `infra/aws/dbx/databricks/us-west-1/outputs.tf`

**Step 1: Add SNS topic (optional-create)**

- If `var.ip_monitoring_sns_topic_arn` is set, use it.
- Else create `aws_sns_topic` and output its ARN.

**Step 2: Add per-subnet alarm resources**

Create `for_each` alarms for every element in `local.ip_monitor_subnets`:

- `aws_cloudwatch_metric_alarm.subnet_free_ip`
  - metric: `FreeIpCount`
  - threshold: `var.ip_monitoring_free_ip_threshold`
  - comparison: `LessThanThreshold`
- `aws_cloudwatch_metric_alarm.subnet_utilization`
  - metric: `UtilizationPct`
  - threshold: `var.ip_monitoring_utilization_threshold_pct`
  - comparison: `GreaterThanThreshold`

Alarm dimensions MUST match Lambda publishing:

```hcl
dimensions = {
  SubnetId       = each.value.id
  SubnetRole     = each.value.role
  ResourcePrefix = var.resource_prefix
}
```

Set `alarm_actions = [local.sns_topic_arn]` and `ok_actions = [local.sns_topic_arn]`.

**Step 3: Output SNS topic**

In `infra/aws/dbx/databricks/us-west-1/outputs.tf`, add:

```hcl
output "ip_monitoring_sns_topic_arn" {
  value       = local.sns_topic_arn
  description = "SNS topic used for subnet IP monitoring alarms."
}
```

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/monitoring_ip.tf infra/aws/dbx/databricks/us-west-1/outputs.tf
git commit -m "feat(monitoring): add subnet IP alarms and SNS output"
```

### Task 7: Document usage

**Files:**
- Modify: `infra/aws/dbx/databricks/us-west-1/README.md`

**Step 1: Add a short “Subnet IP Monitoring” section**

Include:

- What it does (custom metrics + alarms)
- Defaults (`<100` free, `>60%` util, 5-minute period)
- How to enable (set `ip_monitoring_enabled = true`)
- How subnet IDs are sourced in isolated vs custom mode
- How to point alarms at an existing SNS topic

**Step 2: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/README.md
git commit -m "docs: add subnet IP monitoring usage"
```

### Task 8: Verify with Terraform plan (Enterprise isolated)

**Files:** none

**Step 1: Enable monitoring in scenario vars**

Option A (preferred): create a small override tfvars (do not change shared scenario files):

- Create: `infra/aws/dbx/databricks/us-west-1/ip-monitoring.auto.tfvars`

```hcl
ip_monitoring_enabled = true
```

**Step 2: Run plan**

Run (outside sandbox):

```bash
DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 \
  terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario3.enterprise-create-isolated.tfvars
```

Expected plan includes (gated by `ip_monitoring_enabled`):

- Lambda + IAM + log group
- EventBridge schedule + permission
- CloudWatch alarms: 2 * (private + intra) subnet count
- SNS topic (if not using an existing topic ARN)

**Step 3: Deploy and validate alarms**

- Apply using the same repo command convention.
- Confirm metrics appear in CloudWatch under `Databricks/VpcIpMonitoring`.
- To validate alarm wiring quickly, temporarily set thresholds to be immediately breaching and confirm SNS notifications.
