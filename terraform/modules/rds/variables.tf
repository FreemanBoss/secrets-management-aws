# =============================================================================
# RDS Module Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Networking
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  type        = string
}

variable "eks_node_security_group_id" {
  description = "Security group ID of EKS nodes"
  type        = string
  default     = null
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block - used as fallback when EKS SG is not available"
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to access RDS"
  type        = list(string)
  default     = null
}

# Engine Configuration
variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# Storage
variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling"
  type        = number
  default     = 100
}

# Database
variable "database_name" {
  description = "Name of the default database"
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username"
  type        = string
  default     = "dbadmin"
}

# Availability
variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

# Backup
variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

# Performance
variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period"
  type        = number
  default     = 7
}

# Monitoring
variable "monitoring_interval" {
  description = "Enhanced monitoring interval"
  type        = number
  default     = 60
}

variable "log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 30
}

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  type        = string
  default     = null
}

# Security
variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "enable_iam_auth" {
  description = "Enable IAM database authentication"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
