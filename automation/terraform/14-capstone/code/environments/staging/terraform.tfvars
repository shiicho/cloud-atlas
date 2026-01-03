# =============================================================================
# environments/staging/terraform.tfvars
# 预发布环境变量值
# =============================================================================
#
# Staging 环境配置特点：
# - VPC CIDR: 10.1.0.0/16（与 Dev 10.0.0.0/16、Prod 10.2.0.0/16 区分）
# - ASG 规模: 2-4（比 Dev 大，接近 Prod）
# - 备份保留: 7 天
# - Flow Logs: 启用
#
# =============================================================================

# 通用配置
aws_region = "ap-northeast-1"
owner      = "your-name" # 修改为你的名字

# VPC 配置 - Staging 使用 10.1.0.0/16
vpc_cidr         = "10.1.0.0/16"
public_subnets   = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnets  = ["10.1.11.0/24", "10.1.12.0/24"]
database_subnets = ["10.1.21.0/24", "10.1.22.0/24"]

# EC2/ASG 配置 - Staging 规模稍大
app_instance_type    = "t3.micro"
app_min_size         = 2
app_max_size         = 4
app_desired_capacity = 2

# RDS 配置
db_engine            = "mysql"
db_engine_version    = "8.0"
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20
db_name              = "appdb"
db_username          = "admin"
