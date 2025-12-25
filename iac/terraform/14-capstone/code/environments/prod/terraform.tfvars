# =============================================================================
# environments/prod/terraform.tfvars
# 生产环境变量值
# =============================================================================
#
# Production 环境配置特点：
# - VPC CIDR: 10.2.0.0/16（与 Dev 10.0.0.0/16、Staging 10.1.0.0/16 区分）
# - NAT Gateway: 每 AZ 一个（高可用）
# - RDS Multi-AZ: 启用（数据库高可用）
# - 删除保护: 启用
# - 备份保留: 30 天
# - 实例规格: t3.small（比 Dev/Staging 大）
#
# ⚠️ 成本警告：Prod 环境成本显著高于 Dev/Staging！
#
# =============================================================================

# 通用配置
aws_region = "ap-northeast-1"
owner      = "your-name" # 修改为你的名字

# VPC 配置 - Prod 使用 10.2.0.0/16
vpc_cidr         = "10.2.0.0/16"
public_subnets   = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnets  = ["10.2.11.0/24", "10.2.12.0/24"]
database_subnets = ["10.2.21.0/24", "10.2.22.0/24"]

# EC2/ASG 配置 - Prod 使用更大实例和规模
app_instance_type    = "t3.small"
app_min_size         = 2
app_max_size         = 6
app_desired_capacity = 2

# RDS 配置 - Prod 使用更大实例和存储
db_engine            = "mysql"
db_engine_version    = "8.0"
db_instance_class    = "db.t3.small"
db_allocated_storage = 50
db_name              = "appdb"
db_username          = "admin"
