# =============================================================================
# Foundations Layer Outputs
# =============================================================================
# 这些输出将被 03-application 层引用
# =============================================================================

output "data_bucket_name" {
  description = "Data S3 bucket name"
  value       = aws_s3_bucket.data.bucket
}

output "data_bucket_arn" {
  description = "Data S3 bucket ARN"
  value       = aws_s3_bucket.data.arn
}

output "data_security_group_id" {
  description = "Data layer security group ID"
  value       = aws_security_group.data.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.main.name
}

# 透传 Network Layer 的输出（方便 Application Layer 使用）
output "vpc_id" {
  description = "VPC ID (from network layer)"
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (from network layer)"
  value       = local.private_subnet_ids
}
