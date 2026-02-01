
# Terraform Variables Definition

# This file contains all variable definitions for the secrets management
# infrastructure. Variables are organized by category for clarity.

# General Configuration
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "secrets-mgmt"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

# -----------------------------------------------------------------------------
# AWS Region Configuration
variable "aws_region" {
  description = "Primary AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Disaster recovery AWS region"
  type        = string
  default     = "us-west-2"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# -----------------------------------------------------------------------------
# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS workers)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet internet access"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost saving for non-prod)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# EKS Configuration
variable "enable_eks" {
  description = "Enable EKS cluster deployment"
  type        = bool
  default     = true
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.34"  # Latest stable as of Jan 2026
}

variable "eks_node_instance_types" {
  description = "Instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 5
}

variable "eks_node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 50
}

# -----------------------------------------------------------------------------
# Database Configuration
variable "enable_rds" {
  description = "Enable RDS PostgreSQL deployment"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"  # Use larger for production
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for RDS"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "17.7"  # Latest stable as of Jan 2026 (18.x is preview)
}

variable "db_name" {
  description = "Name of the default database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false  # Enable for production
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for RDS"
  type        = bool
  default     = false  # Enable for production
}

variable "db_backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Secrets Management Configuration
variable "enable_parameter_store" {
  description = "Enable SSM Parameter Store scenario"
  type        = bool
  default     = true
}

variable "enable_secrets_manager" {
  description = "Enable AWS Secrets Manager scenario"
  type        = bool
  default     = true
}

variable "enable_vault" {
  description = "Enable HashiCorp Vault scenario"
  type        = bool
  default     = true
}

variable "secrets_rotation_days" {
  description = "Number of days between automatic secret rotation"
  type        = number
  default     = 30

  validation {
    condition     = var.secrets_rotation_days >= 1 && var.secrets_rotation_days <= 365
    error_message = "Rotation days must be between 1 and 365."
  }
}

# -----------------------------------------------------------------------------
# HashiCorp Vault Configuration
variable "vault_namespace" {
  description = "Kubernetes namespace for Vault"
  type        = string
  default     = "vault"
}

variable "vault_ha_enabled" {
  description = "Enable Vault HA mode"
  type        = bool
  default     = false  # Enable for production
}

variable "vault_replicas" {
  description = "Number of Vault replicas (for HA mode)"
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Prometheus/Grafana monitoring stack"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for EKS"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
