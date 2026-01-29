# =============================================================================
# Networking Module Outputs
# =============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "List of database subnet IDs"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Name of the database subnet group"
  value       = module.vpc.database_subnet_group_name
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = module.vpc.natgw_ids
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_ids" {
  description = "List of public route table IDs"
  value       = module.vpc.public_route_table_ids
}
