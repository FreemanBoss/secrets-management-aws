# =============================================================================
# RDS Module Outputs
# =============================================================================

output "db_instance_id" {
  description = "The RDS instance ID"
  value       = module.rds.db_instance_identifier
}

output "db_instance_endpoint" {
  description = "The connection endpoint"
  value       = module.rds.db_instance_endpoint
}

output "db_instance_address" {
  description = "The hostname of the RDS instance"
  value       = module.rds.db_instance_address
}

output "db_instance_port" {
  description = "The database port"
  value       = module.rds.db_instance_port
}

output "db_instance_name" {
  description = "The database name"
  value       = module.rds.db_instance_name
}

output "db_instance_username" {
  description = "The master username"
  value       = module.rds.db_instance_username
  sensitive   = true
}

output "db_instance_password" {
  description = "The master password"
  value       = random_password.master.result
  sensitive   = true
}

output "db_security_group_id" {
  description = "The security group ID"
  value       = module.rds_security_group.security_group_id
}

output "db_master_secret_arn" {
  description = "ARN of the master credentials secret"
  value       = aws_secretsmanager_secret.rds_master.arn
}

output "db_master_secret_name" {
  description = "Name of the master credentials secret"
  value       = aws_secretsmanager_secret.rds_master.name
}

output "db_parameter_group_id" {
  description = "The ID of the parameter group"
  value       = module.rds.db_parameter_group_id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = module.rds.db_instance_arn
}
