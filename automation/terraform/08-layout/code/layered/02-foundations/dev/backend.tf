# =============================================================================
# Backend 配置 - Foundations Layer (Dev)
# =============================================================================

# 学习用：local backend
# terraform {
#   backend "s3" {
#     bucket       = "my-terraform-state"
#     key          = "dev/foundations/terraform.tfstate"
#     region       = "ap-northeast-1"
#     use_lockfile = true  # Terraform 1.10+ 原生 S3 锁定
#     encrypt      = true
#   }
# }

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
