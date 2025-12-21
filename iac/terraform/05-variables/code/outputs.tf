# outputs.tf
# 输出值定义

# -----------------------------------------------------------------------------
# 资源信息
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "S3 Bucket 名称"
  value       = aws_s3_bucket.app.bucket
}

output "bucket_arn" {
  description = "S3 Bucket ARN"
  value       = aws_s3_bucket.app.arn
}

# -----------------------------------------------------------------------------
# 配置信息
# -----------------------------------------------------------------------------

output "environment" {
  description = "部署环境"
  value       = var.environment
}

output "project" {
  description = "项目名称"
  value       = var.project
}

output "versioning_enabled" {
  description = "版本控制是否启用"
  value       = var.enable_versioning
}

output "encryption_enabled" {
  description = "加密是否启用"
  value       = var.enable_encryption
}

# -----------------------------------------------------------------------------
# 计算值（来自 locals）
# -----------------------------------------------------------------------------

output "name_prefix" {
  description = "资源命名前缀"
  value       = local.name_prefix
}

output "instance_type" {
  description = "环境对应的实例类型"
  value       = local.instance_type
}

output "is_production" {
  description = "是否为生产环境"
  value       = local.is_production
}

output "lifecycle_days" {
  description = "生命周期天数"
  value       = local.lifecycle_days
}

# -----------------------------------------------------------------------------
# 敏感输出
# -----------------------------------------------------------------------------

output "db_password_set" {
  description = "数据库密码是否已设置"
  value       = var.db_password != "" ? "Yes (hidden)" : "No"
}

# 如果需要输出敏感值，必须标记 sensitive
# output "db_password" {
#   description = "数据库密码"
#   value       = var.db_password
#   sensitive   = true
# }
