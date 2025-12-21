# modules/vpc/variables.tf
# VPC 模块输入变量

variable "environment" {
  description = "环境名称（dev/staging/prod）"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 必须是 dev、staging 或 prod"
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr 必须是有效的 CIDR 格式"
  }
}

variable "public_subnets" {
  description = "公共子网 CIDR 列表"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "enable_dns" {
  description = "启用 DNS 支持和主机名"
  type        = bool
  default     = true
}

variable "enable_nat" {
  description = "是否创建 NAT Gateway（生产环境推荐启用）"
  type        = bool
  default     = false
}

variable "tags" {
  description = "额外标签"
  type        = map(string)
  default     = {}
}
