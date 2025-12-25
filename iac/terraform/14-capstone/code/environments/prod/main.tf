# =============================================================================
# environments/prod/main.tf
# 生产环境 - 三层 Web 架构
# =============================================================================
#
# Production 环境特点（高可用、安全、合规）：
# - Multi-AZ NAT Gateway（高可用）
# - Multi-AZ RDS（数据库高可用）
# - 启用删除保护（防止误删）
# - 启用 Flow Logs（安全审计）
# - 备份保留 30 天
# - 详细监控启用
#
# 成本影响（相比 Dev）：
# - NAT Gateway: ~$64/月（每 AZ 一个）vs Dev $32/月
# - RDS Multi-AZ: ~$30/月 vs Dev $15/月
# - EC2 (t3.small x 2): ~$40/月 vs Dev (t3.micro x 2) $20/月
#
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  project     = "capstone"
  environment = "prod"

  # 通用标签
  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = "production"
  }
}

# -----------------------------------------------------------------------------
# VPC Module
# 网络基础设施
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  project     = local.project
  environment = local.environment
  vpc_cidr    = var.vpc_cidr

  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  database_subnets = var.database_subnets

  # Prod 环境使用每 AZ 一个 NAT（高可用）
  enable_nat_gateway = true
  single_nat_gateway = false # 每 AZ 一个 NAT

  # Prod 环境启用 Flow Logs
  enable_flow_logs = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# ALB Module
# 负载均衡器
# -----------------------------------------------------------------------------

module "alb" {
  source = "../../modules/alb"

  project           = local.project
  environment       = local.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  # 目标配置
  target_port = 80

  # 健康检查
  health_check_path    = "/health"
  health_check_matcher = "200"

  # Prod 环境启用删除保护
  enable_deletion_protection = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EC2/ASG Module
# 应用服务器
# -----------------------------------------------------------------------------

module "app" {
  source = "../../modules/ec2"

  project            = local.project
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  # 实例配置 - Prod 使用更大实例
  instance_type    = var.app_instance_type
  root_volume_size = 30

  # ASG 配置 - Prod 规模更大
  min_size         = var.app_min_size
  max_size         = var.app_max_size
  desired_capacity = var.app_desired_capacity

  # 连接到 ALB
  target_group_arns     = [module.alb.target_group_arn]
  alb_security_group_id = module.alb.security_group_id

  # 自动扩缩
  enable_autoscaling   = true
  scale_up_threshold   = 70
  scale_down_threshold = 30

  # Prod 环境启用详细监控
  enable_detailed_monitoring = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# RDS Module
# 数据库
# -----------------------------------------------------------------------------

module "database" {
  source = "../../modules/rds"

  project             = local.project
  environment         = local.environment
  vpc_id              = module.vpc.vpc_id
  database_subnet_ids = module.vpc.database_subnet_ids

  # 引擎配置
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # 存储配置 - Prod 更大存储
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100

  # 数据库配置
  db_name         = var.db_name
  master_username = var.db_username

  # 网络安全
  app_security_group_id = module.app.security_group_id

  # Prod 环境配置（高可用、数据保护）
  multi_az                = true  # 高可用
  backup_retention_period = 30    # 30 天备份
  skip_final_snapshot     = false # 删除时创建快照

  # 删除保护 - Prod 环境启用
  deletion_protection = true

  tags = local.common_tags
}
