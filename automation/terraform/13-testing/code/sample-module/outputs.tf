# =============================================================================
# Output Values
# =============================================================================
#
# Outputs from the S3 bucket module.
# All outputs have descriptions for tflint compliance.
#
# =============================================================================

output "bucket_id" {
  description = "The ID of the S3 bucket"
  value       = aws_s3_bucket.main.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.main.arn
}

output "bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.main.bucket
}

output "bucket_region" {
  description = "The AWS region where the bucket is located"
  value       = aws_s3_bucket.main.region
}

output "bucket_domain_name" {
  description = "The bucket domain name"
  value       = aws_s3_bucket.main.bucket_domain_name
}

output "versioning_enabled" {
  description = "Whether versioning is enabled"
  value       = var.enable_versioning
}

output "logging_enabled" {
  description = "Whether access logging is enabled"
  value       = var.enable_logging
}

output "logs_bucket_id" {
  description = "The ID of the logs bucket (if logging is enabled)"
  value       = var.enable_logging ? aws_s3_bucket.logs[0].id : null
}
