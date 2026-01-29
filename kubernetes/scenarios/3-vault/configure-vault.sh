# =============================================================================
# Vault Configuration for Dynamic Secrets
# =============================================================================
# This script configures HashiCorp Vault to provide dynamic database
# credentials for the Finance API application.
#
# Features demonstrated:
# 1. Kubernetes Authentication
# 2. Database Secret Engine (PostgreSQL)
# 3. Dynamic Credential Generation
# 4. Role-based Access Control
# 5. Audit Logging
# =============================================================================

#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------

VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
DB_HOST="${DB_HOST:-}"
DB_NAME="${DB_NAME:-appdb}"
DB_ADMIN_USER="${DB_ADMIN_USER:-dbadmin}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-}"
K8S_HOST="${K8S_HOST:-https://kubernetes.default.svc}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# 1. Enable Audit Device
# -----------------------------------------------------------------------------
# Audit logging is critical for compliance and security monitoring.
# All Vault operations will be logged.
# -----------------------------------------------------------------------------

log_info "Enabling audit device..."
vault audit enable file file_path=/vault/logs/audit.log || log_warn "Audit device may already be enabled"

# -----------------------------------------------------------------------------
# 2. Enable and Configure Kubernetes Authentication
# -----------------------------------------------------------------------------
# This allows pods to authenticate to Vault using their service account.
# -----------------------------------------------------------------------------

log_info "Configuring Kubernetes authentication..."

# Enable the Kubernetes auth method
vault auth enable kubernetes 2>/dev/null || log_warn "Kubernetes auth may already be enabled"

# Get the Kubernetes CA certificate
K8S_CA_CERT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | base64 | tr -d '\n')

# Configure the Kubernetes auth method
vault write auth/kubernetes/config \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    disable_local_ca_jwt="true"

log_info "Kubernetes auth configured successfully"

# -----------------------------------------------------------------------------
# 3. Enable and Configure KV Secrets Engine (v2)
# -----------------------------------------------------------------------------
# For storing static secrets like API keys.
# -----------------------------------------------------------------------------

log_info "Enabling KV secrets engine..."

vault secrets enable -path=secret kv-v2 2>/dev/null || log_warn "KV engine may already be enabled"

# Store API credentials
vault kv put secret/finance-api/api \
    api_key="$(openssl rand -hex 32)" \
    api_secret="$(openssl rand -hex 64)"

log_info "Static secrets stored in KV engine"

# -----------------------------------------------------------------------------
# 4. Enable and Configure Database Secrets Engine
# -----------------------------------------------------------------------------
# This is where the magic happens - dynamic secret generation.
# -----------------------------------------------------------------------------

log_info "Enabling database secrets engine..."

vault secrets enable database 2>/dev/null || log_warn "Database engine may already be enabled"

# Configure the PostgreSQL connection
vault write database/config/postgres \
    plugin_name="postgresql-database-plugin" \
    allowed_roles="finance-api-role" \
    connection_url="postgresql://{{username}}:{{password}}@${DB_HOST}:5432/${DB_NAME}?sslmode=require" \
    username="${DB_ADMIN_USER}" \
    password="${DB_ADMIN_PASSWORD}" \
    password_authentication="scram-sha-256"

log_info "Database connection configured"

# -----------------------------------------------------------------------------
# 5. Create Database Role for Dynamic Credentials
# -----------------------------------------------------------------------------
# This role defines the SQL statements used to create temporary users.
# Each generated user will have limited permissions and a short TTL.
# -----------------------------------------------------------------------------

log_info "Creating database role..."

vault write database/roles/finance-api-role \
    db_name="postgres" \
    creation_statements="
        CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
        GRANT CONNECT ON DATABASE ${DB_NAME} TO \"{{name}}\";
        GRANT USAGE ON SCHEMA public TO \"{{name}}\";
        GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO \"{{name}}\";
    " \
    revocation_statements="
        REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";
        REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM \"{{name}}\";
        REVOKE USAGE ON SCHEMA public FROM \"{{name}}\";
        REVOKE CONNECT ON DATABASE ${DB_NAME} FROM \"{{name}}\";
        DROP ROLE IF EXISTS \"{{name}}\";
    " \
    default_ttl="1h" \
    max_ttl="24h"

log_info "Database role 'finance-api-role' created with 1h TTL"

# -----------------------------------------------------------------------------
# 6. Create Vault Policy for the Application
# -----------------------------------------------------------------------------
# This policy defines what the Finance API can access in Vault.
# Follows the principle of least privilege.
# -----------------------------------------------------------------------------

log_info "Creating Vault policy..."

vault policy write finance-api - <<EOF
# Allow reading dynamic database credentials
path "database/creds/finance-api-role" {
  capabilities = ["read"]
}

# Allow reading static secrets
path "secret/data/finance-api/*" {
  capabilities = ["read"]
}

# Allow the token to look up its own properties
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow the token to renew itself
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

log_info "Policy 'finance-api' created"

# -----------------------------------------------------------------------------
# 7. Create Kubernetes Auth Role
# -----------------------------------------------------------------------------
# This binds the Kubernetes service account to the Vault policy.
# -----------------------------------------------------------------------------

log_info "Creating Kubernetes auth role..."

vault write auth/kubernetes/role/finance-api \
    bound_service_account_names="app-vault" \
    bound_service_account_namespaces="apps" \
    policies="finance-api" \
    token_ttl="1h" \
    token_max_ttl="24h" \
    token_policies="finance-api"

log_info "Kubernetes auth role 'finance-api' created"

# -----------------------------------------------------------------------------
# 8. Rotate the Database Root Password
# -----------------------------------------------------------------------------
# Security best practice: rotate the root password after initial setup.
# Vault will manage the root password from now on.
# -----------------------------------------------------------------------------

log_info "Rotating database root password..."
vault write -force database/rotate-root/postgres

log_info "Root password rotated. The original password is no longer valid."

# -----------------------------------------------------------------------------
# 9. Test the Configuration
# -----------------------------------------------------------------------------

log_info "Testing dynamic credential generation..."

# Generate a test credential
TEST_CREDS=$(vault read -format=json database/creds/finance-api-role)
TEST_USER=$(echo $TEST_CREDS | jq -r '.data.username')
TEST_LEASE=$(echo $TEST_CREDS | jq -r '.lease_id')

log_info "Successfully generated test credentials for user: ${TEST_USER}"

# Revoke the test credential
vault lease revoke ${TEST_LEASE}
log_info "Test credentials revoked"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "  Vault Configuration Complete!"
echo "=============================================="
echo ""
echo "  Kubernetes Auth Role: finance-api"
echo "  Database Role:        finance-api-role"
echo "  Credential TTL:       1 hour"
echo "  Max TTL:              24 hours"
echo ""
echo "  Service Account:      app-vault"
echo "  Namespace:            apps"
echo ""
echo "=============================================="
