# =============================================================================
# environments/dev/variables.tf
# 开发环境变量定义
# =============================================================================

# -----------------------------------------------------------------------------
# 通用变量
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS 区域"
  type        = string
  default     = "ap-northeast-1"
}

variable "owner" {
  description = "资源所有者（用于标签）"
  type        = string
  default     = "your-name"
}

# -----------------------------------------------------------------------------
# VPC 变量
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR 块"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "公共子网 CIDR 列表"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "私有子网 CIDR 列表"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "database_subnets" {
  description = "数据库子网 CIDR 列表"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# -----------------------------------------------------------------------------
# EC2/ASG 变量
# -----------------------------------------------------------------------------

variable "app_instance_type" {
  description = "应用服务器实例类型"
  type        = string
  default     = "t3.micro"
}

variable "app_min_size" {
  description = "ASG 最小实例数"
  type        = number
  default     = 1
}

variable "app_max_size" {
  description = "ASG 最大实例数"
  type        = number
  default     = 3
}

variable "app_desired_capacity" {
  description = "ASG 期望实例数"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# RDS 变量
# -----------------------------------------------------------------------------

variable "db_engine" {
  description = "数据库引擎"
  type        = string
  default     = "mysql"
}

variable "db_engine_version" {
  description = "数据库引擎版本"
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS 实例类型"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS 存储大小（GB）"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "数据库名称"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "数据库用户名"
  type        = string
  default     = "admin"
}
