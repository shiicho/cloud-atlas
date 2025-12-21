# =============================================================================
# 主配置 - Prod 环境
# =============================================================================
# 生产环境可能有额外的配置，如：
# - 更多标签
# - 额外的安全措施
# - 不同的资源规格
# =============================================================================

module "s3_bucket" {
  source = "../../modules/s3-bucket"

  environment       = var.environment
  bucket_prefix     = var.bucket_prefix
  enable_versioning = var.enable_versioning
  lifecycle_days    = var.lifecycle_days

  tags = {
    Team        = "operations"
    Purpose     = "Production storage"
    CostCenter  = "PROD-001"
    Compliance  = "required"
  }
}
