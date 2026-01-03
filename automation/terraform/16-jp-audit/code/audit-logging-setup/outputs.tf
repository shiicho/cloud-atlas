# =============================================================================
# 出力値 - 監査ログ基盤
# =============================================================================
#
# 設計書やドキュメントに記載する情報
# terraform-docs で自動生成可能
#
# =============================================================================

# -----------------------------------------------------------------------------
# State バケット情報
# -----------------------------------------------------------------------------
output "state_bucket_name" {
  description = "Terraform State 保存用 S3 バケット名"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "Terraform State 保存用 S3 バケット ARN"
  value       = aws_s3_bucket.tfstate.arn
}

output "state_bucket_region" {
  description = "State バケットのリージョン"
  value       = aws_s3_bucket.tfstate.region
}

# -----------------------------------------------------------------------------
# ログバケット情報
# -----------------------------------------------------------------------------
output "log_bucket_name" {
  description = "監査ログ保存用 S3 バケット名"
  value       = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  description = "監査ログ保存用 S3 バケット ARN"
  value       = aws_s3_bucket.logs.arn
}

# -----------------------------------------------------------------------------
# CloudTrail 情報
# -----------------------------------------------------------------------------
output "cloudtrail_name" {
  description = "CloudTrail 名"
  value       = aws_cloudtrail.terraform.name
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN"
  value       = aws_cloudtrail.terraform.arn
}

# -----------------------------------------------------------------------------
# State Locking 情報
# Terraform 1.10+ では S3 原生锁定（use_lockfile = true）を使用
# .tflock ファイルで锁机制を実現
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# KMS キー情報
# -----------------------------------------------------------------------------
output "kms_key_arn" {
  description = "State 暗号化用 KMS キー ARN"
  value       = aws_kms_key.tfstate.arn
}

output "kms_key_alias" {
  description = "KMS キーエイリアス"
  value       = aws_kms_alias.tfstate.name
}

# -----------------------------------------------------------------------------
# Backend 設定用（他プロジェクトから参照）
# -----------------------------------------------------------------------------
output "backend_config" {
  description = "Terraform backend 設定（他プロジェクトで使用）"
  value = {
    bucket       = aws_s3_bucket.tfstate.id
    region       = aws_s3_bucket.tfstate.region
    encrypt      = true
    kms_key_id   = aws_kms_key.tfstate.arn
    use_lockfile = true  # Terraform 1.10+ S3 原生锁定
  }
}

# -----------------------------------------------------------------------------
# 監査情報サマリ（設計書用）
# -----------------------------------------------------------------------------
output "audit_summary" {
  description = "監査対応サマリ（設計書に記載）"
  value = {
    state_versioning    = "Enabled"
    state_encryption    = "KMS (${aws_kms_alias.tfstate.name})"
    access_logging      = "Enabled (${aws_s3_bucket.logs.id}/access-logs/)"
    cloudtrail          = aws_cloudtrail.terraform.name
    log_retention       = "${var.log_retention_days} days"
    version_retention   = "${var.state_version_retention_days} days"
    multi_region_trail  = var.multi_region_trail
  }
}
