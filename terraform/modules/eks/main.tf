# =============================================================================
# EKS Cluster Module
# =============================================================================
# This module creates a production-grade EKS cluster with:
# - OIDC Provider for IRSA (IAM Roles for Service Accounts)
# - Managed Node Groups with proper configurations
# - Cluster Addons (CoreDNS, kube-proxy, VPC-CNI, EBS CSI)
# - Security configurations
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  name = "${var.project_name}-${var.environment}-eks"
  
  tags = merge(
    var.additional_tags,
    {
      Module = "eks"
    }
  )
}

# -----------------------------------------------------------------------------
# EKS Cluster (using official AWS module)
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.0"  # Latest as of Jan 2026

  cluster_name    = local.name
  cluster_version = var.cluster_version

  # Prevent replacement of existing cluster
  bootstrap_self_managed_addons = false

  # Networking
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Cluster Endpoint Configuration
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Cluster Addons
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate"
        replicaCount = 2
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      before_compute           = true
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Logging
  cluster_enabled_log_types = var.enable_cluster_logging ? [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ] : []

  # OIDC Provider (required for IRSA)
  enable_irsa = true

  # Cluster Security Group
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Node Security Group
  node_security_group_additional_rules = merge(
    {
      ingress_self_all = {
        description = "Node to node all ports/protocols"
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        type        = "ingress"
        self        = true
      }
    },
    # Only add RDS rule if security group ID is provided
    var.rds_security_group_id != null ? {
      egress_rds = {
        description              = "Access to RDS"
        protocol                 = "tcp"
        from_port                = 5432
        to_port                  = 5432
        type                     = "egress"
        source_security_group_id = var.rds_security_group_id
      }
    } : {}
  )

  # Managed Node Groups
  eks_managed_node_groups = merge(
    {
      # Primary node group for general workloads
      primary = {
        name            = "primary"
        use_name_prefix = true

        instance_types = var.node_instance_types
        capacity_type  = var.use_spot_instances ? "SPOT" : "ON_DEMAND"

        min_size     = var.node_min_size
        max_size     = var.node_max_size
        desired_size = var.node_desired_size

        disk_size = var.node_disk_size

        # Node Labels and Taints
        labels = {
          Environment = var.environment
          NodeGroup   = "primary"
        }

        # Launch Template
        create_launch_template = true
        launch_template_name   = "primary"

        # Enable detailed monitoring
        enable_monitoring = true

        # Block device mappings - using default AWS EBS encryption
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.node_disk_size
              volume_type           = "gp3"
              iops                  = 3000
              throughput            = 125
              encrypted             = true
              delete_on_termination = true
            }
          }
        }

        # Node IAM Role
        iam_role_additional_policies = {
          AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        tags = local.tags
      }
    },
    # Vault node group (if HashiCorp Vault is enabled)
    var.enable_vault_nodes ? {
      vault = {
        name            = "vault"
        use_name_prefix = true

        instance_types = ["t3.medium"]
        capacity_type  = "ON_DEMAND"

        min_size     = 3
        max_size     = 3
        desired_size = 3

        disk_size = 50

        labels = {
          Environment = var.environment
          NodeGroup   = "vault"
          dedicated   = "vault"
        }

        taints = [
          {
            key    = "dedicated"
            value  = "vault"
            effect = "NO_SCHEDULE"
          }
        ]

        create_launch_template = true
        launch_template_name   = "vault"

        # Block device mappings - using default AWS EBS encryption
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = 50
              volume_type           = "gp3"
              iops                  = 3000
              throughput            = 125
              encrypted             = true
              delete_on_termination = true
            }
          }
        }

        iam_role_additional_policies = {
          AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }

        tags = merge(local.tags, {
          "k8s.io/cluster-autoscaler/node-template/label/dedicated" = "vault"
        })
      }
    } : {}
  )

  # Cluster access entries (for EKS admin access)
  enable_cluster_creator_admin_permissions = true

  access_entries = var.additional_admin_arns != null ? {
    for arn in var.additional_admin_arns : arn => {
      principal_arn     = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  } : {}

  tags = local.tags
}

# -----------------------------------------------------------------------------
# IRSA for VPC CNI
# -----------------------------------------------------------------------------

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"

  role_name_prefix      = "${local.name}-vpc-cni-"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# IRSA for EBS CSI Driver
# -----------------------------------------------------------------------------

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"

  role_name_prefix      = "${local.name}-ebs-csi-"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for EKS Cluster Logs
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks" {
  count = var.enable_cluster_logging ? 1 : 0

  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = var.log_retention_days

  tags = local.tags
}
