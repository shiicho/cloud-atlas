# =============================================================================
# modules/rds/outputs.tf
# RDS 模块输出值
# =============================================================================

# -----------------------------------------------------------------------------
# RDS Instance
# -----------------------------------------------------------------------------

output "db_instance_id" {
  description = "RDS 实例 ID"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "RDS 实例 ARN"
  value       = aws_db_instance.main.arn
}

output "db_instance_identifier" {
  description = "RDS 实例标识符"
  value       = aws_db_instance.main.identifier
}

output "db_instance_endpoint" {
  description = "RDS 实例端点（hostname:port）"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  description = "RDS 实例地址（hostname only）"
  value       = aws_db_instance.main.address
}

output "db_instance_port" {
  description = "RDS 实例端口"
  value       = aws_db_instance.main.port
}

output "db_instance_hosted_zone_id" {
  description = "RDS 实例托管区域 ID"
  value       = aws_db_instance.main.hosted_zone_id
}

output "db_instance_resource_id" {
  description = "RDS 实例资源 ID"
  value       = aws_db_instance.main.resource_id
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

output "db_name" {
  description = "数据库名称"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "数据库用户名"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_password_ssm_parameter" {
  description = "密码的 SSM Parameter 名称"
  value       = var.store_password_in_ssm ? aws_ssm_parameter.master_password[0].name : null
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "RDS 安全组 ID"
  value       = aws_security_group.rds.id
}

output "security_group_arn" {
  description = "RDS 安全组 ARN"
  value       = aws_security_group.rds.arn
}

# -----------------------------------------------------------------------------
# Subnet Group
# -----------------------------------------------------------------------------

output "db_subnet_group_name" {
  description = "DB Subnet Group 名称"
  value       = var.db_subnet_group_name != null ? var.db_subnet_group_name : aws_db_subnet_group.main[0].name
}

output "db_subnet_group_arn" {
  description = "DB Subnet Group ARN"
  value       = var.db_subnet_group_name == null ? aws_db_subnet_group.main[0].arn : null
}

# -----------------------------------------------------------------------------
# Parameter Group
# -----------------------------------------------------------------------------

output "parameter_group_name" {
  description = "Parameter Group 名称"
  value       = var.create_parameter_group ? aws_db_parameter_group.main[0].name : var.parameter_group_name
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

output "monitoring_role_arn" {
  description = "增强监控 IAM Role ARN"
  value       = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
}

# -----------------------------------------------------------------------------
# Connection String
# -----------------------------------------------------------------------------

output "connection_string" {
  description = "数据库连接字符串（不含密码）"
  value       = "${var.engine}://${aws_db_instance.main.username}:****@${aws_db_instance.main.endpoint}/${aws_db_instance.main.db_name}"
}

output "jdbc_connection_string" {
  description = "JDBC 连接字符串"
  value       = "jdbc:${var.engine}://${aws_db_instance.main.endpoint}/${aws_db_instance.main.db_name}"
}
