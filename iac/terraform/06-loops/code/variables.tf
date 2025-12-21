# variables.tf
# 变量定义

# -----------------------------------------------------------------------------
# for_each 示例变量
# -----------------------------------------------------------------------------

variable "app_buckets" {
  description = "应用 Buckets 配置（for_each 使用）"
  type = map(object({
    versioning = bool
  }))
  default = {
    api = {
      versioning = true
    }
    web = {
      versioning = false
    }
    data = {
      versioning = true
    }
  }
}

# -----------------------------------------------------------------------------
# count 示例变量（用于演示 Index Shift）
# -----------------------------------------------------------------------------

variable "users" {
  description = "用户列表（count 示例）"
  type        = list(string)
  default     = ["alice", "bob", "charlie"]

  # 实验步骤：
  # 1. 首先 apply 创建用户
  # 2. 在列表中间添加 "david": ["alice", "david", "bob", "charlie"]
  # 3. 运行 plan 观察 Index Shift 问题
}

variable "users_set" {
  description = "用户集合（for_each 示例）"
  type        = set(string)
  default     = ["alice", "bob", "charlie"]
}

# -----------------------------------------------------------------------------
# dynamic block 示例变量
# -----------------------------------------------------------------------------

variable "ingress_rules" {
  description = "Security Group 入站规则"
  type = list(object({
    port        = number
    description = string
    cidr_blocks = optional(list(string), ["0.0.0.0/0"])
  }))
  default = [
    {
      port        = 22
      description = "SSH"
    },
    {
      port        = 80
      description = "HTTP"
    },
    {
      port        = 443
      description = "HTTPS"
    }
  ]
}

# -----------------------------------------------------------------------------
# 环境配置
# -----------------------------------------------------------------------------

variable "environment" {
  description = "部署环境"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "项目名称"
  type        = string
  default     = "loops-demo"
}
