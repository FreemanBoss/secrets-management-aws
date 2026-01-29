# =============================================================================
# Terraform Outputs
# =============================================================================
# This file exports important values from the infrastructure deployment.
# These outputs are essential for:
# - Configuring kubectl and Helm
# - Application deployment
# - Documentation and runbooks
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Name of the database subnet group"
  value       = module.vpc.database_subnet_group_name
}

# -----------------------------------------------------------------------------
# EKS Outputs
# -----------------------------------------------------------------------------

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.enable_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = var.enable_eks ? module.eks[0].cluster_endpoint : null
}

output "eks_cluster_certificate_authority" {
  description = "Base64 encoded certificate authority data for the cluster"
  value       = var.enable_eks ? module.eks[0].cluster_certificate_authority_data : null
  sensitive   = true
}

output "eks_cluster_oidc_issuer_url" {
  description = "The URL of the OIDC Provider for IRSA"
  value       = var.enable_eks ? module.eks[0].cluster_oidc_issuer_url : null
}

output "eks_cluster_oidc_provider_arn" {
  description = "The ARN of the OIDC Provider for IRSA"
  value       = var.enable_eks ? module.eks[0].oidc_provider_arn : null
}

output "eks_kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = var.enable_eks ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks[0].cluster_name}" : null
}

# -----------------------------------------------------------------------------
# RDS Outputs
# -----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = var.enable_rds ? module.rds[0].db_instance_endpoint : null
}

output "rds_port" {
  description = "The port the RDS instance is listening on"
  value       = var.enable_rds ? module.rds[0].db_instance_port : null
}

output "rds_database_name" {
  description = "The name of the default database"
  value       = var.enable_rds ? module.rds[0].db_instance_name : null
}

output "rds_master_username" {
  description = "The master username for the database"
  value       = var.enable_rds ? module.rds[0].db_instance_username : null
  sensitive   = true
}

output "rds_security_group_id" {
  description = "The security group ID for the RDS instance"
  value       = var.enable_rds ? module.rds[0].db_security_group_id : null
}

# -----------------------------------------------------------------------------
# Secrets Management Outputs
# -----------------------------------------------------------------------------

# Parameter Store
output "parameter_store_db_password_arn" {
  description = "ARN of the database password in Parameter Store"
  value       = var.enable_parameter_store ? aws_ssm_parameter.db_password[0].arn : null
}

output "parameter_store_db_password_name" {
  description = "Name of the database password parameter"
  value       = var.enable_parameter_store ? aws_ssm_parameter.db_password[0].name : null
}

# Secrets Manager
output "secrets_manager_db_secret_arn" {
  description = "ARN of the database secret in Secrets Manager"
  value       = var.enable_secrets_manager ? aws_secretsmanager_secret.db_credentials[0].arn : null
}

output "secrets_manager_db_secret_name" {
  description = "Name of the database secret"
  value       = var.enable_secrets_manager ? aws_secretsmanager_secret.db_credentials[0].name : null
}

# HashiCorp Vault
output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = var.enable_vault ? var.vault_namespace : null
}

output "vault_service_url" {
  description = "Internal URL for Vault service"
  value       = var.enable_vault ? "http://vault.${var.vault_namespace}.svc.cluster.local:8200" : null
}

# -----------------------------------------------------------------------------
# IAM Outputs (for IRSA)
# -----------------------------------------------------------------------------

output "parameter_store_role_arn" {
  description = "IAM role ARN for Parameter Store access (IRSA)"
  value       = var.enable_parameter_store && var.enable_eks ? module.parameter_store_irsa[0].iam_role_arn : null
}

output "secrets_manager_role_arn" {
  description = "IAM role ARN for Secrets Manager access (IRSA)"
  value       = var.enable_secrets_manager && var.enable_eks ? module.secrets_manager_irsa[0].iam_role_arn : null
}

output "vault_role_arn" {
  description = "IAM role ARN for Vault access (IRSA)"
  value       = var.enable_vault && var.enable_eks ? module.vault_irsa[0].iam_role_arn : null
}

# -----------------------------------------------------------------------------
# KMS Outputs
# -----------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS key used for secrets encryption"
  value       = aws_kms_key.secrets.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.secrets.name
}

# -----------------------------------------------------------------------------
# Useful Commands
# -----------------------------------------------------------------------------

output "useful_commands" {
  description = "Helpful commands for interacting with the infrastructure"
  value = var.enable_eks ? {
    configure_kubectl = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks[0].cluster_name}"
    get_vault_token   = "kubectl exec -n ${var.vault_namespace} vault-0 -- vault operator init"
    port_forward_vault = "kubectl port-forward -n ${var.vault_namespace} svc/vault 8200:8200"
    test_db_connection = "kubectl run psql-test --rm -it --image=postgres:16 -- psql -h ${var.enable_rds ? split(":", module.rds[0].db_instance_endpoint)[0] : "N/A"} -U ${var.db_username} -d ${var.db_name}"
  } : {}
}
