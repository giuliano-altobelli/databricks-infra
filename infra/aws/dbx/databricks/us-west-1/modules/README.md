# Module Authoring (Low-Context Workflow)

This folder contains Terraform modules used by `infra/aws/dbx/databricks/us-west-1/`.

## Create A New Module

- Create a module directory by copying the template:
  - `scripts/new_module.sh databricks_workspace/<module_name>`
  - `scripts/new_module.sh databricks_account/<module_name>`
- Edit the new module:
  - `SPEC.md`: what the module must do (contract).
  - `FACTS.md`: tiny “docs → facts” ledger (no large pastes).
  - `variables.tf`, `main.tf`, `outputs.tf`: encode decisions in Terraform.

## Docs Retrieval Rules

- Fetch docs only for the resource/argument you are implementing next.
- Reduce each retrieval to short facts with a source pointer (Terraform Registry page, Context7 query topic, etc.).
- Delete or overwrite stale notes once the code is the source of truth.
