# Main Infrastructure Configuration

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name = "${var.project_name}-${var.environment}"
  
  common_tags = merge(
    var.additional_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )
}

# KMS Key for Secrets Encryption
resource "aws_kms_key" "secrets" {
  description             = "KMS key for secrets encryption - ${local.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EKS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow RDS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager to use the key"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# -----------------------------------------------------------------------------
# VPC Networking
module "vpc" {
  source = "./modules/networking"

  project_name    = var.project_name
  environment     = var.environment
  aws_region      = var.aws_region

  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  availability_zones    = var.availability_zones

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # VPC Endpoints for secure connectivity
  enable_ssm_endpoint            = var.enable_parameter_store || var.enable_secrets_manager
  enable_secretsmanager_endpoint = var.enable_secrets_manager
  enable_kms_endpoint            = true
  enable_sts_endpoint            = true
  enable_ecr_endpoint            = true
  enable_logs_endpoint           = var.enable_cloudwatch_logs

  enable_flow_logs         = true
  flow_logs_retention_days = var.log_retention_days

  additional_tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EKS Cluster
module "eks" {
  source = "./modules/eks"
  count  = var.enable_eks ? 1 : 0

  project_name = var.project_name
  environment  = var.environment

  cluster_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # RDS security group is added after RDS is created via separate resource
  rds_security_group_id = null

  node_instance_types = var.eks_node_instance_types
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  node_desired_size   = var.eks_node_desired_size
  node_disk_size      = var.eks_node_disk_size

  enable_vault_nodes = var.enable_vault && var.vault_ha_enabled

  enable_cluster_logging = var.enable_cloudwatch_logs
  log_retention_days     = var.log_retention_days

  kms_key_arn = aws_kms_key.secrets.arn

  additional_tags = local.common_tags

  depends_on = [module.vpc]
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL
module "rds" {
  source = "./modules/rds"
  count  = var.enable_rds ? 1 : 0

  project_name = var.project_name
  environment  = var.environment

  vpc_id               = module.vpc.vpc_id
  vpc_cidr_block       = var.vpc_cidr
  db_subnet_group_name = module.vpc.database_subnet_group_name

  # EKS node security group - allow access from EKS nodes
  eks_node_security_group_id = var.enable_eks ? module.eks[0].node_security_group_id : null

  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 5

  database_name   = var.db_name
  master_username = var.db_username

  multi_az           = var.db_multi_az
  deletion_protection = var.db_deletion_protection

  backup_retention_period = var.db_backup_retention_period

  kms_key_arn     = aws_kms_key.secrets.arn
  enable_iam_auth = true

  create_cloudwatch_alarms = true
  log_retention_days       = var.log_retention_days

  additional_tags = local.common_tags

  depends_on = [module.vpc]
}

# =============================================================================
# SCENARIO A: SSM Parameter Store
resource "aws_ssm_parameter" "db_password" {
  count = var.enable_parameter_store && var.enable_rds ? 1 : 0

  name        = "/${local.name}/database/password"
  description = "Database password for ${local.name}"
  type        = "SecureString"
  value       = module.rds[0].db_instance_password
  key_id      = aws_kms_key.secrets.arn

  tier = "Standard"

  tags = merge(local.common_tags, {
    Scenario = "parameter-store"
  })
}

resource "aws_ssm_parameter" "db_connection_string" {
  count = var.enable_parameter_store && var.enable_rds ? 1 : 0

  name        = "/${local.name}/database/connection-string"
  description = "Database connection string for ${local.name}"
  type        = "SecureString"
  value       = "postgresql://${var.db_username}:${module.rds[0].db_instance_password}@${module.rds[0].db_instance_endpoint}/${var.db_name}?sslmode=require"
  key_id      = aws_kms_key.secrets.arn

  tier = "Standard"

  tags = merge(local.common_tags, {
    Scenario = "parameter-store"
  })
}

resource "aws_ssm_parameter" "api_key" {
  count = var.enable_parameter_store ? 1 : 0

  name        = "/${local.name}/api/key"
  description = "API key for ${local.name}"
  type        = "SecureString"
  value       = random_password.api_key.result
  key_id      = aws_kms_key.secrets.arn

  tier = "Standard"

  tags = merge(local.common_tags, {
    Scenario = "parameter-store"
  })
}

# IRSA for Parameter Store access
module "parameter_store_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"
  count   = var.enable_parameter_store && var.enable_eks ? 1 : 0

  role_name_prefix = "${local.name}-param-store-"
  
  role_policy_arns = {
    policy = aws_iam_policy.parameter_store_read[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks[0].oidc_provider_arn
      namespace_service_accounts = ["apps:app-parameter-store"]
    }
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "parameter_store_read" {
  count = var.enable_parameter_store ? 1 : 0

  name        = "${local.name}-parameter-store-read"
  description = "Allow reading from Parameter Store for ${local.name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${local.name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.secrets.arn
      }
    ]
  })

  tags = local.common_tags
}

# =============================================================================
# SCENARIO B: AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  count = var.enable_secrets_manager && var.enable_rds ? 1 : 0

  name        = "${local.name}/database/credentials"
  description = "Database credentials for ${local.name}"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = var.db_deletion_protection ? 30 : 0

  tags = merge(local.common_tags, {
    Scenario = "secrets-manager"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  count = var.enable_secrets_manager && var.enable_rds ? 1 : 0

  secret_id = aws_secretsmanager_secret.db_credentials[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = module.rds[0].db_instance_password
    engine   = "postgres"
    host     = split(":", module.rds[0].db_instance_endpoint)[0]
    port     = 5432
    dbname   = var.db_name
  })
}

resource "aws_secretsmanager_secret" "api_credentials" {
  count = var.enable_secrets_manager ? 1 : 0

  name        = "${local.name}/api/credentials"
  description = "API credentials for ${local.name}"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Scenario = "secrets-manager"
  })
}

resource "aws_secretsmanager_secret_version" "api_credentials" {
  count = var.enable_secrets_manager ? 1 : 0

  secret_id = aws_secretsmanager_secret.api_credentials[0].id
  secret_string = jsonencode({
    api_key    = random_password.api_key.result
    api_secret = random_password.api_secret.result
  })
}

# IRSA for Secrets Manager access
module "secrets_manager_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"
  count   = var.enable_secrets_manager && var.enable_eks ? 1 : 0

  role_name_prefix = "${local.name}-secrets-mgr-"
  
  role_policy_arns = {
    policy = aws_iam_policy.secrets_manager_read[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks[0].oidc_provider_arn
      namespace_service_accounts = ["apps:app-secrets-manager"]
    }
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "secrets_manager_read" {
  count = var.enable_secrets_manager ? 1 : 0

  name        = "${local.name}-secrets-manager-read"
  description = "Allow reading from Secrets Manager for ${local.name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.secrets.arn
      }
    ]
  })

  tags = local.common_tags
}

# =============================================================================
# SCENARIO C: HashiCorp Vault
# IRSA for Vault
module "vault_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"
  count   = var.enable_vault && var.enable_eks ? 1 : 0

  role_name_prefix = "${local.name}-vault-"
  
  role_policy_arns = {
    policy = aws_iam_policy.vault[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks[0].oidc_provider_arn
      namespace_service_accounts = ["${var.vault_namespace}:vault"]
    }
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "vault" {
  count = var.enable_vault ? 1 : 0

  name        = "${local.name}-vault-policy"
  description = "IAM policy for HashiCorp Vault on EKS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# IRSA for Vault-injected applications
module "vault_app_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"
  count   = var.enable_vault && var.enable_eks ? 1 : 0

  role_name_prefix = "${local.name}-vault-app-"
  
  oidc_providers = {
    main = {
      provider_arn               = module.eks[0].oidc_provider_arn
      namespace_service_accounts = ["apps:app-vault"]
    }
  }

  tags = local.common_tags
}

# =============================================================================
# Random Values for Demo
resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "random_password" "api_secret" {
  length  = 64
  special = true
}

# =============================================================================
# Security Group for RDS (from EKS access)
module "rds_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"
  count   = var.enable_rds ? 1 : 0

  name        = "${local.name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = var.enable_eks ? [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "PostgreSQL from EKS"
      source_security_group_id = module.eks[0].node_security_group_id
    }
  ] : []

  tags = local.common_tags
}
