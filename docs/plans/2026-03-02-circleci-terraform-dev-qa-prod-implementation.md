# CircleCI Terraform Dev→QA→Prod Promotion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a scalable CircleCI pipeline that runs Terraform checks + plans on PRs and promotes the same git SHA to **dev (auto)** → **qa (manual approval on `main`)** → **prod (manual approval on `main`)**, using S3 remote state with separate state per environment (dev uses the existing key).

**Architecture:** Create per-environment S3 backend config files (`backends/dev.hcl`, `backends/qa.hcl`, `backends/prod.hcl`) where dev keeps the existing `key = "us-west-1/databricks/terraform.tfstate"` and qa/prod use new keys. Add a `.circleci/config.yml` that uses an internal Docker image executor (placeholder) and CircleCI contexts per environment to inject AWS + Databricks OAuth M2M credentials. Each env stage runs `terraform init -reconfigure`, then `plan -out=tfplan`, persists the plan, and `apply tfplan` after the appropriate approval gate.

**Tech Stack:** CircleCI (workflows + approvals + contexts), Terraform (~>1.3), Databricks Terraform Provider (`databricks/databricks`), AWS S3 backend + DynamoDB locking, internal Docker image executor.

---

## Assumptions / placeholders to fill in

- **Internal executor image:** `<INTERNAL_DOCKER_IMAGE>:<TAG>` (must include `bash`, `terraform`, and optionally `awscli` + `jq`).
- **Terraform backend bucket:** `<TF_STATE_BUCKET>`
- **Terraform lock table:** `<TF_LOCK_TABLE>`
- **AWS region for backend:** `<TF_BACKEND_REGION>`
- **Databricks creds per env** are provided via CircleCI contexts:
  - `DATABRICKS_AUTH_TYPE=oauth-m2m`
  - `DATABRICKS_CLIENT_ID`
  - `DATABRICKS_CLIENT_SECRET`
  - plus any AWS auth (OIDC/assume-role preferred) required for Terraform.

## State layout decision (no migration for dev)

- **dev state key (existing):** `us-west-1/databricks/terraform.tfstate`
- **qa state key (new):** `us-west-1/databricks/qa/terraform.tfstate`
- **prod state key (new):** `us-west-1/databricks/prod/terraform.tfstate`

---

### Task 1: Add backend config files for dev/qa/prod

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/backends/dev.hcl`
- Create: `infra/aws/dbx/databricks/us-west-1/backends/qa.hcl`
- Create: `infra/aws/dbx/databricks/us-west-1/backends/prod.hcl`

**Step 1: Create `dev.hcl` (keep existing key)**

```hcl
bucket         = "<TF_STATE_BUCKET>"
key            = "us-west-1/databricks/terraform.tfstate"
region         = "<TF_BACKEND_REGION>"
dynamodb_table = "<TF_LOCK_TABLE>"
encrypt        = true
```

**Step 2: Create `qa.hcl`**

```hcl
bucket         = "<TF_STATE_BUCKET>"
key            = "us-west-1/databricks/qa/terraform.tfstate"
region         = "<TF_BACKEND_REGION>"
dynamodb_table = "<TF_LOCK_TABLE>"
encrypt        = true
```

**Step 3: Create `prod.hcl`**

```hcl
bucket         = "<TF_STATE_BUCKET>"
key            = "us-west-1/databricks/prod/terraform.tfstate"
region         = "<TF_BACKEND_REGION>"
dynamodb_table = "<TF_LOCK_TABLE>"
encrypt        = true
```

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/backends
git commit -m "chore(ci): add s3 backend configs for dev qa prod"
```

---

### Task 2: Add per-environment tfvars scaffolding (workspace host/id, env flags, etc.)

**Files:**
- Create: `infra/aws/dbx/databricks/us-west-1/tfvars/dev.tfvars`
- Create: `infra/aws/dbx/databricks/us-west-1/tfvars/qa.tfvars`
- Create: `infra/aws/dbx/databricks/us-west-1/tfvars/prod.tfvars`

**Step 1: Create `dev.tfvars` (placeholder)**

```hcl
# dev workspace targeting
workspace_source        = "existing"
existing_workspace_host = "<DEV_WORKSPACE_HOST>"
existing_workspace_id   = "<DEV_WORKSPACE_ID>"

# if your root module uses an env selector
environment = "dev"
```

**Step 2: Create `qa.tfvars` (placeholder)**

```hcl
workspace_source        = "existing"
existing_workspace_host = "<QA_WORKSPACE_HOST>"
existing_workspace_id   = "<QA_WORKSPACE_ID>"

environment = "qa"
```

**Step 3: Create `prod.tfvars` (placeholder)**

```hcl
workspace_source        = "existing"
existing_workspace_host = "<PROD_WORKSPACE_HOST>"
existing_workspace_id   = "<PROD_WORKSPACE_ID>"

environment = "prod"
```

**Step 4: Commit**

```bash
git add infra/aws/dbx/databricks/us-west-1/tfvars
git commit -m "chore(ci): add dev qa prod tfvars scaffolding"
```

---

### Task 3: Add a small CI wrapper script to DRY Terraform init/plan/apply

**Files:**
- Create: `scripts/ci/terraform_env.sh`

**Step 1: Create `scripts/ci/terraform_env.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?env required: dev|qa|prod}"
ACTION="${2:?action required: fmt|validate|plan|apply}"

ROOT="infra/aws/dbx/databricks/us-west-1"
BACKEND_FILE="${ROOT}/backends/${ENVIRONMENT}.hcl"
TFVARS_FILE="${ROOT}/tfvars/${ENVIRONMENT}.tfvars"

export TF_IN_AUTOMATION=1
export TF_INPUT=0

terraform -chdir="${ROOT}" init -reconfigure -backend-config="${BACKEND_FILE}"

case "${ACTION}" in
  fmt)
    terraform -chdir="${ROOT}" fmt -check -recursive
    ;;
  validate)
    terraform -chdir="${ROOT}" validate
    ;;
  plan)
    terraform -chdir="${ROOT}" plan -var-file="${TFVARS_FILE}" -out="tfplan-${ENVIRONMENT}"
    ;;
  apply)
    terraform -chdir="${ROOT}" apply -auto-approve "tfplan-${ENVIRONMENT}"
    ;;
  *)
    echo "unknown action: ${ACTION}" >&2
    exit 2
    ;;
esac
```

**Step 2: Make it executable**

Run:
```bash
chmod +x scripts/ci/terraform_env.sh
```

Expected: `git status` shows executable bit change for `scripts/ci/terraform_env.sh`.

**Step 3: Commit**

```bash
git add scripts/ci/terraform_env.sh
git commit -m "chore(ci): add terraform helper script for env promotion"
```

---

### Task 4: Create CircleCI config skeleton with internal Docker executor

**Files:**
- Create: `.circleci/config.yml`

**Step 1: Add config with a reusable executor**

```yaml
version: 2.1

executors:
  internal_tf:
    docker:
      - image: <INTERNAL_DOCKER_IMAGE>:<TAG>

jobs:
  terraform_checks:
    executor: internal_tf
    steps:
      - checkout
      - run:
          name: Terraform fmt + validate
          command: |
            scripts/ci/terraform_env.sh dev fmt
            scripts/ci/terraform_env.sh dev validate

  terraform_plan:
    executor: internal_tf
    parameters:
      env:
        type: enum
        enum: ["dev", "qa", "prod"]
    steps:
      - checkout
      - run:
          name: Terraform plan (<< parameters.env >>)
          command: |
            scripts/ci/terraform_env.sh << parameters.env >> plan
      - persist_to_workspace:
          root: infra/aws/dbx/databricks/us-west-1
          paths:
            - tfplan-<< parameters.env >>

  terraform_apply:
    executor: internal_tf
    parameters:
      env:
        type: enum
        enum: ["dev", "qa", "prod"]
    steps:
      - checkout
      - attach_workspace:
          at: infra/aws/dbx/databricks/us-west-1
      - run:
          name: Terraform apply (<< parameters.env >>)
          command: |
            scripts/ci/terraform_env.sh << parameters.env >> apply

workflows:
  terraform_pr:
    jobs:
      - terraform_checks
      - terraform_plan:
          name: plan_dev
          env: dev
          requires: [terraform_checks]

  terraform_main_promote:
    jobs:
      - terraform_checks:
          filters:
            branches:
              only: main
      - terraform_plan:
          name: plan_dev_main
          env: dev
          requires: [terraform_checks]
          filters:
            branches:
              only: main
      - terraform_apply:
          name: apply_dev
          env: dev
          requires: [plan_dev_main]
          filters:
            branches:
              only: main
      - terraform_plan:
          name: plan_qa
          env: qa
          requires: [apply_dev]
          filters:
            branches:
              only: main
      - hold_apply_qa:
          type: approval
          requires: [plan_qa]
          filters:
            branches:
              only: main
      - terraform_apply:
          name: apply_qa
          env: qa
          requires: [hold_apply_qa]
          filters:
            branches:
              only: main
      - terraform_plan:
          name: plan_prod
          env: prod
          requires: [apply_qa]
          filters:
            branches:
              only: main
      - hold_apply_prod:
          type: approval
          requires: [plan_prod]
          filters:
            branches:
              only: main
      - terraform_apply:
          name: apply_prod
          env: prod
          requires: [hold_apply_prod]
          filters:
            branches:
              only: main
```

**Step 2: Commit**

```bash
git add .circleci/config.yml
git commit -m "ci(circleci): add terraform plan/apply promotion workflow dev qa prod"
```

---

### Task 5: Define CircleCI contexts and env vars (docs-only, no repo changes)

**Files:**
- (No code changes)

**Step 1: Create contexts**

Create (names are suggestions):
- `aws-dev`, `aws-qa`, `aws-prod`
- `databricks-dev`, `databricks-qa`, `databricks-prod`

Lock down `aws-prod` + `databricks-prod` to:
- `main` branch only
- restricted approver group

**Step 2: Populate required env vars**

Per Databricks context:
- `DATABRICKS_AUTH_TYPE=oauth-m2m`
- `DATABRICKS_CLIENT_ID=<...>`
- `DATABRICKS_CLIENT_SECRET=<...>`

Per AWS context (preferred: assume-role / OIDC; placeholders here):
- `AWS_REGION=<...>`
- `AWS_ACCESS_KEY_ID=<...>` / `AWS_SECRET_ACCESS_KEY=<...>` / `AWS_SESSION_TOKEN=<...>` **or** envs needed to assume a role

**Step 3: Update CircleCI config to attach contexts**

Add `context: [aws-<env>, databricks-<env>]` to the `plan_*` / `apply_*` jobs.

---

### Task 6: Verification (local + CI smoke)

**Files:**
- Verify: `.circleci/config.yml`
- Verify: `infra/aws/dbx/databricks/us-west-1/backends/*.hcl`
- Verify: `infra/aws/dbx/databricks/us-west-1/tfvars/*.tfvars`

**Step 1: Local Terraform sanity (dev only)**

Run:
```bash
terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive
terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate
```

Expected: validate succeeds.

**Step 2: CI smoke test**

Open a PR and confirm:
- `terraform_checks` runs
- `plan_dev` runs and uploads/persists `tfplan-dev`

Merge to `main` and confirm:
- dev applies automatically
- qa/prod are blocked by approval jobs

---

## Execution handoff

Plan complete and saved to `docs/plans/2026-03-02-circleci-terraform-dev-qa-prod-implementation.md`.

Two execution options:

1. **Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks.
2. **Parallel Session (separate)** — Open a new session with `superpowers:executing-plans` and execute task-by-task.

Which approach?

