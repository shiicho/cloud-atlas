# modules/vpc/outputs.tf
# VPC 模块输出

# -----------------------------------------------------------------------------
# VPC 基本信息
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "VPC ARN"
  value       = aws_vpc.main.arn
}

# -----------------------------------------------------------------------------
# Subnet 信息
# -----------------------------------------------------------------------------

output "public_subnet_ids" {
  description = "公共子网 ID 列表"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "公共子网 CIDR 列表"
  value       = aws_subnet.public[*].cidr_block
}

output "public_subnet_azs" {
  description = "公共子网可用区列表"
  value       = aws_subnet.public[*].availability_zone
}

# -----------------------------------------------------------------------------
# Gateway 信息
# -----------------------------------------------------------------------------

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

# -----------------------------------------------------------------------------
# Route Table 信息
# -----------------------------------------------------------------------------

output "public_route_table_id" {
  description = "公共路由表 ID"
  value       = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# 可用区信息
# -----------------------------------------------------------------------------

output "availability_zones" {
  description = "使用的可用区列表"
  value       = data.aws_availability_zones.available.names
}
