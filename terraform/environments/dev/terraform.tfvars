# =============================================================================
# Development Environment Configuration
# =============================================================================
# This file contains Terraform variable values for the development environment.
# Optimized for cost savings while maintaining functionality.
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

project_name = "secrets-mgmt"
environment  = "dev"

# -----------------------------------------------------------------------------
# AWS Region Configuration
# -----------------------------------------------------------------------------

aws_region = "us-east-1"
dr_region  = "us-west-2"

availability_zones = [
  "us-east-1a",
  "us-east-1b"
]

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------

vpc_cidr = "10.0.0.0/16"

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]

private_subnet_cidrs = [
  "10.0.11.0/24",
  "10.0.12.0/24"
]

database_subnet_cidrs = [
  "10.0.21.0/24",
  "10.0.22.0/24"
]

# Cost optimization: Use single NAT Gateway for dev
enable_nat_gateway = true
single_nat_gateway = true

# -----------------------------------------------------------------------------
# EKS Configuration
# -----------------------------------------------------------------------------

enable_eks = true

eks_cluster_version = "1.31"

# Cost optimization: Use smaller instances for dev
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size   = 2
eks_node_min_size       = 1
eks_node_max_size       = 4
eks_node_disk_size      = 30

# -----------------------------------------------------------------------------
# RDS Configuration
# -----------------------------------------------------------------------------

enable_rds = true

# Cost optimization: Use smallest instance for dev
db_instance_class      = "db.t3.micro"
db_allocated_storage   = 20
db_engine_version      = "16.4"
db_name                = "appdb"
db_username            = "dbadmin"

# Dev settings: No HA, easier deletion
db_multi_az              = false
db_deletion_protection   = false
db_backup_retention_period = 1

# -----------------------------------------------------------------------------
# Secrets Management Scenarios
# -----------------------------------------------------------------------------

# Enable all three scenarios for comparison
enable_parameter_store = true
enable_secrets_manager = true
enable_vault           = true

# Rotation interval
secrets_rotation_days = 30

# -----------------------------------------------------------------------------
# HashiCorp Vault Configuration
# -----------------------------------------------------------------------------

vault_namespace = "vault"

# Dev mode: Single replica (not HA)
vault_ha_enabled = false
vault_replicas   = 1

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------

enable_monitoring      = true
enable_cloudwatch_logs = true
log_retention_days     = 7

# -----------------------------------------------------------------------------
# Additional Tags
# -----------------------------------------------------------------------------

additional_tags = {
  CostCenter  = "development"
  Team        = "devops"
  Application = "secrets-management-demo"
}
