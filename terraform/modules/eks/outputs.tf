# =============================================================================
# EKS Module Outputs
# =============================================================================

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OIDC identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.eks.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID of the EKS node group"
  value       = module.eks.node_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "The cluster primary security group ID"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "node_group_iam_role_arns" {
  description = "IAM role ARNs of the EKS managed node groups"
  value       = { for k, v in module.eks.eks_managed_node_groups : k => v.iam_role_arn }
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks.cluster_name}"
}

# Data source for current region
data "aws_region" "current" {}
