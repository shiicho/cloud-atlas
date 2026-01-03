# outputs.tf
# 输出值定义
#
# 输出值在 terraform apply 后显示，也可以被其他模块引用。
# 在 CI/CD 流程中，输出值会显示在 apply 日志中。

# =============================================================================
# S3 Bucket 信息
# =============================================================================

output "bucket_name" {
  description = "S3 Bucket 名称"
  value       = aws_s3_bucket.example.bucket
}

output "bucket_arn" {
  description = "S3 Bucket ARN"
  value       = aws_s3_bucket.example.arn
}

output "bucket_region" {
  description = "S3 Bucket 区域"
  value       = aws_s3_bucket.example.region
}

# =============================================================================
# 版本控制状态
# =============================================================================

output "versioning_status" {
  description = "版本控制状态"
  value       = aws_s3_bucket_versioning.example.versioning_configuration[0].status
}

# =============================================================================
# 环境信息
# =============================================================================

output "environment" {
  description = "当前环境"
  value       = var.environment
}

output "project_name" {
  description = "项目名称"
  value       = var.project_name
}
