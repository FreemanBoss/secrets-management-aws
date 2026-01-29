# =============================================================================
# Terraform Backend Configuration - Development
# =============================================================================
# For development, we use local state.
# For production, uncomment the S3 backend below.
# =============================================================================

# Using local backend for development
# State is stored in terraform.tfstate locally

# Uncomment below for remote state (recommended for team collaboration)
# bucket         = "your-terraform-state-bucket-dev"
# key            = "secrets-management/dev/terraform.tfstate"
# region         = "us-east-1"
# encrypt        = true
# dynamodb_table = "terraform-state-lock-dev"
