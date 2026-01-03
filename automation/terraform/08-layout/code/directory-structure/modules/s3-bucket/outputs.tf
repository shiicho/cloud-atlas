# =============================================================================
# S3 Bucket 模块 - 输出值
# =============================================================================

output "bucket_id" {
  description = "S3 Bucket ID"
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "S3 Bucket 名称"
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "S3 Bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "S3 Bucket 域名"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "S3 Bucket 区域域名"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
