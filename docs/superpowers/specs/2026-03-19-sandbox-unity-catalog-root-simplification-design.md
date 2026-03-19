Date: 2026-03-19

# Sandbox Unity Catalog Root Simplification Design

## Summary

Specialize the `sandbox` branch root stack at `infra/aws/dbx/databricks/us-west-1` so it no longer models Unity Catalog as a choice between reusing an existing catalog and creating a new isolated catalog.

For this branch, the only supported Unity Catalog behavior is:

- bootstrap the sandbox workspace and metastore assignment first
- create a sandbox workspace
- attach that workspace to the shared existing metastore
- create only sandbox-owned catalogs declared in `catalogs_config.tf`
- fail if any configured sandbox catalog already exists in the same metastore

This removes the misleading `uc_catalog_mode` and `uc_existing_catalog_name` interface from the sandbox workflow and makes the governed catalog set the only Unity Catalog source of truth.

## Scope

In scope:

- remove `uc_catalog_mode` and `uc_existing_catalog_name` from the sandbox branch root interface
- remove sandbox usage of the legacy single-catalog root path in `main.tf`
- make `catalogs_config.tf` the only catalog-definition entrypoint for the sandbox branch
- add a live metastore collision check for configured sandbox catalog names
- update sandbox validations, docs, and outputs to match the sandbox-only contract

Out of scope:

- preserving generic existing-catalog behavior in the `sandbox` branch
- introducing a new multi-environment abstraction
- changing the governed catalog module contract beyond what is needed for root-level validation
- adopting pre-existing catalogs into Terraform state

## Context

The sandbox branch already establishes a stricter contract than the current root interface suggests:

- `sandbox_validations.tf` already requires a create-workspace sandbox run shape
- `catalogs_config.tf` already defines explicit sandbox-prefixed governed catalogs such as `sandbox_personal`
- the sandbox README already says the run must reject attempts to use `uc_catalog_mode = "existing"`

The remaining problem is that the root still exposes and consumes generic Unity Catalog mode variables:

- `variables.tf` defines `uc_catalog_mode` and `uc_existing_catalog_name`
- `locals.tf` derives `effective_uc_catalog_mode` and `catalog_name` from those variables
- `main.tf` still has a legacy single-catalog module call gated by `effective_uc_catalog_mode`
- `catalogs_config.tf` still contains overlap checks that reference the removed existing-catalog concept

That leaves the sandbox branch with two competing models:

1. sandbox-only governed catalog creation
2. legacy root-level mode switching for a single catalog

The design removes the second model from the sandbox branch.

## Approved Design

### Root interface and control flow

The sandbox branch root becomes sandbox-specific for Unity Catalog.

Changes:

- remove `uc_catalog_mode` and `uc_existing_catalog_name` from `variables.tf`
- remove both settings from `scenario2.sandbox-create-managed.tfvars`
- stop deriving `effective_uc_catalog_mode` in `locals.tf`
- stop using the legacy `module "unity_catalog_catalog_creation"` branch in `main.tf`
- make the governed catalog fan-out in `catalogs_config.tf` the only catalog creation path

The only supported sandbox flow is:

1. bootstrap the sandbox workspace
2. assign the shared existing metastore
3. rerun Terraform once the workspace ID and host are present in state
4. validate the configured sandbox catalog names against the metastore during plan
5. create the sandbox-owned governed catalogs from `catalogs_config.tf`
6. create downstream schemas, volumes, and related sandbox-owned resources from those governed catalogs

This makes the branch contract explicit: the sandbox branch shares the metastore, but it does not share catalogs.

### Governed catalog source of truth

`catalogs_config.tf` is the authoritative source of sandbox catalog intent.

Rules:

- every sandbox-managed catalog must come from `local.governed_catalog_domains`
- sandbox catalogs must continue to use explicit `sandbox_`-prefixed names
- the static uniqueness checks for configured catalog names and AWS-safe suffixes remain in place
- checks that depend on `uc_existing_catalog_name` or `effective_uc_catalog_mode` are removed

The branch must not carry a second catalog-definition path in root locals or tfvars.

### Live metastore collision check

The root adds a live Databricks read that checks whether any configured sandbox catalog name already exists in the assigned metastore.

Behavior:

- the check runs after bootstrap has created the workspace and metastore assignment, and before governed catalog creation
- it inspects the configured sandbox catalog names from `catalogs_config.tf`
- if none of those names already exist, the run proceeds
- if one or more names already exist in the metastore, the run fails before catalog creation

Failure messaging must clearly state:

- which catalog names already exist
- that the sandbox branch only creates new sandbox-owned catalogs
- that pre-existing catalogs are not adopted into Terraform state in this branch

This replaces the old overlap model of "do not collide with `uc_existing_catalog_name`" with the actual sandbox safety requirement: "do not collide with any existing metastore catalog of the same name."

### Compatibility handling for single-catalog references

The governed catalog set becomes the authoritative root output.

However, the root still has a small amount of single-catalog compatibility shape:

- `local.catalog_name`
- root `output "catalog_name"`
- the disabled-by-default security-analysis module input that references `local.catalog_name`

To avoid an unrelated break while removing the legacy mode-switching path, retain `catalog_name` only as a compatibility alias to the sandbox personal catalog when present. The authoritative contract remains `output "catalogs"`.

Compatibility rule:

- `output "catalogs"` is the real sandbox catalog interface
- `output "catalog_name"` remains only as a temporary alias for the personal catalog, or `null` if that catalog is disabled

This keeps the root coherent during the simplification without preserving the old existing-catalog behavior.

## Validation And Verification

### Root validations

Update `sandbox_validations.tf` so the sandbox run shape asserts:

- `resource_prefix == "sandbox-infra"`
- `pricing_tier == "PREMIUM"`
- `workspace_source == "create"`
- `network_configuration == "managed"`
- `metastore_exists == true`
- `existing_workspace_host == null`
- `existing_workspace_id == null`

The validation must no longer reference `uc_catalog_mode`.

### Documentation

Update the root README to say:

- the sandbox branch never adopts existing Unity Catalog catalogs
- the sandbox branch only creates new catalogs defined in `catalogs_config.tf`
- if a configured sandbox catalog already exists in the shared metastore, the run must fail and be resolved explicitly

### Verification commands

Implementation verification should include:

- `terraform -chdir=infra/aws/dbx/databricks/us-west-1 fmt -recursive`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 validate`
- `DATABRICKS_AUTH_TYPE=oauth-m2m direnv exec infra/aws/dbx/databricks/us-west-1 terraform -chdir=infra/aws/dbx/databricks/us-west-1 plan -var-file=scenario2.sandbox-create-managed.tfvars`

Behavioral verification should include one collision case:

- run the documented bootstrap step first so the workspace exists in Terraform state
- then configure a sandbox catalog name that already exists in the assigned metastore and confirm `plan` fails before catalog creation with the expected collision error

### Staged sandbox workflow

The sandbox branch uses a deliberate two-stage operator workflow:

1. bootstrap apply:
   - create the workspace
   - assign the metastore
   - establish the state-backed workspace ID and host
2. full sandbox plan/apply:
   - run the native metastore catalog collision check during plan
   - create governed catalogs and downstream sandbox-owned resources only if the check is clear

The workflow must keep `workspace_id` derived from Terraform state. The design explicitly rejects hardcoding `workspace_id` in tfvars or other checked-in config because that would make destroy/recreate cycles brittle and operator-dependent.

## Resulting Contract

After this change, the `sandbox` branch will have one Unity Catalog contract only:

- shared metastore
- sandbox-owned catalogs
- no existing-catalog adoption
- failure on name collision in the metastore

That contract matches the actual purpose of the branch and removes the root-level ambiguity that currently makes the sandbox tfvars misleading.
