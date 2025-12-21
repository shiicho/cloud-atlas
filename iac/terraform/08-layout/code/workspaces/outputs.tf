# =============================================================================
# 输出值定义
# =============================================================================
# 输出当前 workspace 的资源信息
# 可用于脚本读取或其他模块引用
# =============================================================================

output "environment" {
  description = "当前环境名称（workspace 名称）"
  value       = terraform.workspace
}

output "bucket_name" {
  description = "S3 Bucket 名称"
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "S3 Bucket ARN"
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "S3 Bucket 所在区域"
  value       = aws_s3_bucket.demo.region
}

output "versioning_enabled" {
  description = "版本控制是否开启"
  value       = local.env_config.enable_versioning
}

output "lifecycle_days" {
  description = "对象过期天数"
  value       = local.env_config.lifecycle_days
}

# =============================================================================
# 调试信息
# =============================================================================
output "debug_info" {
  description = "调试信息（展示 workspace 机制）"
  value = {
    workspace          = terraform.workspace
    env_config         = local.env_config
    is_production      = terraform.workspace == "prod"
    force_destroy      = terraform.workspace != "prod"
  }
}
