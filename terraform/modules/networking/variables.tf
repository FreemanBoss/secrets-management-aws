# =============================================================================
# Networking Module Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway"
  type        = bool
  default     = true
}

# VPC Endpoint toggles
variable "enable_ssm_endpoint" {
  description = "Enable SSM VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_secretsmanager_endpoint" {
  description = "Enable Secrets Manager VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_kms_endpoint" {
  description = "Enable KMS VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_sts_endpoint" {
  description = "Enable STS VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_ecr_endpoint" {
  description = "Enable ECR VPC endpoints"
  type        = bool
  default     = true
}

variable "enable_logs_endpoint" {
  description = "Enable CloudWatch Logs VPC endpoint"
  type        = bool
  default     = true
}

# Flow Logs
variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention period for flow logs"
  type        = number
  default     = 30
}

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
