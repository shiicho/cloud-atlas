# =============================================================================
# Backend 配置 - Network Layer (Dev)
# =============================================================================

# 学习用：local backend
# 实际项目中使用 S3 backend，key 按层级组织

# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state"
#     key            = "dev/network/terraform.tfstate"  # 层级路径
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
