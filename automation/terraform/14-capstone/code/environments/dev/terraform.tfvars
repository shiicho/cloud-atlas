# =============================================================================
# environments/dev/terraform.tfvars
# 开发环境变量值
# =============================================================================

# 通用配置
aws_region = "ap-northeast-1"
owner      = "your-name"  # 修改为你的名字

# VPC 配置
vpc_cidr         = "10.0.0.0/16"
public_subnets   = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets  = ["10.0.11.0/24", "10.0.12.0/24"]
database_subnets = ["10.0.21.0/24", "10.0.22.0/24"]

# EC2/ASG 配置 - Dev 使用最小规模
app_instance_type    = "t3.micro"
app_min_size         = 1
app_max_size         = 3
app_desired_capacity = 2

# RDS 配置 - Dev 使用最小规格
db_engine            = "mysql"
db_engine_version    = "8.0"
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20
db_name              = "appdb"
db_username          = "admin"
