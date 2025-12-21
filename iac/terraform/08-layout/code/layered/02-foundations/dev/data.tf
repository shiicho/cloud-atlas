# =============================================================================
# 数据源 - 引用 Network Layer 的输出
# =============================================================================
# 使用 terraform_remote_state 读取其他层的 state
# 这是分层架构中跨层数据共享的关键技术
# =============================================================================

# -----------------------------------------------------------------------------
# 引用 Network Layer
# -----------------------------------------------------------------------------
# 注意：使用 S3 backend 时需要配置正确的 bucket 和 key
# 本示例使用 local backend 仅供学习参考

# 生产环境配置示例：
# data "terraform_remote_state" "network" {
#   backend = "s3"
#   config = {
#     bucket = "my-terraform-state"
#     key    = "dev/network/terraform.tfstate"
#     region = "ap-northeast-1"
#   }
# }

# 学习用：直接引用本地 state 文件
# 注意：这只在本地开发时有效
data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../01-network/dev/terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# 使用 Network Layer 的输出
# -----------------------------------------------------------------------------
# 示例：data.terraform_remote_state.network.outputs.vpc_id
# 示例：data.terraform_remote_state.network.outputs.private_subnet_ids
