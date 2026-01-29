# =============================================================================
# Terraform Backend Configuration - Production
# =============================================================================
# Production MUST use remote state with locking.
# =============================================================================

bucket         = "secrets-mgmt-terraform-state-prod"
key            = "secrets-management/production/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "terraform-state-lock-prod"
