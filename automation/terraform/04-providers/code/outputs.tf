# outputs.tf
# 输出值定义

# -----------------------------------------------------------------------------
# 东京区域资源（默认 Provider）
# -----------------------------------------------------------------------------

output "tokyo_bucket" {
  description = "东京区域 S3 Bucket 名称"
  value       = aws_s3_bucket.demo.bucket
}

output "tokyo_bucket_region" {
  description = "东京区域 S3 Bucket 所在区域"
  value       = aws_s3_bucket.demo.region
}

# -----------------------------------------------------------------------------
# 大阪区域资源（alias Provider）
# -----------------------------------------------------------------------------

output "osaka_bucket" {
  description = "大阪区域 S3 Bucket 名称"
  value       = aws_s3_bucket.osaka.bucket
}

output "osaka_bucket_region" {
  description = "大阪区域 S3 Bucket 所在区域"
  value       = aws_s3_bucket.osaka.region
}

# -----------------------------------------------------------------------------
# 区域信息对比
# -----------------------------------------------------------------------------

output "osaka_region_name" {
  description = "大阪 Provider 区域名"
  value       = data.aws_region.osaka.name
}

# -----------------------------------------------------------------------------
# 便捷命令
# -----------------------------------------------------------------------------
#
# 验证 Bucket 区域：
#
# aws s3api get-bucket-location --bucket $(terraform output -raw tokyo_bucket)
# aws s3api get-bucket-location --bucket $(terraform output -raw osaka_bucket)
#
# 期望输出：
# {"LocationConstraint": "ap-northeast-1"}  # 东京
# {"LocationConstraint": "ap-northeast-3"}  # 大阪
# -----------------------------------------------------------------------------
