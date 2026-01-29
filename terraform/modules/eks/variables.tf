# =============================================================================
# EKS Module Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

# Networking
variable "vpc_id" {
  description = "VPC ID where the cluster will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID of the RDS instance"
  type        = string
  default     = null
}

# Cluster Configuration
variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS API endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Node Group Configuration
variable "node_instance_types" {
  description = "List of instance types for the primary node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 5
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 50
}

variable "use_spot_instances" {
  description = "Use spot instances for the primary node group"
  type        = bool
  default     = false
}

# Vault Node Group
variable "enable_vault_nodes" {
  description = "Create a dedicated node group for HashiCorp Vault"
  type        = bool
  default     = false
}

# Logging
variable "enable_cluster_logging" {
  description = "Enable EKS cluster logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

# Encryption
variable "kms_key_arn" {
  description = "ARN of KMS key for EBS encryption"
  type        = string
  default     = null
}

# Access
variable "additional_admin_arns" {
  description = "List of IAM ARNs to grant cluster admin access"
  type        = list(string)
  default     = null
}

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
