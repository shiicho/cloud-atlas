# envs/dev.tfvars
# 开发环境配置
#
# 使用方法：
#   terraform plan -var-file=envs/dev.tfvars
#   terraform apply -var-file=envs/dev.tfvars

# 环境标识
environment = "dev"

# 开发环境：简化配置，节省成本
enable_versioning = false
enable_encryption = true
lifecycle_days    = 7     # 7 天后删除旧对象

# 开发环境标签
extra_tags = {
  Owner   = "dev-team"
  Purpose = "development"
}
