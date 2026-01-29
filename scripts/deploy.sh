#!/bin/bash
# =============================================================================
# Infrastructure Deployment Script
# =============================================================================
# This script deploys the complete secrets management infrastructure.
# It handles Terraform provisioning, Helm installations, and configuration.
#
# Usage:
#   ./deploy.sh [environment] [action]
#
# Examples:
#   ./deploy.sh dev plan
#   ./deploy.sh dev apply
#   ./deploy.sh production apply
#   ./deploy.sh dev destroy
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
K8S_DIR="${PROJECT_ROOT}/kubernetes"

# Default values
ENVIRONMENT="${1:-dev}"
ACTION="${2:-plan}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws-cli")
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        log_info "Run: aws configure"
        exit 1
    fi
    
    # Display AWS identity
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
    log_info "AWS Account: ${AWS_ACCOUNT}"
    log_info "AWS Identity: ${AWS_USER}"
    
    # Check tool versions
    log_info "Terraform version: $(terraform version -json | jq -r '.terraform_version')"
    log_info "AWS CLI version: $(aws --version | cut -d' ' -f1)"
    log_info "kubectl version: $(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion')"
    log_info "Helm version: $(helm version --short)"
    
    log_info "All prerequisites satisfied ✓"
}

# -----------------------------------------------------------------------------
# Terraform Functions
# -----------------------------------------------------------------------------

terraform_init() {
    log_section "Initializing Terraform"
    
    cd "${TERRAFORM_DIR}"
    
    terraform init \
        -backend-config="environments/${ENVIRONMENT}/backend.tfvars" \
        -upgrade
    
    log_info "Terraform initialized ✓"
}

terraform_plan() {
    log_section "Planning Infrastructure Changes"
    
    cd "${TERRAFORM_DIR}"
    
    terraform plan \
        -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
        -out="tfplan-${ENVIRONMENT}"
    
    log_info "Plan saved to tfplan-${ENVIRONMENT}"
}

terraform_apply() {
    log_section "Applying Infrastructure Changes"
    
    cd "${TERRAFORM_DIR}"
    
    if [ -f "tfplan-${ENVIRONMENT}" ]; then
        terraform apply "tfplan-${ENVIRONMENT}"
    else
        terraform apply \
            -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
            -auto-approve
    fi
    
    log_info "Infrastructure deployed ✓"
}

terraform_destroy() {
    log_section "Destroying Infrastructure"
    
    log_warn "This will destroy ALL resources in ${ENVIRONMENT}!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Destruction cancelled"
        exit 0
    fi
    
    cd "${TERRAFORM_DIR}"
    
    terraform destroy \
        -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
        -auto-approve
    
    log_info "Infrastructure destroyed ✓"
}

terraform_output() {
    cd "${TERRAFORM_DIR}"
    terraform output -json
}

# -----------------------------------------------------------------------------
# EKS Configuration
# -----------------------------------------------------------------------------

configure_kubectl() {
    log_section "Configuring kubectl"
    
    local cluster_name=$(terraform_output | jq -r '.eks_cluster_name.value')
    local region=$(terraform_output | jq -r '.aws_region.value // "us-east-1"')
    
    if [ "$cluster_name" == "null" ] || [ -z "$cluster_name" ]; then
        log_warn "EKS cluster not found, skipping kubectl configuration"
        return
    fi
    
    aws eks update-kubeconfig \
        --region "${region}" \
        --name "${cluster_name}"
    
    # Verify connection
    kubectl cluster-info
    
    log_info "kubectl configured ✓"
}

# -----------------------------------------------------------------------------
# Helm Installations
# -----------------------------------------------------------------------------

install_helm_charts() {
    log_section "Installing Helm Charts"
    
    # Add required Helm repositories
    log_info "Adding Helm repositories..."
    helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
    helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update
    
    log_info "Helm repositories updated ✓"
    
    # Install Secrets Store CSI Driver
    log_info "Installing Secrets Store CSI Driver..."
    helm upgrade --install secrets-store-csi-driver \
        secrets-store-csi-driver/secrets-store-csi-driver \
        --namespace kube-system \
        --values "${K8S_DIR}/helm-values/secrets-store-csi-driver.yaml" \
        --wait
    
    # Install AWS Provider for CSI Driver
    log_info "Installing AWS Provider for CSI Driver..."
    helm upgrade --install secrets-store-csi-driver-provider-aws \
        aws-secrets-manager/secrets-store-csi-driver-provider-aws \
        --namespace kube-system \
        --values "${K8S_DIR}/helm-values/secrets-store-csi-driver-provider-aws.yaml" \
        --wait
    
    # Install External Secrets Operator
    log_info "Installing External Secrets Operator..."
    helm upgrade --install external-secrets \
        external-secrets/external-secrets \
        --namespace external-secrets \
        --create-namespace \
        --values "${K8S_DIR}/helm-values/external-secrets.yaml" \
        --wait
    
    # Install HashiCorp Vault
    log_info "Installing HashiCorp Vault..."
    kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
    
    helm upgrade --install vault \
        hashicorp/vault \
        --namespace vault \
        --values "${K8S_DIR}/helm-values/vault.yaml" \
        --wait
    
    log_info "All Helm charts installed ✓"
}

# -----------------------------------------------------------------------------
# Application Deployment
# -----------------------------------------------------------------------------

deploy_application() {
    log_section "Deploying Application"
    
    # Create namespace and base resources
    kubectl apply -f "${K8S_DIR}/base/"
    
    # Get Terraform outputs for variable substitution
    local outputs=$(terraform_output)
    local db_host=$(echo "$outputs" | jq -r '.rds_endpoint.value // ""' | cut -d':' -f1)
    local db_name=$(echo "$outputs" | jq -r '.rds_database_name.value // "appdb"')
    local db_username=$(echo "$outputs" | jq -r '.rds_master_username.value // "dbadmin"')
    local project_name=$(echo "$outputs" | jq -r '.project_name.value // "secrets-mgmt-dev"')
    local aws_region=$(echo "$outputs" | jq -r '.aws_region.value // "us-east-1"')
    local param_store_role=$(echo "$outputs" | jq -r '.parameter_store_role_arn.value // ""')
    local secrets_mgr_role=$(echo "$outputs" | jq -r '.secrets_manager_role_arn.value // ""')
    local ecr_registry="${AWS_ACCOUNT}.dkr.ecr.${aws_region}.amazonaws.com"
    
    # Build and push Docker image
    log_info "Building and pushing Docker image..."
    aws ecr get-login-password --region "${aws_region}" | docker login --username AWS --password-stdin "${ecr_registry}"
    
    docker build -t "${ecr_registry}/finance-api:1.0.0" "${PROJECT_ROOT}/app/"
    docker push "${ecr_registry}/finance-api:1.0.0"
    
    # Deploy scenarios with variable substitution
    for scenario_dir in "${K8S_DIR}/scenarios/"*/; do
        scenario=$(basename "$scenario_dir")
        log_info "Deploying scenario: ${scenario}..."
        
        # Use envsubst for variable replacement
        export DB_HOST="${db_host}"
        export DB_NAME="${db_name}"
        export DB_USERNAME="${db_username}"
        export PROJECT_NAME="${project_name}"
        export AWS_REGION="${aws_region}"
        export PARAMETER_STORE_ROLE_ARN="${param_store_role}"
        export SECRETS_MANAGER_ROLE_ARN="${secrets_mgr_role}"
        export ECR_REGISTRY="${ecr_registry}"
        
        for yaml_file in "${scenario_dir}"*.yaml; do
            if [ -f "$yaml_file" ]; then
                envsubst < "$yaml_file" | kubectl apply -f -
            fi
        done
    done
    
    log_info "Application deployed ✓"
}

# -----------------------------------------------------------------------------
# Status Check
# -----------------------------------------------------------------------------

check_status() {
    log_section "Checking Deployment Status"
    
    echo "=== Namespaces ==="
    kubectl get namespaces
    
    echo ""
    echo "=== Pods in apps namespace ==="
    kubectl get pods -n apps -o wide
    
    echo ""
    echo "=== Services in apps namespace ==="
    kubectl get svc -n apps
    
    echo ""
    echo "=== External Secrets Status ==="
    kubectl get externalsecrets -n apps
    
    echo ""
    echo "=== Vault Status ==="
    kubectl get pods -n vault
    
    echo ""
    echo "=== Secrets Store CSI Driver ==="
    kubectl get pods -n kube-system -l app=secrets-store-csi-driver
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

main() {
    log_section "Secrets Management Infrastructure Deployment"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Action: ${ACTION}"
    
    check_prerequisites
    
    case "${ACTION}" in
        init)
            terraform_init
            ;;
        plan)
            terraform_init
            terraform_plan
            ;;
        apply)
            terraform_init
            terraform_apply
            configure_kubectl
            install_helm_charts
            deploy_application
            check_status
            ;;
        destroy)
            terraform_init
            terraform_destroy
            ;;
        status)
            configure_kubectl
            check_status
            ;;
        *)
            log_error "Unknown action: ${ACTION}"
            log_info "Valid actions: init, plan, apply, destroy, status"
            exit 1
            ;;
    esac
    
    log_section "Deployment Complete!"
}

# Run main function
main
