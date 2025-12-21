# =============================================================================
# modules/vpc/variables.tf
# VPC 模块输入变量
# =============================================================================

# -----------------------------------------------------------------------------
# 必需变量
# -----------------------------------------------------------------------------

variable "project" {
  description = "项目名称，用于资源命名和标签"
  type        = string
}

variable "environment" {
  description = "环境名称（dev/staging/prod）"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 必须是 dev, staging 或 prod"
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR 块（如 10.0.0.0/16）"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr 必须是有效的 CIDR 格式"
  }
}

# -----------------------------------------------------------------------------
# 子网配置
# -----------------------------------------------------------------------------

variable "public_subnets" {
  description = "公共子网 CIDR 列表（用于 ALB、Bastion）"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnets) >= 2
    error_message = "至少需要 2 个公共子网以实现高可用"
  }
}

variable "private_subnets" {
  description = "私有子网 CIDR 列表（用于应用服务器）"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnets) >= 2
    error_message = "至少需要 2 个私有子网以实现高可用"
  }
}

variable "database_subnets" {
  description = "数据库子网 CIDR 列表（用于 RDS）"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# -----------------------------------------------------------------------------
# NAT Gateway 配置
# -----------------------------------------------------------------------------

variable "enable_nat_gateway" {
  description = "是否创建 NAT Gateway（私有子网访问互联网需要）"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = <<-EOT
    是否只创建一个 NAT Gateway（省钱但降低可用性）
    - true: 单 NAT（dev 环境推荐，省钱）
    - false: 每个 AZ 一个 NAT（prod 环境推荐，高可用）
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# VPC Flow Logs 配置
# -----------------------------------------------------------------------------

variable "enable_flow_logs" {
  description = "是否启用 VPC Flow Logs（安全审计需要）"
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "Flow Logs 保留天数"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days 必须是 CloudWatch Logs 支持的保留期"
  }
}

# -----------------------------------------------------------------------------
# 标签
# -----------------------------------------------------------------------------

variable "tags" {
  description = "附加标签，会合并到所有资源"
  type        = map(string)
  default     = {}
}
