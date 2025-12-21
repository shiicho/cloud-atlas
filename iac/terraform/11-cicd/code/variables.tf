# variables.tf
# 输入变量定义
#
# 本文件定义 CI/CD 示例项目使用的变量。
# 变量值可以通过 terraform.tfvars、环境变量或 CI/CD 流水线传入。

# =============================================================================
# 基础配置
# =============================================================================

variable "aws_region" {
  description = "AWS 区域"
  type        = string
  default     = "ap-northeast-1"  # 东京
}

variable "environment" {
  description = "环境名称 (dev, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment 必须是 dev, staging 或 production"
  }
}

# =============================================================================
# 资源配置
# =============================================================================

variable "project_name" {
  description = "项目名称，用于资源命名前缀"
  type        = string
  default     = "cicd-example"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "project_name 必须以小写字母开头，只能包含小写字母、数字和连字符"
  }
}

variable "enable_versioning" {
  description = "是否启用 S3 Bucket 版本控制"
  type        = bool
  default     = true
}

# =============================================================================
# 标签
# =============================================================================

variable "additional_tags" {
  description = "附加标签（合并到 default_tags）"
  type        = map(string)
  default     = {}
}
