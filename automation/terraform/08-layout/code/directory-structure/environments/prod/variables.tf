# =============================================================================
# 变量定义 - Prod 环境
# =============================================================================

variable "environment" {
  description = "环境名称"
  type        = string
  default     = "prod"
}

variable "bucket_prefix" {
  description = "S3 Bucket 名称前缀"
  type        = string
  default     = "myapp"
}

variable "enable_versioning" {
  description = "是否启用版本控制"
  type        = bool
  default     = true  # prod 必须启用版本控制
}

variable "lifecycle_days" {
  description = "对象过期天数"
  type        = number
  default     = 90  # prod 90 天（或更长/不过期）
}
