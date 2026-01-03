# =============================================================================
# modules/ec2/variables.tf
# EC2/ASG 模块输入变量
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

variable "private_subnet_ids" {
  description = "私有子网 ID 列表（EC2 部署位置）"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "至少需要 2 个子网以实现高可用"
  }
}

# -----------------------------------------------------------------------------
# 实例配置
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 实例类型"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID（如不指定，使用最新的 Amazon Linux 2023）"
  type        = string
  default     = null
}

variable "ami_ssm_parameter" {
  description = "AMI ID 的 SSM Parameter 名称（可选）"
  type        = string
  default     = null
}

variable "app_port" {
  description = "应用监听端口"
  type        = number
  default     = 80
}

# -----------------------------------------------------------------------------
# EBS 配置
# -----------------------------------------------------------------------------

variable "root_volume_size" {
  description = "根卷大小（GB）"
  type        = number
  default     = 20
}

variable "root_volume_type" {
  description = "根卷类型"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type 必须是 gp2, gp3, io1 或 io2"
  }
}

variable "ebs_optimized" {
  description = "是否启用 EBS 优化"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ASG 配置
# -----------------------------------------------------------------------------

variable "min_size" {
  description = "ASG 最小实例数"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG 最大实例数"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "ASG 期望实例数"
  type        = number
  default     = 2
}

variable "health_check_grace_period" {
  description = "健康检查宽限期（秒）"
  type        = number
  default     = 300
}

variable "instance_warmup" {
  description = "实例预热时间（秒），用于实例刷新"
  type        = number
  default     = 300
}

# -----------------------------------------------------------------------------
# 自动扩缩配置
# -----------------------------------------------------------------------------

variable "enable_autoscaling" {
  description = "是否启用自动扩缩"
  type        = bool
  default     = true
}

variable "scale_up_threshold" {
  description = "扩容 CPU 阈值（%）"
  type        = number
  default     = 70
}

variable "scale_down_threshold" {
  description = "缩容 CPU 阈值（%）"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# 安全组配置
# -----------------------------------------------------------------------------

variable "alb_security_group_id" {
  description = "ALB 安全组 ID（允许来自 ALB 的流量）"
  type        = string
  default     = null
}

variable "enable_alb_ingress" {
  description = "是否启用来自 ALB 的入站规则（解决 count 在 plan 时无法确定的问题）"
  type        = bool
  default     = false
}

variable "enable_ssh_access" {
  description = "是否启用 SSH 访问"
  type        = bool
  default     = false
}

variable "bastion_security_group_id" {
  description = "Bastion 安全组 ID（SSH 来源）"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# IAM 配置
# -----------------------------------------------------------------------------

variable "create_iam_role" {
  description = "是否创建 IAM Role"
  type        = bool
  default     = true
}

variable "iam_instance_profile_arn" {
  description = "已存在的 IAM Instance Profile ARN"
  type        = string
  default     = null
}

variable "enable_cloudwatch_agent" {
  description = "是否启用 CloudWatch Agent"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# 监控配置
# -----------------------------------------------------------------------------

variable "enable_detailed_monitoring" {
  description = "是否启用详细监控（1 分钟粒度）"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# 目标组
# -----------------------------------------------------------------------------

variable "target_group_arns" {
  description = "ALB 目标组 ARN 列表"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# User Data
# -----------------------------------------------------------------------------

variable "user_data" {
  description = "自定义 User Data 脚本"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# 标签
# -----------------------------------------------------------------------------

variable "tags" {
  description = "附加标签，会合并到所有资源"
  type        = map(string)
  default     = {}
}
