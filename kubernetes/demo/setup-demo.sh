#!/bin/bash
# =============================================================================
# Demo Application Setup and Verification Script
# =============================================================================
# This script sets up the demo applications and verifies each secrets
# management approach is working correctly.
# =============================================================================

set -e

NAMESPACE="demo"
VAULT_NAMESPACE="vault"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Step 1: Pre-requisite Checks
# =============================================================================
log_info "Checking prerequisites..."

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

# Check EKS connectivity
if ! kubectl get nodes &> /dev/null; then
    log_error "Cannot connect to EKS cluster. Please configure kubeconfig."
    exit 1
fi

log_success "Prerequisites check passed"

# =============================================================================
# Step 2: Create Vault Policy and Role for Demo Apps
# =============================================================================
log_info "Configuring Vault for demo applications..."

# Get Vault pod name
VAULT_POD=$(kubectl get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$VAULT_POD" ]; then
    log_warn "Vault pod not found. Skipping Vault configuration."
else
    # Create policy for demo apps
    log_info "Creating Vault policy for demo apps..."
    kubectl exec -n $VAULT_NAMESPACE $VAULT_POD -- vault policy write demo-app - <<EOF
# Allow read access to all demo secrets
path "secret/data/database/*" {
  capabilities = ["read", "list"]
}
path "secret/data/api/*" {
  capabilities = ["read", "list"]
}
path "secret/data/app/*" {
  capabilities = ["read", "list"]
}
EOF

    # Create Kubernetes auth role for demo apps
    log_info "Creating Vault Kubernetes auth role..."
    kubectl exec -n $VAULT_NAMESPACE $VAULT_POD -- vault write auth/kubernetes/role/demo-app \
        bound_service_account_names=vault-demo-app \
        bound_service_account_namespaces=$NAMESPACE \
        policies=demo-app \
        ttl=1h

    log_success "Vault configuration completed"
fi

# =============================================================================
# Step 3: Apply Demo Manifests
# =============================================================================
log_info "Applying demo manifests..."

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Apply manifests in order
kubectl apply -f $SCRIPT_DIR/01-service-account.yaml
kubectl apply -f $SCRIPT_DIR/02-external-secrets.yaml
kubectl apply -f $SCRIPT_DIR/03-secrets-store-csi.yaml
kubectl apply -f $SCRIPT_DIR/04-vault-integration.yaml
kubectl apply -f $SCRIPT_DIR/05-demo-deployments.yaml

log_success "Demo manifests applied"

# =============================================================================
# Step 4: Wait for Pods to be Ready
# =============================================================================
log_info "Waiting for demo pods to be ready..."

# Wait for External Secrets to sync
log_info "Waiting for External Secrets to sync..."
sleep 10

# Check if secrets were created
if kubectl get secret database-credentials -n $NAMESPACE &> /dev/null; then
    log_success "External Secret 'database-credentials' synced"
else
    log_warn "External Secret 'database-credentials' not yet synced"
fi

if kubectl get secret api-credentials -n $NAMESPACE &> /dev/null; then
    log_success "External Secret 'api-credentials' synced"
else
    log_warn "External Secret 'api-credentials' not yet synced"
fi

# Wait for deployments
log_info "Waiting for deployments to be ready (timeout: 120s)..."
kubectl wait --for=condition=available --timeout=120s deployment/demo-external-secrets -n $NAMESPACE 2>/dev/null || log_warn "demo-external-secrets not ready"
kubectl wait --for=condition=available --timeout=120s deployment/demo-csi-parameter-store -n $NAMESPACE 2>/dev/null || log_warn "demo-csi-parameter-store not ready"
kubectl wait --for=condition=available --timeout=120s deployment/demo-csi-secrets-manager -n $NAMESPACE 2>/dev/null || log_warn "demo-csi-secrets-manager not ready"
kubectl wait --for=condition=available --timeout=120s deployment/demo-vault-injector -n $NAMESPACE 2>/dev/null || log_warn "demo-vault-injector not ready"

# =============================================================================
# Step 5: Verify Each Approach
# =============================================================================
echo ""
echo "============================================="
echo "  Verification Results"
echo "============================================="

# Check External Secrets
log_info "Checking External Secrets approach..."
ESO_POD=$(kubectl get pods -n $NAMESPACE -l app=demo-external-secrets -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$ESO_POD" ]; then
    echo ""
    kubectl logs $ESO_POD -n $NAMESPACE 2>/dev/null | head -20
    echo ""
fi

# Check CSI Parameter Store
log_info "Checking CSI Driver (Parameter Store) approach..."
CSI_PS_POD=$(kubectl get pods -n $NAMESPACE -l app=demo-csi-parameter-store -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CSI_PS_POD" ]; then
    echo ""
    kubectl logs $CSI_PS_POD -n $NAMESPACE 2>/dev/null | head -20
    echo ""
fi

# Check CSI Secrets Manager
log_info "Checking CSI Driver (Secrets Manager) approach..."
CSI_SM_POD=$(kubectl get pods -n $NAMESPACE -l app=demo-csi-secrets-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CSI_SM_POD" ]; then
    echo ""
    kubectl logs $CSI_SM_POD -n $NAMESPACE 2>/dev/null | head -20
    echo ""
fi

# Check Vault Injector
log_info "Checking Vault Agent Injector approach..."
VAULT_INJ_POD=$(kubectl get pods -n $NAMESPACE -l app=demo-vault-injector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$VAULT_INJ_POD" ]; then
    echo ""
    kubectl logs $VAULT_INJ_POD -c demo-app -n $NAMESPACE 2>/dev/null | head -25
    echo ""
fi

# =============================================================================
# Step 6: Summary
# =============================================================================
echo ""
echo "============================================="
echo "  Demo Pods Status"
echo "============================================="
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "============================================="
echo "  Secrets Created"
echo "============================================="
kubectl get secrets -n $NAMESPACE

echo ""
log_success "Demo setup complete!"
echo ""
echo "To view logs for each approach:"
echo "  kubectl logs -n $NAMESPACE -l secrets-provider=external-secrets"
echo "  kubectl logs -n $NAMESPACE -l secrets-provider=csi-driver"
echo "  kubectl logs -n $NAMESPACE -l secrets-provider=vault -c demo-app"
