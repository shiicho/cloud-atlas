# =============================================================================
# modules/alb/variables.tf
# ALB 模块输入变量
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

variable "public_subnet_ids" {
  description = "公共子网 ID 列表（ALB 部署位置）"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "ALB 至少需要 2 个子网以实现高可用"
  }
}

# -----------------------------------------------------------------------------
# 目标组配置
# -----------------------------------------------------------------------------

variable "target_port" {
  description = "目标端口（应用监听端口）"
  type        = number
  default     = 80
}

# -----------------------------------------------------------------------------
# 健康检查配置
# -----------------------------------------------------------------------------

variable "health_check_path" {
  description = "健康检查路径"
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "健康检查成功的 HTTP 状态码"
  type        = string
  default     = "200"
}

variable "health_check_interval" {
  description = "健康检查间隔（秒）"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "健康检查超时（秒）"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "连续成功次数判定为健康"
  type        = number
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  description = "连续失败次数判定为不健康"
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# HTTPS 配置（可选）
# -----------------------------------------------------------------------------

variable "certificate_arn" {
  description = "ACM 证书 ARN（启用 HTTPS）"
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "SSL 策略"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

# -----------------------------------------------------------------------------
# 目标组其他配置
# -----------------------------------------------------------------------------

variable "deregistration_delay" {
  description = "目标注销延迟（秒）"
  type        = number
  default     = 300
}

variable "stickiness_enabled" {
  description = "是否启用 Session Stickiness"
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Stickiness Cookie 有效期（秒）"
  type        = number
  default     = 86400
}

# -----------------------------------------------------------------------------
# ALB 其他配置
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = "是否启用删除保护（生产环境推荐）"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "访问日志 S3 Bucket 名称（启用访问日志）"
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "访问日志 S3 前缀"
  type        = string
  default     = "alb-logs"
}

# -----------------------------------------------------------------------------
# 标签
# -----------------------------------------------------------------------------

variable "tags" {
  description = "附加标签，会合并到所有资源"
  type        = map(string)
  default     = {}
}
