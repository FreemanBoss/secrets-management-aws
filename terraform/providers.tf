# =============================================================================
# Terraform Provider Configuration
# =============================================================================
# This file defines the required providers and their versions.
# We pin versions to ensure reproducibility and avoid breaking changes.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # AWS Provider - Core infrastructure
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.0"  # Latest stable as of Jan 2026
    }

    # Kubernetes Provider - For K8s resources
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35.0"
    }

    # Helm Provider - For Helm chart deployments
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }

    # TLS Provider - For certificate generation
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }

    # Random Provider - For generating random values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }

    # Vault Provider - For HashiCorp Vault configuration
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5.0"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure for production use
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "secrets-management/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# =============================================================================
# Provider Configurations
# =============================================================================

# Primary AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "secrets-management"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "devops-team"
    }
  }
}

# Secondary AWS Provider for multi-region resources (DR)
provider "aws" {
  alias  = "dr_region"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = "secrets-management"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "devops-team"
    }
  }
}

# Kubernetes Provider - Configured after EKS is created
provider "kubernetes" {
  host                   = try(module.eks[0].cluster_endpoint, null)
  cluster_ca_certificate = try(base64decode(module.eks[0].cluster_certificate_authority_data), null)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", try(module.eks[0].cluster_name, "")]
  }
}

# Helm Provider - For deploying charts
provider "helm" {
  kubernetes {
    host                   = try(module.eks[0].cluster_endpoint, null)
    cluster_ca_certificate = try(base64decode(module.eks[0].cluster_certificate_authority_data), null)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", try(module.eks[0].cluster_name, "")]
    }
  }
}
