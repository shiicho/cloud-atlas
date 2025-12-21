# envs/prod.tfvars
# 生产环境配置
#
# 使用方法：
#   terraform plan -var-file=envs/prod.tfvars
#   terraform apply -var-file=envs/prod.tfvars

# 环境标识
environment = "prod"

# 生产环境：完整配置，数据保护
enable_versioning = true
enable_encryption = true
lifecycle_days    = 365   # 保留 1 年

# 生产环境标签
extra_tags = {
  Owner       = "platform-team"
  Purpose     = "production"
  CostCenter  = "CC-001"
  Compliance  = "required"
}
