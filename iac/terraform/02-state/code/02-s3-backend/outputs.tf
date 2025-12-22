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
  description = "[LEGACY] DynamoDB table name for state locking (deprecated in TF 1.11+)"
  value       = aws_dynamodb_table.tflock.name
}

# -----------------------------------------------------------------------------
# 后端配置示例
# -----------------------------------------------------------------------------

output "backend_config_recommended" {
  description = "[RECOMMENDED] Backend config with native S3 locking (TF 1.10+)"
  value       = <<-EOT
    # 【推荐】Terraform 1.10+ 原生 S3 锁定配置：

    backend "s3" {
      bucket       = "${aws_s3_bucket.tfstate.bucket}"
      key          = "your-project/terraform.tfstate"
      region       = "ap-northeast-1"
      encrypt      = true
      use_lockfile = true
    }
  EOT
}

output "backend_config_legacy" {
  description = "[LEGACY] Backend config with DynamoDB locking (deprecated)"
  value       = <<-EOT
    # 【旧版】DynamoDB 锁定配置（已弃用，仅供旧项目参考）：

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
