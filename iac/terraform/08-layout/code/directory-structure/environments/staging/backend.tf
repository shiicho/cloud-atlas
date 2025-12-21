# =============================================================================
# Backend 配置 - Staging 环境
# =============================================================================

# 注意：本示例使用 local backend 便于学习
# 实际项目中应使用 S3 backend

# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state-bucket"
#     key            = "staging/terraform.tfstate"  # staging 专用路径
#     region         = "ap-northeast-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
