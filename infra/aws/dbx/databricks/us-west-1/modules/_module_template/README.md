# Databricks Terraform Module Template

This folder is a starter layout for new modules under `infra/aws/dbx/databricks/us-west-1/modules/`.

Workflow (optimized for low agent context):

1. Fill `SPEC.md` with the user-facing intent (what the module must do).
2. As you consult docs, write only durable facts to `FACTS.md` (no large paste).
   - Preferred sources: Terraform Registry provider docs and Context7 snippets.
3. Encode decisions in Terraform (`variables.tf`, `main.tf`, `outputs.tf`) and delete stale notes.
