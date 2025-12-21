# =============================================================================
# 变量定义 - Dev 环境
# =============================================================================

variable "environment" {
  description = "环境名称"
  type        = string
  default     = "dev"
}

variable "bucket_prefix" {
  description = "S3 Bucket 名称前缀"
  type        = string
  default     = "myapp"
}

variable "enable_versioning" {
  description = "是否启用版本控制"
  type        = bool
  default     = false  # dev 环境不需要版本控制
}

variable "lifecycle_days" {
  description = "对象过期天数"
  type        = number
  default     = 7  # dev 环境 7 天后清理
}
