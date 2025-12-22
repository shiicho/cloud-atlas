# =============================================================================
# Backend 配置 - Prod 环境
# =============================================================================
# 生产环境的 state 应该有额外的保护措施
# 建议：使用独立的 S3 bucket，限制访问权限
# =============================================================================

# 注意：本示例使用 local backend 便于学习
# 实际项目中 prod 应使用 S3 backend 并加强保护

# terraform {
#   backend "s3" {
#     bucket       = "my-terraform-state-bucket"
#     key          = "prod/terraform.tfstate"  # prod 专用路径
#     region       = "ap-northeast-1"
#     use_lockfile = true  # Terraform 1.10+ 原生 S3 锁定
#     encrypt      = true
#
#     # 生产环境建议：
#     # - 使用 KMS 加密
#     # - 开启 S3 versioning
#     # - 配置 S3 access logs
#     # - 限制 bucket policy
#   }
# }

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
