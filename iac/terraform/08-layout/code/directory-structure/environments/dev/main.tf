# =============================================================================
# 主配置 - Dev 环境
# =============================================================================
# 调用共享模块，传入 dev 环境的配置
# =============================================================================

module "s3_bucket" {
  source = "../../modules/s3-bucket"

  environment       = var.environment
  bucket_prefix     = var.bucket_prefix
  enable_versioning = var.enable_versioning
  lifecycle_days    = var.lifecycle_days

  tags = {
    Team    = "development"
    Purpose = "Dev environment storage"
  }
}
