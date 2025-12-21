# =============================================================================
# 变量定义 - State 安全配置
# Variables - State Security Configuration
# =============================================================================

variable "region" {
  type        = string
  description = "AWS region"
  default     = "ap-northeast-1"
}

variable "project_name" {
  type        = string
  description = "Project name (used in resource naming)"
  default     = "myproject"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens only."
  }
}

variable "terraform_role_arns" {
  type        = list(string)
  description = "ARNs of IAM roles that can access Terraform state"

  # 默认值：当前账户的管理员角色
  # 生产环境应该明确指定允许的角色
  default = []
}

# =============================================================================
# 本地变量
# =============================================================================

locals {
  # 如果没有指定角色，使用账户根用户（仅用于演示）
  terraform_role_arns = length(var.terraform_role_arns) > 0 ? var.terraform_role_arns : [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
}
