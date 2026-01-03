# environments/prod/terraform.tfvars
# 生产环境变量

environment    = "prod"
vpc_cidr       = "10.1.0.0/16"
public_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
