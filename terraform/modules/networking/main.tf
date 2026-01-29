# =============================================================================
# VPC Networking Module
# =============================================================================
# This module creates a production-grade VPC with:
# - Public subnets (for ALB, NAT Gateway)
# - Private subnets (for EKS worker nodes)
# - Database subnets (for RDS - isolated)
# - NAT Gateway for outbound internet access
# - VPC Endpoints for AWS services (cost & security optimization)
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  name = "${var.project_name}-${var.environment}"
  
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)

  tags = merge(
    var.additional_tags,
    {
      Module = "networking"
    }
  )
}

# -----------------------------------------------------------------------------
# VPC Module (using official AWS module)
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"  # Latest as of Jan 2026

  name = local.name
  cidr = var.vpc_cidr

  azs              = local.azs
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.database_subnet_cidrs

  # NAT Gateway Configuration
  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # DNS Configuration
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Database Subnet Configuration
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  database_subnet_group_name         = "${local.name}-db"

  # Subnet Tags for EKS Auto-discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = 1
    "kubernetes.io/cluster/${local.name}-eks"     = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "kubernetes.io/cluster/${local.name}-eks"     = "shared"
  }

  database_subnet_tags = {
    "Type" = "database"
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# VPC Endpoints (Security & Cost Optimization)
# -----------------------------------------------------------------------------
# VPC Endpoints allow private connectivity to AWS services without
# traversing the public internet. This is critical for:
# - Security: Traffic stays within AWS network
# - Cost: Reduces NAT Gateway data processing charges
# - Compliance: Required for many security frameworks
# -----------------------------------------------------------------------------

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name}-vpc-endpoints"
  })
}

# Gateway Endpoints (Free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.database_route_table_ids)

  tags = merge(local.tags, {
    Name = "${local.name}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.database_route_table_ids)

  tags = merge(local.tags, {
    Name = "${local.name}-dynamodb-endpoint"
  })
}

# Interface Endpoints (Critical for Secrets Management)
resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_ssm_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-ssm-endpoint"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.enable_ssm_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-ssmmessages-endpoint"
  })
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_secretsmanager_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-secretsmanager-endpoint"
  })
}

resource "aws_vpc_endpoint" "kms" {
  count = var.enable_kms_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-kms-endpoint"
  })
}

resource "aws_vpc_endpoint" "sts" {
  count = var.enable_sts_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-sts-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_ecr_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_ecr_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  count = var.enable_logs_endpoint ? 1 : 0

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name}-logs-endpoint"
  })
}

# -----------------------------------------------------------------------------
# VPC Flow Logs (Security & Compliance)
# -----------------------------------------------------------------------------

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = module.vpc.vpc_id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = merge(local.tags, {
    Name = "${local.name}-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${local.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = local.tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
