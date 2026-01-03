# =============================================================================
# modules/vpc/outputs.tf
# VPC 模块输出值
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR 块"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "VPC ARN"
  value       = aws_vpc.main.arn
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

output "public_subnet_ids" {
  description = "公共子网 ID 列表"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "公共子网 CIDR 列表"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_ids" {
  description = "私有子网 ID 列表"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "私有子网 CIDR 列表"
  value       = aws_subnet.private[*].cidr_block
}

output "database_subnet_ids" {
  description = "数据库子网 ID 列表"
  value       = aws_subnet.database[*].id
}

output "database_subnet_cidrs" {
  description = "数据库子网 CIDR 列表"
  value       = aws_subnet.database[*].cidr_block
}

output "database_subnet_group_name" {
  description = "RDS 子网组名称"
  value       = length(aws_db_subnet_group.database) > 0 ? aws_db_subnet_group.database[0].name : null
}

# -----------------------------------------------------------------------------
# Availability Zones
# -----------------------------------------------------------------------------

output "availability_zones" {
  description = "使用的可用区列表"
  value       = local.azs
}

# -----------------------------------------------------------------------------
# Gateways
# -----------------------------------------------------------------------------

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway ID 列表"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway 公网 IP 列表"
  value       = aws_eip.nat[*].public_ip
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------

output "public_route_table_id" {
  description = "公共路由表 ID"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "私有路由表 ID 列表"
  value       = aws_route_table.private[*].id
}

output "database_route_table_id" {
  description = "数据库路由表 ID"
  value       = length(aws_route_table.database) > 0 ? aws_route_table.database[0].id : null
}

# -----------------------------------------------------------------------------
# Flow Logs
# -----------------------------------------------------------------------------

output "flow_log_id" {
  description = "VPC Flow Log ID"
  value       = length(aws_flow_log.main) > 0 ? aws_flow_log.main[0].id : null
}

output "flow_log_cloudwatch_log_group" {
  description = "Flow Logs CloudWatch Log Group 名称"
  value       = length(aws_cloudwatch_log_group.flow_log) > 0 ? aws_cloudwatch_log_group.flow_log[0].name : null
}
