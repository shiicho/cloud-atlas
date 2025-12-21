# =============================================================================
# 输出值 - Dev 环境
# =============================================================================

output "environment" {
  description = "当前环境"
  value       = var.environment
}

output "bucket_name" {
  description = "S3 Bucket 名称"
  value       = module.s3_bucket.bucket_name
}

output "bucket_arn" {
  description = "S3 Bucket ARN"
  value       = module.s3_bucket.bucket_arn
}
