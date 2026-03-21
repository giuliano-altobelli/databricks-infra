Date: 2026-03-20

# Personal Infra Retirement Design

## Summary

Promote the existing `sandbox-infra` workspace to the canonical baseline for future work and add a one-time, explicit retirement workflow for the original `personal-infra` workspace.

The retirement workflow must preserve only:

- the shared Databricks account
- the shared Unity Catalog metastore
- the existing Okta SCIM-provisioned users

Everything else that was created solely for the first `personal-infra` workspace should be destroyed once it is safely attributed and represented in a dedicated retirement state.

## Scope

In scope:

- defining `sandbox-infra` as the new baseline workspace
- defining a one-time retirement workflow for the old `personal-infra` workspace
- adding an explicit Terraform state boundary for retirement work
- documenting the preserve set and destroy set for the teardown
- supporting retirement from either recovered historical state or reconstructed import state
- adding destroy-plan guardrails and post-destroy verification requirements

Out of scope:

- finalizing the long-term shared-versus-owned resource model for future workspaces
- refactoring the root into separate shared and per-workspace stacks
- reintroducing `workspace_source` or any other adopt-existing-workspace mode
- preserving `personal-infra` as a meaningful long-lived environment after teardown

## Context

The root at `infra/aws/dbx/databricks/us-west-1` is now create-only:

- the root always creates the Databricks workspace
- `workspace_host` and `workspace_id` derive from the managed workspace state
- the old existing-workspace inputs are gone

The repo also already has evidence of the new baseline direction:

- `sandbox.local.tfbackend` defines a dedicated sandbox state path
- `scenario2.sandbox-create-managed.tfvars` defines the sandbox create-only run shape
- `README.md` already documents a sandbox-first workflow

At the same time, the current local default state file is empty while the sandbox state file is populated. That means the first `personal-infra` workspace cannot be assumed to still have a clean, current, authoritative Terraform state boundary in the working directory.

This creates the core retirement problem:

1. the old workspace still needs to be destroyed safely
2. the repo must not guess about ownership when shared objects already exist
3. the create-only root should not regress just to support teardown

## Approved Design

### Architecture

`sandbox-infra` becomes the canonical baseline workspace for this repo.

`personal-infra` is treated as disposable bootstrap history. After teardown succeeds, the repo should no longer document, validate, or preserve it as an environment.

The create-only root remains create-only. The design does not reintroduce `workspace_source`, `existing_workspace_host`, `existing_workspace_id`, or any similar adoption path.

The preserved shared objects are limited to:

- the Databricks account
- the shared Unity Catalog metastore
- the existing Okta SCIM-provisioned users

Everything else created solely for `personal-infra`, across AWS, Databricks account-to-workspace assignment, workspace-level configuration, and first-workspace-specific Unity Catalog resources, is eligible for destruction.

### Retirement Model

The teardown must use a dedicated retirement state boundary and a two-phase workflow:

1. recover or reconstruct a `personal-infra` state snapshot that represents only first-workspace-owned resources
2. generate and review a destroy plan from that retirement state before any apply

The retirement workflow must not begin with a blind `terraform destroy` from the current working directory or the sandbox backend.

Accepted state reconstruction paths:

- recover a historical Terraform state snapshot if one exists and is trustworthy
- otherwise import live `personal-infra` resources into a dedicated retirement backend until the state accurately represents the destroy set

If a resource cannot be safely proven as first-workspace-owned, the workflow should exclude it from automated destruction and surface it for explicit manual adjudication.

### Workflow And Repo Changes

Add a dedicated retirement workflow to the repo beside the steady-state sandbox workflow.

Required repo changes:

- add a dedicated backend file for the retirement state, analogous to `sandbox.local.tfbackend`
- add a dedicated retirement runbook in the `us-west-1` docs
- define a written preserve-versus-destroy contract for the first workspace
- document both retirement entry paths:
  - recover from historical state
  - reconstruct by import when historical state is missing

After retirement is complete, active operator guidance should focus on the sandbox baseline and future create-only workspaces. The old `scenario1.premium-existing.tfvars` path should no longer be treated as meaningful active guidance.

### Guardrails And Verification

The retirement workflow must be conservative.

Required guardrails:

- never run destroy from the sandbox backend
- never run destroy from an unqualified default local state path
- always generate a destroy plan file before apply
- always require human review of that destroy plan
- reject the plan if it touches the shared metastore, SCIM users, or any resource clearly intended to be shared beyond the retired workspace

Required verification:

- inventory the live `personal-infra` AWS and Databricks resources before destroy
- compare the destroy plan against the written preserve-versus-destroy contract
- confirm the old workspace no longer exists after destroy
- confirm the shared metastore still exists after destroy
- confirm the sandbox workspace remains assigned to the shared metastore and usable after destroy

Objects that cannot be safely attributed should be left out of Terraform destroy and handled manually rather than forcing uncertain deletion through automation.

## Resulting Contract

After this work:

- `sandbox-infra` is the clean baseline for future workspace work
- `personal-infra` can be destroyed without regressing the root back to an adopt-existing model
- the repo preserves only the shared account, shared metastore, and SCIM users during retirement
- teardown safety depends on explicit state boundaries, explicit ownership rules, and reviewed destroy plans
