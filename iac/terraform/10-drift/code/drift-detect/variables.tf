# variables.tf
# 输入变量定义
# =============================================================================
#
# 本文件定义可配置的变量，使代码更灵活。
# 可通过 -var、*.tfvars、环境变量等方式覆盖默认值。

variable "environment" {
  description = "环境名称 (dev/staging/prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 必须是 dev、staging 或 prod"
  }
}

variable "instance_name" {
  description = "EC2 实例名称"
  type        = string
  default     = "drift-demo"
}

variable "instance_type" {
  description = "EC2 实例类型"
  type        = string
  default     = "t3.micro"  # 免费层
}

variable "owner" {
  description = "资源所有者（用于标签）"
  type        = string
  default     = "terraform-course"
}
