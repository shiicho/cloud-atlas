# terraform.tfvars
# 默认变量值（自动加载）
#
# 此文件会被 terraform 自动加载，无需 -var-file 指定。
# 适合放置所有环境共享的默认配置。

# 项目名称
project = "myapp"

# AWS 区域
aws_region = "ap-northeast-1"

# 默认启用版本控制
enable_versioning = true

# 默认启用加密
enable_encryption = true

# 各环境实例类型
instance_types = {
  dev     = "t3.micro"
  staging = "t3.small"
  prod    = "t3.medium"
}

# 允许的 IP 段
allowed_ips = [
  "10.0.0.0/8",
  "192.168.0.0/16"
]
