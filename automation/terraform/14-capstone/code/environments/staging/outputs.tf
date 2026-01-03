# =============================================================================
# environments/staging/outputs.tf
# 预发布环境输出值
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR 块"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "公共子网 ID 列表"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "私有子网 ID 列表"
  value       = module.vpc.private_subnet_ids
}

output "database_subnet_ids" {
  description = "数据库子网 ID 列表"
  value       = module.vpc.database_subnet_ids
}

output "nat_gateway_ips" {
  description = "NAT Gateway 公网 IP 列表"
  value       = module.vpc.nat_gateway_public_ips
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "ALB DNS 名称"
  value       = module.alb.alb_dns_name
}

output "alb_url" {
  description = "ALB 访问 URL"
  value       = module.alb.alb_url
}

output "alb_arn" {
  description = "ALB ARN"
  value       = module.alb.alb_arn
}

# -----------------------------------------------------------------------------
# EC2/ASG
# -----------------------------------------------------------------------------

output "asg_name" {
  description = "Auto Scaling Group 名称"
  value       = module.app.asg_name
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = module.app.launch_template_id
}

output "ec2_security_group_id" {
  description = "EC2 安全组 ID"
  value       = module.app.security_group_id
}

output "ec2_iam_role_arn" {
  description = "EC2 IAM Role ARN"
  value       = module.app.iam_role_arn
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS 端点"
  value       = module.database.db_instance_endpoint
}

output "rds_address" {
  description = "RDS 地址（hostname only）"
  value       = module.database.db_instance_address
}

output "rds_port" {
  description = "RDS 端口"
  value       = module.database.db_instance_port
}

output "rds_database_name" {
  description = "数据库名称"
  value       = module.database.db_name
}

output "rds_password_ssm_parameter" {
  description = "RDS 密码的 SSM Parameter 名称"
  value       = module.database.db_password_ssm_parameter
}

output "rds_connection_string" {
  description = "RDS 连接字符串（不含密码）"
  value       = module.database.connection_string
}

# -----------------------------------------------------------------------------
# 便捷输出
# -----------------------------------------------------------------------------

output "summary" {
  description = "环境概览"
  value = <<-EOT

    ========================================
    Capstone Staging Environment Summary
    ========================================

    ALB URL: ${module.alb.alb_url}

    RDS Endpoint: ${module.database.db_instance_endpoint}
    Database: ${module.database.db_name}
    Username: admin
    Password: aws ssm get-parameter --name "${module.database.db_password_ssm_parameter}" --with-decryption --query "Parameter.Value" --output text

    ASG: ${module.app.asg_name}

    ========================================
    REMEMBER: terraform destroy when done!
    ========================================

  EOT
}
