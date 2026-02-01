#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ENVIRONMENT="${1:-dev}"
ACTION="${2:-plan}"

cd "$PROJECT_ROOT/terraform"

case "$ACTION" in
  init)
    terraform init
    ;;
  plan)
    terraform plan -var-file="environments/$ENVIRONMENT/terraform.tfvars"
    ;;
  apply)
    terraform apply -var-file="environments/$ENVIRONMENT/terraform.tfvars" -auto-approve
    ;;
  destroy)
    terraform destroy -var-file="environments/$ENVIRONMENT/terraform.tfvars" -auto-approve
    ;;
  *)
    echo "Usage: $0 [dev|production] [init|plan|apply|destroy]"
    exit 1
    ;;
esac
