# outputs.tf
# 输出值

output "bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.demo.arn
}

output "warning" {
  description = "Important warning about local state"
  value       = "This demo uses LOCAL state - NOT suitable for team collaboration!"
}
