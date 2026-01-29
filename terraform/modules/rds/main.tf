# =============================================================================
# RDS PostgreSQL Module
# =============================================================================
# This module creates a production-grade RDS PostgreSQL instance with:
# - Private subnet placement (no public access)
# - Encryption at rest and in transit
# - Performance Insights enabled
# - Automated backups with configurable retention
# - Security group with least-privilege access
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  name = "${var.project_name}-${var.environment}-postgres"
  
  tags = merge(
    var.additional_tags,
    {
      Module = "rds"
    }
  )
}

# -----------------------------------------------------------------------------
# Generate Random Password for Master User
# -----------------------------------------------------------------------------
# This password is used ONLY for initial setup.
# It will be stored in Secrets Manager for rotation.
# -----------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# Security Group for RDS
# -----------------------------------------------------------------------------

module "rds_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"

  name        = "${local.name}-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  # Ingress rules - Allow from VPC CIDR (EKS nodes are in VPC private subnets)
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from VPC"
      cidr_blocks = var.vpc_cidr_block
    }
  ]

  # Egress rules
  egress_rules = ["all-all"]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL Instance
# -----------------------------------------------------------------------------

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.10.0"  # Latest as of Jan 2026

  identifier = local.name

  # Engine Configuration
  engine               = "postgres"
  engine_version       = var.engine_version
  family               = "postgres${split(".", var.engine_version)[0]}"  # postgres16
  major_engine_version = split(".", var.engine_version)[0]               # 16
  instance_class       = var.instance_class

  # Storage Configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  # Database Configuration
  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  # Network Configuration
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [module.rds_security_group.security_group_id]
  publicly_accessible    = false
  
  # Multi-AZ
  multi_az = var.multi_az

  # Maintenance Window
  maintenance_window          = var.maintenance_window
  backup_window               = var.backup_window
  backup_retention_period     = var.backup_retention_period
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier_prefix = "${local.name}-final"
  deletion_protection         = var.deletion_protection
  delete_automated_backups    = !var.deletion_protection

  # Performance Insights
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = var.kms_key_arn

  # Enhanced Monitoring
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_name                  = "${local.name}-monitoring-role"
  create_monitoring_role                = var.monitoring_interval > 0

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # Parameter Group
  create_db_parameter_group = true
  parameters = [
    {
      name  = "log_statement"
      value = "all"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"  # Log queries taking more than 1 second
    },
    {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
      apply_method = "pending-reboot"
    },
    {
      name  = "pg_stat_statements.track"
      value = "all"
    },
    {
      name  = "rds.force_ssl"
      value = "1"
    }
  ]

  # Option Group
  create_db_option_group = false

  # IAM Database Authentication
  iam_database_authentication_enabled = var.enable_iam_auth

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Store Master Password in Secrets Manager (for rotation)
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "rds_master" {
  name        = "${local.name}/master-credentials"
  description = "Master credentials for RDS PostgreSQL instance ${local.name}"
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = var.deletion_protection ? 30 : 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id
  secret_string = jsonencode({
    username            = var.master_username
    password            = random_password.master.result
    engine              = "postgres"
    host                = module.rds.db_instance_endpoint
    port                = 5432
    dbname              = var.database_name
    dbInstanceIdentifier = module.rds.db_instance_identifier
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for RDS
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name}-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization is too high"

  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name}-free-storage-space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120  # 5 GB in bytes
  alarm_description   = "RDS free storage space is too low"

  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name}-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "RDS database connections are too high"

  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}
