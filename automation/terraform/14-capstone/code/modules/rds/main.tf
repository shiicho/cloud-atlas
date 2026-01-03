# =============================================================================
# modules/rds/main.tf
# RDS 模块 - 创建 RDS 数据库实例及相关资源
# =============================================================================
#
# 本模块创建：
# - RDS Instance (或 Aurora Cluster)
# - DB Subnet Group
# - Security Group
# - Parameter Group
# - Option Group（MySQL/MariaDB）
#
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  # 端口映射
  port_map = {
    mysql    = 3306
    postgres = 5432
    mariadb  = 3306
  }
  port = lookup(local.port_map, var.engine, 3306)

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "rds"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Random Password（如果未提供密码）
# -----------------------------------------------------------------------------

resource "random_password" "master" {
  count = var.master_password == null ? 1 : 0

  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# SSM Parameter（保存密码）
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "master_password" {
  count = var.store_password_in_ssm ? 1 : 0

  name        = "/${var.project}/${var.environment}/rds/master-password"
  description = "RDS master password for ${local.name_prefix}"
  type        = "SecureString"
  value       = var.master_password != null ? var.master_password : random_password.master[0].result

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

# -----------------------------------------------------------------------------
# Security Group
# RDS 安全组 - 只允许来自应用层的访问
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for ${local.name_prefix} RDS"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-rds-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# 入站规则：来自应用层的数据库流量
resource "aws_vpc_security_group_ingress_rule" "from_app" {
  count = var.enable_app_ingress ? 1 : 0

  security_group_id            = aws_security_group.rds.id
  description                  = "Allow database traffic from application layer"
  from_port                    = local.port
  to_port                      = local.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.app_security_group_id

  tags = {
    Name = "${local.name_prefix}-rds-app-ingress"
  }
}

# 入站规则：来自指定 CIDR（可选，用于调试）
resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? length(var.allowed_cidr_blocks) : 0

  security_group_id = aws_security_group.rds.id
  description       = "Allow database traffic from CIDR"
  from_port         = local.port
  to_port           = local.port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_cidr_blocks[count.index]

  tags = {
    Name = "${local.name_prefix}-rds-cidr-ingress-${count.index}"
  }
}

# 出站规则：无需出站
# RDS 实例通常不需要主动出站连接

# -----------------------------------------------------------------------------
# DB Subnet Group
# 定义 RDS 可以部署的子网
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  count = var.db_subnet_group_name == null ? 1 : 0

  name        = "${local.name_prefix}-db-subnet-group"
  description = "Database subnet group for ${local.name_prefix}"
  subnet_ids  = var.database_subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-db-subnet-group"
    }
  )
}

# -----------------------------------------------------------------------------
# DB Parameter Group
# 数据库参数配置
# -----------------------------------------------------------------------------

resource "aws_db_parameter_group" "main" {
  count = var.create_parameter_group ? 1 : 0

  name        = "${local.name_prefix}-db-params"
  family      = var.parameter_group_family
  description = "Database parameter group for ${local.name_prefix}"

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "pending-reboot")
    }
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# RDS Instance
# 主数据库实例
# -----------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db"

  # 引擎配置
  engine               = var.engine
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  parameter_group_name = var.create_parameter_group ? aws_db_parameter_group.main[0].name : var.parameter_group_name

  # 存储配置
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  # 数据库配置
  db_name  = var.db_name
  username = var.master_username
  password = var.master_password != null ? var.master_password : random_password.master[0].result
  port     = local.port

  # 网络配置
  db_subnet_group_name   = var.db_subnet_group_name != null ? var.db_subnet_group_name : aws_db_subnet_group.main[0].name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # 高可用配置
  multi_az = var.multi_az

  # 备份配置
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # 监控配置
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  # 升级配置
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = var.allow_major_version_upgrade
  apply_immediately           = var.apply_immediately

  # 删除保护
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-db-final-snapshot"

  # 其他配置
  copy_tags_to_snapshot = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-db"
    }
  )

  lifecycle {
    ignore_changes = [password] # 密码可能通过其他方式更新
  }
}

# -----------------------------------------------------------------------------
# Enhanced Monitoring IAM Role
# 增强监控需要的 IAM 角色
# -----------------------------------------------------------------------------

resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${local.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# 数据库监控告警
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_description = "RDS CPU utilization is too high"
  alarm_actions     = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "storage" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5GB in bytes

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_description = "RDS free storage space is low"
  alarm_actions     = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.max_connections_threshold

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_description = "RDS connection count is too high"
  alarm_actions     = var.alarm_actions

  tags = local.common_tags
}
