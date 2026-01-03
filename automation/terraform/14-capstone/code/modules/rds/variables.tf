# =============================================================================
# modules/rds/variables.tf
# RDS 模块输入变量
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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "database_subnet_ids" {
  description = "数据库子网 ID 列表"
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_ids) >= 2
    error_message = "至少需要 2 个子网以实现高可用"
  }
}

# -----------------------------------------------------------------------------
# 引擎配置
# -----------------------------------------------------------------------------

variable "engine" {
  description = "数据库引擎（mysql, postgres, mariadb）"
  type        = string
  default     = "mysql"

  validation {
    condition     = contains(["mysql", "postgres", "mariadb"], var.engine)
    error_message = "engine 必须是 mysql, postgres 或 mariadb"
  }
}

variable "engine_version" {
  description = "数据库引擎版本"
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "RDS 实例类型"
  type        = string
  default     = "db.t3.micro"
}

# -----------------------------------------------------------------------------
# 存储配置
# -----------------------------------------------------------------------------

variable "allocated_storage" {
  description = "初始存储大小（GB）"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "最大存储大小（GB，0 表示禁用自动扩展）"
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "存储类型"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1"], var.storage_type)
    error_message = "storage_type 必须是 gp2, gp3 或 io1"
  }
}

variable "kms_key_id" {
  description = "KMS Key ID（存储加密）"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# 数据库配置
# -----------------------------------------------------------------------------

variable "db_name" {
  description = "数据库名称"
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "主用户名"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "主用户密码（不设置则自动生成）"
  type        = string
  default     = null
  sensitive   = true
}

variable "store_password_in_ssm" {
  description = "是否将密码存储到 SSM Parameter Store"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# 网络配置
# -----------------------------------------------------------------------------

variable "db_subnet_group_name" {
  description = "已存在的 DB Subnet Group 名称（不指定则创建新的）"
  type        = string
  default     = null
}

variable "app_security_group_id" {
  description = "应用层安全组 ID（允许来自应用的访问）"
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "允许访问的 CIDR 块列表（调试用）"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# 高可用配置
# -----------------------------------------------------------------------------

variable "multi_az" {
  description = "是否启用 Multi-AZ（生产环境推荐）"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# 备份配置
# -----------------------------------------------------------------------------

variable "backup_retention_period" {
  description = "备份保留天数（0 表示禁用）"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "备份时间窗口（UTC）"
  type        = string
  default     = "03:00-04:00" # 日本时间 12:00-13:00
}

variable "maintenance_window" {
  description = "维护时间窗口（UTC）"
  type        = string
  default     = "Mon:04:00-Mon:05:00" # 日本时间周一 13:00-14:00
}

# -----------------------------------------------------------------------------
# Parameter Group 配置
# -----------------------------------------------------------------------------

variable "create_parameter_group" {
  description = "是否创建自定义 Parameter Group"
  type        = bool
  default     = false
}

variable "parameter_group_family" {
  description = "Parameter Group 族（如 mysql8.0, postgres14）"
  type        = string
  default     = "mysql8.0"
}

variable "parameter_group_name" {
  description = "已存在的 Parameter Group 名称"
  type        = string
  default     = null
}

variable "parameters" {
  description = "自定义数据库参数"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

# -----------------------------------------------------------------------------
# 监控配置
# -----------------------------------------------------------------------------

variable "enabled_cloudwatch_logs_exports" {
  description = "导出到 CloudWatch Logs 的日志类型"
  type        = list(string)
  default     = []
  # MySQL: ["audit", "error", "general", "slowquery"]
  # PostgreSQL: ["postgresql", "upgrade"]
}

variable "monitoring_interval" {
  description = "增强监控间隔（秒，0 表示禁用）"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval 必须是 0, 1, 5, 10, 15, 30 或 60"
  }
}

variable "performance_insights_enabled" {
  description = "是否启用 Performance Insights"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# 升级配置
# -----------------------------------------------------------------------------

variable "auto_minor_version_upgrade" {
  description = "是否自动升级小版本"
  type        = bool
  default     = true
}

variable "allow_major_version_upgrade" {
  description = "是否允许大版本升级"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "是否立即应用变更（否则在维护窗口应用）"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# 删除保护
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "是否启用删除保护（生产环境推荐）"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "删除时是否跳过最终快照"
  type        = bool
  default     = true # Dev 环境默认跳过，省钱
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

variable "create_cloudwatch_alarms" {
  description = "是否创建 CloudWatch 告警"
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "告警触发的 SNS Topic ARN 列表"
  type        = list(string)
  default     = []
}

variable "max_connections_threshold" {
  description = "最大连接数告警阈值"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# 标签
# -----------------------------------------------------------------------------

variable "tags" {
  description = "附加标签，会合并到所有资源"
  type        = map(string)
  default     = {}
}
