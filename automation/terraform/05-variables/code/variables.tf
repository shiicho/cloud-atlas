# variables.tf
# 变量定义
#
# 本文件演示：
# 1. 基本类型（string, number, bool）
# 2. 复杂类型（list, map, object）
# 3. 验证规则（validation）
# 4. 敏感变量（sensitive）

# -----------------------------------------------------------------------------
# 基本变量
# -----------------------------------------------------------------------------

variable "project" {
  description = "项目名称，用于资源命名"
  type        = string
  default     = "myapp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project))
    error_message = "project 必须以小写字母开头，只能包含小写字母、数字、连字符"
  }
}

variable "environment" {
  description = "部署环境（dev/staging/prod）"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 必须是 dev、staging 或 prod"
  }
}

variable "aws_region" {
  description = "AWS 区域"
  type        = string
  default     = "ap-northeast-1"
}

# -----------------------------------------------------------------------------
# 数字类型
# -----------------------------------------------------------------------------

variable "instance_count" {
  description = "实例数量"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "instance_count 必须在 1-10 之间"
  }
}

variable "lifecycle_days" {
  description = "S3 对象生命周期天数（0 表示不启用）"
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# 布尔类型
# -----------------------------------------------------------------------------

variable "enable_versioning" {
  description = "是否启用 S3 版本控制"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "是否启用 S3 加密"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# 列表类型
# -----------------------------------------------------------------------------

variable "allowed_ips" {
  description = "允许访问的 IP 列表"
  type        = list(string)
  default     = ["10.0.0.0/8", "192.168.0.0/16"]

  validation {
    condition     = length(var.allowed_ips) > 0
    error_message = "allowed_ips 至少需要一个 IP 段"
  }
}

variable "tags_list" {
  description = "额外标签列表"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Map 类型
# -----------------------------------------------------------------------------

variable "instance_types" {
  description = "各环境的实例类型"
  type        = map(string)
  default = {
    dev     = "t3.micro"
    staging = "t3.small"
    prod    = "t3.medium"
  }
}

variable "extra_tags" {
  description = "额外标签（键值对）"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Object 类型
# -----------------------------------------------------------------------------

variable "bucket_config" {
  description = "S3 Bucket 配置对象"
  type = object({
    versioning     = bool
    encryption     = bool
    lifecycle_days = number
  })
  default = {
    versioning     = true
    encryption     = true
    lifecycle_days = 90
  }
}

# -----------------------------------------------------------------------------
# 敏感变量
# -----------------------------------------------------------------------------

variable "db_password" {
  description = "数据库密码（演示敏感变量）"
  type        = string
  default     = ""
  sensitive   = true

  # 注意：sensitive = true 只是隐藏 CLI 输出
  # 值仍然明文存储在 State 中！
  # 真正的密钥应使用 SSM Parameter Store 或 Secrets Manager
}

# -----------------------------------------------------------------------------
# 变量使用说明
# -----------------------------------------------------------------------------
#
# 1. 命令行指定：
#    terraform plan -var='project=myapp'
#
# 2. 环境变量：
#    export TF_VAR_project=myapp
#
# 3. tfvars 文件：
#    terraform plan -var-file=envs/dev.tfvars
#
# 4. 自动加载（无需 -var-file）：
#    - terraform.tfvars
#    - *.auto.tfvars
#
# -----------------------------------------------------------------------------
