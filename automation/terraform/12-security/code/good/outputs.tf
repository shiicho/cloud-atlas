# =============================================================================
# 输出值 - 最佳实践示例
# Outputs - Best Practice Example
# =============================================================================

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}

# =============================================================================
# 敏感输出 - 使用 sensitive = true
# =============================================================================
#
# 注意：即使标记为 sensitive，这些值仍会存储在 State 文件中
# sensitive = true 只是防止在 CLI 输出中显示
#
# 建议：
# - 尽量避免将敏感值作为 output
# - 如果必须输出，确保 State 文件已加密
# - 不要在 CI/CD 日志中打印 output
#

output "db_username" {
  description = "Database username (non-sensitive, okay to output)"
  value       = aws_db_instance.main.username
}

# 不要这样做：输出密码
# output "db_password" {
#   description = "Database password"
#   value       = data.aws_ssm_parameter.db_password.value
#   sensitive   = true  # 即使标记为 sensitive，仍在 State 中
# }

# =============================================================================
# 连接信息（供应用使用）
# =============================================================================

output "db_connection_string_ssm_path" {
  description = "SSM parameter path for database password (apps should fetch from here)"
  value       = "/myapp/${var.environment}/db/password"
}

output "security_group_id" {
  description = "Security group ID for the database"
  value       = aws_security_group.db.id
}
