# =============================================================================
# environments/dev/main.tf
# 开发环境 - 三层 Web 架构
# =============================================================================
#
# 本配置组装所有模块，创建完整的三层架构：
# - 网络层：VPC + Subnets + NAT
# - 表示层：ALB
# - 应用层：EC2 Auto Scaling Group
# - 数据层：RDS MySQL
#
# 成本预估（如果及时清理）：
# - VPC/Subnets: 免费
# - NAT Gateway: ~$32/月 (~$1/天)
# - ALB: ~$16/月 (~$0.5/天)
# - EC2 (2 x t3.micro): ~$20/月 (~$0.7/天)
# - RDS (db.t3.micro): ~$15/月 (~$0.5/天)
# - 总计: ~$3/天，一周约 $20
#
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  project     = "capstone"
  environment = "dev"

  # 通用标签
  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = "training"
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

  # Dev 环境使用单 NAT 省钱
  enable_nat_gateway = true
  single_nat_gateway = true

  # Dev 环境可以不启用 Flow Logs 省钱
  enable_flow_logs = false

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

  # Dev 环境不启用删除保护
  enable_deletion_protection = false

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

  # 实例配置 - Dev 使用小实例
  instance_type    = var.app_instance_type
  root_volume_size = 20

  # ASG 配置 - Dev 使用最小规模
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

  # Dev 环境不启用详细监控省钱
  enable_detailed_monitoring = false

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

  # 存储配置 - Dev 使用最小存储
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 50

  # 数据库配置
  db_name         = var.db_name
  master_username = var.db_username

  # 网络安全
  app_security_group_id = module.app.security_group_id

  # Dev 环境配置
  multi_az                = false # 省钱
  backup_retention_period = 1     # 最小备份保留
  skip_final_snapshot     = true  # 删除时不创建快照

  # 删除保护 - Dev 环境禁用
  deletion_protection = false

  tags = local.common_tags
}
