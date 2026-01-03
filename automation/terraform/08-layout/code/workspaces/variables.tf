# =============================================================================
# 输入变量定义
# =============================================================================
# Workspaces 模式下，所有环境使用相同的变量定义
# 环境区分主要通过 terraform.workspace 变量实现
# =============================================================================

variable "project_name" {
  description = "项目名称，用于资源命名前缀"
  type        = string
  default     = "demo"
}

variable "bucket_prefix" {
  description = "S3 Bucket 名称前缀"
  type        = string
  default     = "demo-bucket"
}

# =============================================================================
# 环境特定配置
# =============================================================================
# 使用 map 来存储不同环境的配置
# 通过 terraform.workspace 选择对应配置
# =============================================================================

variable "environment_configs" {
  description = "各环境的配置参数"
  type = map(object({
    enable_versioning = bool
    lifecycle_days    = number
  }))
  default = {
    default = {
      enable_versioning = false
      lifecycle_days    = 30
    }
    dev = {
      enable_versioning = false
      lifecycle_days    = 7   # dev 环境 7 天后删除
    }
    staging = {
      enable_versioning = true
      lifecycle_days    = 30  # staging 30 天后删除
    }
    prod = {
      enable_versioning = true
      lifecycle_days    = 90  # prod 90 天后删除
    }
  }
}
