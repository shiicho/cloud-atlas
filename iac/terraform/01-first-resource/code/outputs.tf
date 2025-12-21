# outputs.tf
# 输出值定义
#
# Output 用于：
# 1. apply 完成后显示重要信息
# 2. 供其他 Terraform 模块引用（module.xxx.output_name）
# 3. 供外部脚本读取（terraform output -raw xxx）

# -----------------------------------------------------------------------------
# Bucket 基本信息
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "S3 Bucket 名称"
  value       = aws_s3_bucket.first_bucket.bucket
}

output "bucket_id" {
  description = "S3 Bucket ID（与 bucket_name 相同）"
  value       = aws_s3_bucket.first_bucket.id
}

output "bucket_arn" {
  description = "S3 Bucket ARN（用于 IAM 策略）"
  value       = aws_s3_bucket.first_bucket.arn
}

output "bucket_region" {
  description = "S3 Bucket 所在区域"
  value       = aws_s3_bucket.first_bucket.region
}

# -----------------------------------------------------------------------------
# 访问信息
# -----------------------------------------------------------------------------

output "bucket_domain_name" {
  description = "S3 Bucket 域名（用于直接访问）"
  value       = aws_s3_bucket.first_bucket.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "S3 Bucket 区域域名"
  value       = aws_s3_bucket.first_bucket.bucket_regional_domain_name
}

# -----------------------------------------------------------------------------
# 便捷链接
# -----------------------------------------------------------------------------

output "console_url" {
  description = "AWS Console 中查看此 Bucket 的 URL"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.first_bucket.bucket}?region=${aws_s3_bucket.first_bucket.region}"
}

# -----------------------------------------------------------------------------
# Output 使用示例
# -----------------------------------------------------------------------------
#
# 命令行读取：
#   terraform output                    # 显示所有输出
#   terraform output bucket_name        # 显示特定输出（带引号）
#   terraform output -raw bucket_name   # 显示原始值（无引号，脚本用）
#
# 在脚本中使用：
#   BUCKET=$(terraform output -raw bucket_name)
#   aws s3 cp file.txt s3://$BUCKET/
#
# 在其他模块中引用：
#   module "other" {
#     bucket_name = module.this.bucket_name
#   }
# -----------------------------------------------------------------------------
