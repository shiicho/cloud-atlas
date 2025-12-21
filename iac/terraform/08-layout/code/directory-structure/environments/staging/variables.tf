# =============================================================================
# 变量定义 - Staging 环境
# =============================================================================

variable "environment" {
  description = "环境名称"
  type        = string
  default     = "staging"
}

variable "bucket_prefix" {
  description = "S3 Bucket 名称前缀"
  type        = string
  default     = "myapp"
}

variable "enable_versioning" {
  description = "是否启用版本控制"
  type        = bool
  default     = true  # staging 启用版本控制（模拟 prod）
}

variable "lifecycle_days" {
  description = "对象过期天数"
  type        = number
  default     = 30  # staging 30 天后清理
}
