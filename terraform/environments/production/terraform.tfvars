# =============================================================================
# Production Environment Configuration
# =============================================================================
# This file contains Terraform variable values for the production environment.
# Optimized for high availability, security, and compliance.
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

project_name = "secrets-mgmt"
environment  = "production"

# -----------------------------------------------------------------------------
# AWS Region Configuration
# -----------------------------------------------------------------------------

aws_region = "us-east-1"
dr_region  = "us-west-2"

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
]

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24",
  "10.0.3.0/24"
]

private_subnet_cidrs = [
  "10.0.11.0/24",
  "10.0.12.0/24",
  "10.0.13.0/24"
]

database_subnet_cidrs = [
  "10.0.21.0/24",
  "10.0.22.0/24",
  "10.0.23.0/24"
]

# Production: NAT Gateway per AZ for HA
enable_nat_gateway = true
single_nat_gateway = false

# -----------------------------------------------------------------------------
# EKS Configuration
# -----------------------------------------------------------------------------

enable_eks = true

eks_cluster_version = "1.31"

# Production: Use larger instances with capacity
eks_node_instance_types = ["m6i.large", "m6i.xlarge"]
eks_node_desired_size   = 3
eks_node_min_size       = 3
eks_node_max_size       = 10
eks_node_disk_size      = 100

# -----------------------------------------------------------------------------
# RDS Configuration
# -----------------------------------------------------------------------------

enable_rds = true

# Production: Use appropriate instance class
db_instance_class      = "db.r6g.large"
db_allocated_storage   = 100
db_engine_version      = "16.4"
db_name                = "appdb"
db_username            = "dbadmin"

# Production settings: HA and protection enabled
db_multi_az              = true
db_deletion_protection   = true
db_backup_retention_period = 30

# -----------------------------------------------------------------------------
# Secrets Management Scenarios
# -----------------------------------------------------------------------------

# Enable all three scenarios for comparison
enable_parameter_store = true
enable_secrets_manager = true
enable_vault           = true

# More frequent rotation for production
secrets_rotation_days = 7

# -----------------------------------------------------------------------------
# HashiCorp Vault Configuration
# -----------------------------------------------------------------------------

vault_namespace = "vault"

# Production: HA mode with 3 replicas
vault_ha_enabled = true
vault_replicas   = 3

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------

enable_monitoring      = true
enable_cloudwatch_logs = true
log_retention_days     = 90

# -----------------------------------------------------------------------------
# Additional Tags
# -----------------------------------------------------------------------------

additional_tags = {
  CostCenter   = "production"
  Team         = "platform"
  Application  = "secrets-management"
  Compliance   = "soc2"
  DataClass    = "confidential"
}
