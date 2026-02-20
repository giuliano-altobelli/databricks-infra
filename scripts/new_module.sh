#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/new_module.sh <relative-module-path>

Examples:
  scripts/new_module.sh databricks_workspace/my_feature
  scripts/new_module.sh databricks_account/my_account_feature

This copies the module template from:
  infra/aws/dbx/databricks/us-west-1/modules/_module_template

Into:
  infra/aws/dbx/databricks/us-west-1/modules/<relative-module-path>
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "" ]]; then
  usage
  exit 0
fi

target_rel="${1}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

modules_dir="${repo_root}/infra/aws/dbx/databricks/us-west-1/modules"
template_dir="${modules_dir}/_module_template"
dest_dir="${modules_dir}/${target_rel}"

if [[ ! -d "${template_dir}" ]]; then
  echo "error: template dir not found: ${template_dir}" >&2
  exit 1
fi

case "${target_rel}" in
  _module_template | _module_template/*)
    echo "error: target path must not be _module_template" >&2
    exit 1
    ;;
esac

if [[ -e "${dest_dir}" ]]; then
  echo "error: destination already exists: ${dest_dir}" >&2
  exit 1
fi

mkdir -p "$(dirname "${dest_dir}")"
cp -R "${template_dir}" "${dest_dir}"

echo "created module: ${dest_dir}"
echo "next:"
echo "  - Fill SPEC.md and FACTS.md"
echo "  - Use Terraform Registry / Context7 and record only facts in FACTS.md"
echo "  - Implement main.tf/variables.tf/outputs.tf"
