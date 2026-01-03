# =============================================================================
# 主配置 - Staging 环境
# =============================================================================

module "s3_bucket" {
  source = "../../modules/s3-bucket"

  environment       = var.environment
  bucket_prefix     = var.bucket_prefix
  enable_versioning = var.enable_versioning
  lifecycle_days    = var.lifecycle_days

  tags = {
    Team    = "qa"
    Purpose = "Staging environment storage"
  }
}
