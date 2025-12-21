# outputs.tf
# 输出值 - 远程后端配置所需信息

# -----------------------------------------------------------------------------
# 后端基础设施信息
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.tfstate.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN for Terraform state"
  value       = aws_s3_bucket.tfstate.arn
}

output "dynamodb_table" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.tflock.name
}

# -----------------------------------------------------------------------------
# 后端配置示例
# -----------------------------------------------------------------------------

output "backend_config" {
  description = "Example backend configuration to use in other projects"
  value       = <<-EOT
    # 将以下配置添加到你的 terraform {} 块中：

    backend "s3" {
      bucket         = "${aws_s3_bucket.tfstate.bucket}"
      key            = "your-project/terraform.tfstate"
      region         = "ap-northeast-1"
      dynamodb_table = "${aws_dynamodb_table.tflock.name}"
      encrypt        = true
    }
  EOT
}

# -----------------------------------------------------------------------------
# 演示资源信息
# -----------------------------------------------------------------------------

output "demo_bucket_name" {
  description = "Demo S3 bucket name (uses remote state)"
  value       = aws_s3_bucket.demo.bucket
}
