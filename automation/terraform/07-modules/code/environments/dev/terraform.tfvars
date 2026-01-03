# environments/dev/terraform.tfvars
# 开发环境变量

environment    = "dev"
vpc_cidr       = "10.0.0.0/16"
public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
