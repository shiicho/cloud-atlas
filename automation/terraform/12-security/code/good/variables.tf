# =============================================================================
# 变量定义 - 最佳实践示例
# Variables - Best Practice Example
# =============================================================================

# =============================================================================
# 基础配置
# =============================================================================

variable "region" {
  type        = string
  description = "AWS region to deploy resources"
  default     = "ap-northeast-1"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/staging/prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# =============================================================================
# 网络配置
# =============================================================================

variable "vpc_id" {
  type        = string
  description = "VPC ID (leave empty to use default VPC)"
  default     = ""
}

variable "use_private_subnets" {
  type        = bool
  description = "Whether to filter for private subnets by tag"
  default     = false
}

variable "allowed_db_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access the database"
  default     = ["10.0.0.0/8"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_db_cidr_blocks : can(cidrnetmask(cidr))
    ])
    error_message = "All values must be valid CIDR blocks."
  }
}

# =============================================================================
# 数据库配置
# =============================================================================

variable "db_username" {
  type        = string
  description = "Database admin username"
  default     = "admin"
}

# 注意：密码不在这里定义！
# 密码从 SSM Parameter Store 动态获取
# 这是正确的做法：代码中不包含任何密钥值

variable "db_instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  type        = number
  description = "Allocated storage in GB"
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_kms_key_id" {
  type        = string
  description = "KMS key ID for RDS encryption (optional, uses AWS managed key if not specified)"
  default     = null
}

# =============================================================================
# SSM 参数路径配置
# =============================================================================
#
# 密钥存储约定：
# /myapp/{environment}/db/password     - 数据库密码
# /myapp/{environment}/api_key         - 第三方 API 密钥
# /myapp/{environment}/jwt_secret      - JWT 签名密钥
#
# 由安全团队/运维人员预先创建这些参数：
#
# aws ssm put-parameter \
#   --name "/myapp/prod/db/password" \
#   --value "实际的密码" \
#   --type "SecureString" \
#   --description "Production database password"
#
# =============================================================================
