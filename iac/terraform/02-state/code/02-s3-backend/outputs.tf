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

# -----------------------------------------------------------------------------
# 后端配置示例
# -----------------------------------------------------------------------------

output "backend_config" {
  description = "Backend config with native S3 locking (Terraform 1.10+)"
  value       = <<-EOT
    # Terraform 1.10+ 原生 S3 锁定配置：

    backend "s3" {
      bucket       = "${aws_s3_bucket.tfstate.bucket}"
      key          = "your-project/terraform.tfstate"
      region       = "ap-northeast-1"
      encrypt      = true
      use_lockfile = true
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
