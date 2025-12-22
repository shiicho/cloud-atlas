# =============================================================================
# Provider 配置 - 最佳实践示例
# Provider Configuration - Best Practice Example
# =============================================================================
#
# 注意：如果使用远程后端，请取消下面 backend 块的注释
#

# terraform {
#   backend "s3" {
#     bucket       = "your-tfstate-bucket"
#     key          = "myapp/${terraform.workspace}/terraform.tfstate"
#     region       = "ap-northeast-1"
#     encrypt      = true
#     kms_key_id   = "alias/terraform-state-key"
#     use_lockfile = true  # Terraform 1.10+ S3 原生锁定
#   }
# }
