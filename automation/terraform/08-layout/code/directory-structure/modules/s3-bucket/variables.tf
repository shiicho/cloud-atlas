# =============================================================================
# S3 Bucket 模块 - 输入变量
# =============================================================================

variable "bucket_prefix" {
  description = "S3 Bucket 名称前缀"
  type        = string
}

variable "environment" {
  description = "环境名称 (dev/staging/prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 必须是 dev, staging, 或 prod"
  }
}

variable "enable_versioning" {
  description = "是否启用版本控制"
  type        = bool
  default     = false
}

variable "lifecycle_days" {
  description = "对象过期天数（0 表示不启用生命周期规则）"
  type        = number
  default     = 0

  validation {
    condition     = var.lifecycle_days >= 0
    error_message = "lifecycle_days 必须大于等于 0"
  }
}

variable "tags" {
  description = "额外标签"
  type        = map(string)
  default     = {}
}
