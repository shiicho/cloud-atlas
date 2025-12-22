# =============================================================================
# 输出值 - State 安全配置
# Outputs - State Security Configuration
# =============================================================================

output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.tfstate.arn
}

# Note: Using S3 native locking (use_lockfile = true)
# Terraform 1.10+ supports native S3 locking via .tflock files

output "kms_key_arn" {
  description = "ARN of the KMS key for state encryption"
  value       = aws_kms_key.tfstate.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key for state encryption"
  value       = aws_kms_alias.tfstate.name
}

output "logs_bucket_name" {
  description = "Name of the S3 bucket for access logs"
  value       = aws_s3_bucket.logs.id
}

# =============================================================================
# Backend 配置示例（供其他项目使用）
# =============================================================================

output "backend_config_example" {
  description = "Example backend configuration for other Terraform projects"
  value       = <<-EOF

    # 将以下配置添加到你的 terraform 块中：
    # Add the following configuration to your terraform block:

    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tfstate.id}"
        key          = "your-project/terraform.tfstate"
        region       = "${data.aws_region.current.name}"
        encrypt      = true
        kms_key_id   = "${aws_kms_alias.tfstate.name}"
        use_lockfile = true  # Terraform 1.10+ S3 原生锁定
      }
    }

  EOF
}
